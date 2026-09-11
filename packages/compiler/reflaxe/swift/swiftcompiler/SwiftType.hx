package swiftcompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;
import StructuralKeyValidator;
import PolicyQueries;

/**
    Type mapping from the translatable Haxe subset to Swift, per
    docs/specs/features/07-numeric-tower.md and the stdlib rulings: Int is Int32 and
    Float is Double (numbers ruling), haxe.io.Bytes is the byte array
    (stdlib/01), haxe.io.BytesBuffer is the runtime growth class
    (stdlib/02), ReadOnlyArray is a let-bound Array (features/18). The
    resident string ABI (docs/specs/features/08-strings-and-unicode.md) renders String as Array<UInt16>
    inside resident modules; business modules keep native String and
    convert once at the resident boundary.
**/
class SwiftType {
    final imports:SwiftImports;

    /** Resident modules render String as the unit array of the runtime ABI. */
    public final resident:Bool;

    public function new(imports:SwiftImports) {
        this.imports = imports;
        this.resident = RuntimeResidents.isResident(imports.selfModule);
    }

    /**
        A zero-argument `Void` callback is the thunk shape the test harness
        passes around; Haxe function types carry no throw bit, so the
        emitted type always admits a throwing closure body.
    **/
    public static function isThrowingThunk(t:Null<Type>):Bool {
        if (t == null)
            return false;
        return switch (Context.follow(t)) {
            case TFun(args, ret): isThrowingThunkType(args.length, ret);
            case _: false;
        };
    }

    static function isThrowingThunkType(argCount:Int, ret:Type):Bool {
        return argCount == 0 && isVoidType(ret);
    }

    static function isVoidType(t:Type):Bool {
        return switch (Context.follow(t)) {
            case TAbstract(a, _): a.get().name == "Void";
            case _: false;
        };
    }

    public function of(t:Null<Type>):String {
        if (t == null) {
            return "Void";
        }
        return switch (t) {
            case TAbstract(a, params):
                final abs = a.get();
                if (ValueTypeSupport.isMarkedAbstract(abs)) {
                    abs.name;
                } else switch (pathOf(abs.pack, abs.name)) {
                    case "Int": "Int32";
                    // The f32 configuration maps the module real onto the native
                    // binary32 type (feature spec 23).
                    case "Float": FloatPrecision.isF32() ? "Float" : "Double";
                    case "Bool": "Bool";
                    case "Void": "Void";
                    case "Null": nullOptional(params[0], of);
                    case "haxe.ds.Map" if (params.length == 2): "[" + of(params[0]) + ": " + of(params[1]) + "]";
                    case "std.ReadOnlyArray": "[" + of(params[0]) + "]";
                    case "haxe.Int64": "Int64";
                    case _: of(abs.type);
                }
            case TInst(c, params):
                final cls = c.get();
                switch (pathOf(cls.pack, cls.name)) {
                    // The shared exception base maps to the runtime class the
                    // generated exception subclasses extend (features/06).
                    case "haxe.Exception":
                        imports.runtime("BoringException");
                        "BoringException";
                    case "String": resident ? "[UInt16]" : "String";
                    case "std.StringBuf" | "StringBuf": "[UInt16]";
                    case "Array": "[" + of(params[0]) + "]";
                    case "haxe.io.Bytes": "[UInt8]";
                    case "haxe.io.BytesBuffer":
                        imports.runtime("BytesBuffer");
                        "BytesBuffer";
                    case "std.SortedMap":
                        imports.runtime("SortedMapTable");
                        // Haxe folds Null<Null<V>> into Null<V>, and the runtime
                        // get returns Null<V>; keeping the inner Null in the value
                        // parameter would make get return V??. One optional layer
                        // stays, carried by get.
                        "SortedMapTable<" + of(params[0]) + ", " + of(DefaultArgExpander.withoutNull(params[1])) + ">";
                    case "std.SortedMapBuilder":
                        imports.runtime("SortedMapTableBuilder");
                        "SortedMapTableBuilder<" + of(params[0]) + ", " + of(DefaultArgExpander.withoutNull(params[1])) + ">";
                    case "std.SortedSet":
                        imports.runtime("SortedSetTable");
                        "SortedSetTable<" + of(params[0]) + ">";
                    case "std.SortedSetBuilder":
                        imports.runtime("SortedSetTableBuilder");
                        "SortedSetTableBuilder<" + of(params[0]) + ">";
                    case _:
                        imports.value(cls.module, cls.name);
                        // A generic class referenced with its arguments
                        // carries them; Swift binds the bare name to
                        // <Any, Any>, so the arguments always render.
                        params.length > 0 ? cls.name + "<" + [for (p in params) of(p)].join(", ") + ">" : cls.name;
                }
            case TType(def, params):
                final d = def.get();
                if (d.pack.join(".") == "haxe.io" && d.name == "Bytes") {
                    "[UInt8]";
                } else if (d.pack.length == 0 && d.name == "Map" && params.length == 2) {
                    "[" + of(params[0]) + ": " + of(params[1]) + "]";
                } else if (RuntimeResidents.isResident(d.module) && params.length > 0) {
                    // A resident named function type expands inline with its
                    // arguments applied; Swift typealiases carry no generic
                    // parameters here, so the function type renders directly.
                    ofSubstituted(d.type, d.params, params);
                } else if (params.length == 0) {
                    imports.type(d.module, d.name);
                    d.name;
                } else {
                    fail(t);
                }
            case TEnum(e, _):
                final en = e.get();
                imports.type(en.module, en.name);
                en.name;
            case TFun(args, ret):
                "(" + [for (arg in args) of(arg.t)].join(", ") + ")" + (isThrowingThunkType(args.length, ret) ? " throws" : "") + " -> " + of(ret);
            case TAnonymous(_):
                Context.error("anonymous structure types must be named typedefs before translation", Context.currentPos());
                null;
            case TDynamic(_) | TMono(_):
                fail(t);
            case TLazy(f): of(f());
        }
    }

    /**
        Renders a type with its type parameters replaced by applied
        arguments: the comparator alias of the sorted-table resident
        reaches its fields as a typedef applied to the class parameters.
    **/
    function ofSubstituted(t:Type, params:Array<TypeParameter>, args:Array<Type>):String {
        return switch (t) {
            case TAbstract(a, params2):
                final abs = a.get();
                for (i in 0...params.length) {
                    if (params[i].name == abs.name) {
                        return of(args[i]);
                    }
                }
                switch (pathOf(abs.pack, abs.name)) {
                    case "Int": "Int32";
                    // The f32 configuration maps the module real onto the native
                    // binary32 type (feature spec 23).
                    case "Float": FloatPrecision.isF32() ? "Float" : "Double";
                    case "Bool": "Bool";
                    case "Void": "Void";
                    case "Null": nullOptional(params2[0], t -> ofSubstituted(t, params, args));
                    case "std.ReadOnlyArray": "[" + ofSubstituted(params2[0], params, args) + "]";
                    case _: ofSubstituted(abs.type, params, args);
                }
            case TInst(c, params2):
                final cls = c.get();
                switch (pathOf(cls.pack, cls.name)) {
                    case "String": resident ? "[UInt16]" : "String";
                    case "std.StringBuf" | "StringBuf": "[UInt16]";
                    case "Array": "[" + ofSubstituted(params2[0], params, args) + "]";
                    case "haxe.io.Bytes": "[UInt8]";
                    case _:
                        for (i in 0...params.length) {
                            if (params[i].name == cls.name) {
                                return of(args[i]);
                            }
                        }
                        switch (cls.kind) {
                            case KTypeParameter(_): of(args[resolveParam(params, cls.name)]);
                            case _: cls.name;
                        }
                }
            case TType(def, params2):
                final d = def.get();
                if (RuntimeResidents.isResident(d.module) && params2.length > 0) {
                    ofSubstituted(d.type, d.params, [for (p in params2) substituteType(p, params, args)]);
                } else if (params2.length == 0) {
                    imports.type(d.module, d.name);
                    d.name;
                } else {
                    fail(t);
                }
            case TEnum(e, _):
                final en = e.get();
                imports.type(en.module, en.name);
                en.name;
            case TFun(args2, ret):
                "(" + [for (arg in args2) ofSubstituted(arg.t, params, args)].join(", ") + ")"
                    + (isThrowingThunkType(args2.length, ret) ? " throws" : "") + " -> " + ofSubstituted(ret, params, args);
            case TLazy(f): ofSubstituted(f(), params, args);
            case _: fail(t);
        }
    }

    static function resolveParam(params:Array<TypeParameter>, name:String):Int {
        for (i in 0...params.length) {
            if (params[i].name == name) {
                return i;
            }
        }
        return 0;
    }

    /**
        Type parameter substitution, the structure-preserving counterpart
        of `ofSubstituted`: rebuilds a type with its parameters replaced
        by applied arguments so a nested alias application carries real
        types, with no rendered-text substitution.
    **/
    static function substituteType(t:Type, params:Array<TypeParameter>, args:Array<Type>):Type {
        return switch (t) {
            case TAbstract(a, ps):
                final abs = a.get();
                for (i in 0...params.length) {
                    if (params[i].name == abs.name) {
                        return args[i];
                    }
                }
                TAbstract(a, [for (p in ps) substituteType(p, params, args)]);
            case TInst(c, ps):
                final cls = c.get();
                switch (cls.kind) {
                    case KTypeParameter(_):
                        args[resolveParam(params, cls.name)];
                    case _:
                        TInst(c, [for (p in ps) substituteType(p, params, args)]);
                }
            case TType(d, ps):
                TType(d, [for (p in ps) substituteType(p, params, args)]);
            case TEnum(e, ps):
                TEnum(e, [for (p in ps) substituteType(p, params, args)]);
            case TFun(fargs, ret):
                TFun([
                    for (a in fargs)
                        {name: a.name, t: substituteType(a.t, params, args), opt: a.opt}
                ], substituteType(ret, params, args));
            case TLazy(f):
                substituteType(f(), params, args);
            case _:
                t;
        }
    }

    /**
        Optional rendering: a nested optional never occurs in the subset,
        but the spelled-out form keeps the shape total. Optionals of
        function types parenthesize.
    **/
    function wrapOptional(inner:String):String {
        return inner + "?";
    }

    /**
        Haxe's ternary and map inference can nest the Null wrapper
        (`Null<Null<T>>`); one `?` is enough, and a doubled Swift
        `T??` changes what a later force unwrap reads.
    **/
    function nullOptional(inner:Type, render:Type->String):String {
        return switch (inner) {
            case TAbstract(a, _) if (a.get().name == "Null"): render(inner);
            case TLazy(f): nullOptional(f(), render);
            case _: wrapOptional(render(inner));
        };
    }

    /**
        A standalone Swift nil must carry its optional payload type. Haxe's
        TNull expression retains that payload in its type, but Swift cannot
        infer it in conditional expressions and a few synthesized argument
        positions. Keep the spelling explicit at those boundaries.
    **/
    public function optionalNone(t:Null<Type>):String {
        return switch (t) {
            case TAbstract(a, params) if (a.get().name == "Null" && params.length == 1):
                switch (Context.follow(params[0])) {
                    case TMono(_): "nil";
                    case _: "Optional<" + of(params[0]) + ">.none";
                };
            case TLazy(f): optionalNone(f());
            case _: "nil";
        };
    }

    function pathOf(pack:Array<String>, name:String):String {
        return PolicyQueries.pathOf(pack, name);
    }

    public static function classifyKey(t:Null<Type>, ?pos:haxe.macro.Expr.Position):KeyDomain {
        return PolicyQueries.classifyKey(t, pos);
    }

    static function validateDataClassField(cls:ClassType, field:ClassField, path:String):Void {
        PolicyQueries.validateDataClassField(cls, field, path);
    }

    public static function canEmitDataClassComparator(cls:ClassType):Bool {
        return comparatorFieldsSupported(cls, []);
    }

    /**
        Whether `t` renders as a Swift class whose `==` is not
        synthesized. Ordinary classes and runtime collection classes
        compare by reference in Haxe; a data class carries an emitted
        comparator and a value type uses its own `==`, so those keep the
        native operator.
    **/
    public function usesIdentityEquality(t:Null<Type>):Bool {
        if (t == null) {
            return false;
        }
        return switch (Context.follow(t)) {
            case TInst(c, _):
                final cls = c.get();
                if (cls.kind != KNormal) {
                    false;
                } else switch (pathOf(cls.pack, cls.name)) {
                    case "String" | "std.StringBuf" | "StringBuf" | "Array" | "haxe.io.Bytes": false;
                    case _: !(cls.meta.has(":dataClass") && canEmitDataClassComparator(cls));
                }
            case _: false;
        };
    }

    /**
        The element type when `t` is a raw ReadOnlyArray (checked before
        Context.follow, which erases the abstract to Array). Nullable
        collections need this raw check: the Null arm's followed inner
        type is Array and would otherwise lose the array shape.
    **/
    public static function rawArrayElement(t:Type):Null<Type> {
        return switch (t) {
            case TAbstract(a, params) if (a.get().name == "ReadOnlyArray" && params.length == 1): params[0];
            case TLazy(f): rawArrayElement(f());
            case _: null;
        }
    }

    /**
        Whether every non-computed field of the data class has a
        comparison arm in SwiftDecl.dataClassComparator. The direct arms
        compare Int, Float, Bool, String, enums, and nested data classes;
        the ReadOnlyArray arm compares elements with an arm or an
        Equatable scalar through `!=`; the Null arm compares its inner
        operand with the same arms, unwrapping an array shape before the
        follow. A class with a field no arm covers gets no comparator,
        since the emitted body would silently ignore that field, and a
        nested data class recurses with a visited set so a rendered
        comparator never references a comparator that was skipped; a
        reference cycle has no orderable rendering and fails.
    **/
    static function comparatorFieldsSupported(cls:ClassType, visited:Array<String>):Bool {
        if (visited.indexOf(cls.name) >= 0) {
            return false;
        }
        visited.push(cls.name);
        for (f in cls.fields.get()) {
            final isStoredVar = switch (f.kind) {
                case FVar(read, write): !(read.match(AccCall) && write.match(AccNever));
                case _: false;
            };
            if (isStoredVar && !comparatorFieldSupported(f.type, visited)) {
                visited.pop();
                return false;
            }
        }
        visited.pop();
        return true;
    }

    static function comparatorFieldSupported(t:Type, visited:Array<String>):Bool {
        return switch (t) {
            case TAbstract(a, params) if (a.get().name == "Null" && params.length == 1):
                final inner = rawArrayElement(params[0]);
                comparableOperandSupported(inner == null ? params[0] : inner, visited);
            case TAbstract(a, params) if (a.get().name == "ReadOnlyArray" && params.length == 1):
                comparableOperandSupported(params[0], visited);
            case _: comparableOperandSupported(t, visited);
        };
    }

    /** One comparand of the comparison arms: a scalar with an arm, an enum, a String, or a nested data class whose own comparator is itself emittable. */
    static function comparableOperandSupported(t:Type, visited:Array<String>):Bool {
        return switch (Context.follow(t)) {
            case TAbstract(a, _): a.get().name == "Int" || a.get().name == "Float" || a.get().name == "Bool";
            case TInst(c, _): c.get().name == "String" || comparatorDataClassSupported(c.get(), visited);
            case TEnum(_, _): true;
            case _: false;
        }
    }

    static function comparatorDataClassSupported(cls:ClassType, visited:Array<String>):Bool {
        return cls.meta.has(":dataClass") && comparatorFieldsSupported(cls, visited);
    }

    static function isDataClassFieldKey(t:Type):Bool {
        return PolicyQueries.isDataClassFieldKey(t);
    }

    static function validateStructDef(def:DefType, pos:haxe.macro.Expr.Position, visited:Array<String>):Array<ClassField> {
        return StructuralKeyValidator.validateStructDef(def, pos, visited);
    }

    static function validateFieldType(t:Type, pos:haxe.macro.Expr.Position, visited:Array<String>):Void {
        StructuralKeyValidator.validateFieldType(t, pos, visited);
    }

    function fail(t:Type):String {
        Context.error("type has no Swift lowering in the translatable subset: " + Std.string(t), Context.currentPos());
        return null;
    }
}
#end
