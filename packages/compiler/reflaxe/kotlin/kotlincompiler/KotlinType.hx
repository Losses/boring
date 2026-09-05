package kotlincompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;
import StructuralKeyValidator;
import PolicyQueries;

enum KeyDomain {
    IntKey;
    StringKey;
    StructKey(def:DefType, fields:Array<ClassField>);
    DataClassKey(cls:ClassType, fields:Array<ClassField>);
}

/**
    Type mapping from the translatable Haxe subset to Kotlin, per
    docs/specs/features/14-type-system-mapping.md and stdlib rulings.
    Cross-package types record their imports; the payload enum of the
    sealed error fold resolves to its exception class.
**/
class KotlinType {
    final imports:KotlinImports;
    final state:KotlinEmissionState;

    public function new(imports:KotlinImports, state:KotlinEmissionState) {
        this.imports = imports;
        this.state = state;
    }

    public function of(t:Null<Type>):String {
        if (t == null) {
            return "Unit";
        }
        return switch (t) {
            case TAbstract(a, params):
                final abs = a.get();
                if (ValueTypeSupport.isMarkedAbstract(abs)) {
                    imports.requireType(abs.module, abs.name);
                    abs.name;
                } else switch (pathOf(abs.pack, abs.name)) {
                    case "Int": "Int";
                    // The module precision switch selects the Float
                    // width for the whole compilation (feature spec 23).
                    case "Float": FloatPrecision.isF32() ? "Float" : "Double";
                    case "Bool": "Boolean";
                    case "Void": "Unit";
                    case "Null": of(params[0]) + "?";
                    case "haxe.ds.Map" if (params.length == 2): "MutableMap<" + of(params[0]) + ", " + of(params[1]) + ">";
                    case "std.ReadOnlyArray":
                        "List<" + of(params[0]) + ">";
                    case "haxe.Int64":
                        "Long";
                    case _: of(abs.type);
                }
            case TInst(c, params):
                final cls = c.get();
                switch (pathOf(cls.pack, cls.name)) {
                    case "String": "String";
                    case "std.StringBuf" | "StringBuf": "StringBuilder";
                    case "Array":
                        "MutableList<" + of(params[0]) + ">";
                    case "haxe.io.Bytes": "ByteArray";
                    case "haxe.io.BytesBuffer":
                        imports.requireType(cls.module, "BytesBuffer");
                        "BytesBuffer";
                    case "std.SortedMap":
                        imports.requireType(cls.module, "SortedMapTable");
                        "SortedMapTable<" + of(params[0]) + ", " + of(params[1]) + ">";
                    case "std.SortedMapBuilder":
                        imports.requireType(cls.module, "SortedMapTableBuilder");
                        "SortedMapTableBuilder<" + of(params[0]) + ", " + of(params[1]) + ">";
                    case "std.SortedSet":
                        imports.requireType(cls.module, "SortedSetTable");
                        "SortedSetTable<" + of(params[0]) + ">";
                    case "std.SortedSetBuilder":
                        imports.requireType(cls.module, "SortedSetTableBuilder");
                        "SortedSetTableBuilder<" + of(params[0]) + ">";
                    case _:
                        imports.requireType(cls.module, cls.name);
                        if (params.length > 0) {
                            cls.name + "<" + [for (p in params) of(p)].join(", ") + ">";
                        } else {
                            cls.name;
                        }
                }
            case TType(def, params):
                final d = def.get();
                if (d.pack.join(".") == "haxe.io" && d.name == "Bytes") {
                    "ByteArray";
                } else if (d.pack.length == 0 && d.name == "Map" && params.length == 2) {
                    "MutableMap<" + of(params[0]) + ", " + of(params[1]) + ">";
                } else if (RuntimeResidents.isResident(d.module)) {
                    // Resident typedefs name function types for the
                    // TypeScript alias; Kotlin carries no named-alias
                    // requirement, so the reference lowers to the
                    // underlying function type with the arguments
                    // applied at the reference site.
                    of(haxe.macro.TypeTools.applyTypeParameters(d.type, d.params, params));
                } else if (params.length == 0) {
                    imports.requireType(d.module, d.name);
                    d.name;
                } else {
                    fail(t);
                }
            case TEnum(e, _):
                final en = e.get();
                final owner = state.payloadEnumOwners.get(en.module);
                if (owner != null) {
                    owner;
                } else {
                    imports.requireType(en.module, en.name);
                    en.name;
                }
            case TFun(args, ret):
                "(" + [for (arg in args) of(arg.t)].join(", ") + ") -> " + of(ret);
            case TAnonymous(_):
                Context.error("anonymous structure types must be named typedefs before translation", Context.currentPos());
                null;
            case TDynamic(_) | TMono(_):
                fail(t);
            case TLazy(f): of(f());
        }
    }

    function pathOf(pack:Array<String>, name:String):String {
        return pack.length == 0 ? name : pack.join(".") + "." + name;
    }

    public static function classifyKey(t:Null<Type>, ?pos:haxe.macro.Expr.Position):KeyDomain {
        if (t == null) {
            final p = pos != null ? pos : Context.currentPos();
            Context.error("sorted keyed tables support Int, String, structure, and dataClass keys in this implementation", p);
            return IntKey;
        }
        final p = pos != null ? pos : Context.currentPos();
        return switch (t) {
            case TAbstract(a, _):
                if (a.get().name == "Int") {
                    IntKey;
                } else {
                    Context.error("sorted keyed tables support Int, String, structure, and dataClass keys in this implementation", p);
                    IntKey;
                }
            case TInst(c, _):
                final cls = c.get();
                if (cls.name == "String") {
                    StringKey;
                } else if (cls.meta.has(":dataClass")) {
                    final fields = [
                        for (f in cls.fields.get())
                            if (switch (f.kind) {
                                    case FVar(read, write): !(read.match(AccCall) && write.match(AccNever));
                                    case _: false;
                                }) f
                    ];
                    for (f in fields)
                        validateDataClassField(cls, f);
                    DataClassKey(cls, fields);
                } else {
                    Context.error("sorted keyed tables support Int, String, structure, and dataClass keys in this implementation", p);
                    IntKey;
                }
            case TType(defRef, _):
                final def = defRef.get();
                final fields = validateStructDef(def, p, [def.name]);
                StructKey(def, fields);
            case TLazy(f):
                classifyKey(f(), p);
            case _:
                Context.error("sorted keyed tables support Int, String, structure, and dataClass keys in this implementation", p);
                IntKey;
        }
    }

    static function validateDataClassField(cls:ClassType, field:ClassField):Void {
        if (!isDataClassFieldKey(field.type)) {
            Context.error("dataClass key " + cls.name + " field " + field.name + " has unsupported type " + field.type, field.pos);
            return;
        }
        switch (Context.follow(field.type)) {
            case TInst(c, _) if (c.get().meta.has(":dataClass")):
                for (f in c.get().fields.get())
                    if (switch (f.kind) {
                            case FVar(read, write): !(read.match(AccCall) && write.match(AccNever));
                            case _: false;
                        })
                        validateDataClassField(c.get(), f);
            case _:
        }
    }

    public static function canEmitDataClassComparator(cls:ClassType):Bool {
        return PolicyQueries.canEmitDataClassComparator(cls);
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
        Context.error("type has no Kotlin lowering in the translatable subset: " + Std.string(t), Context.currentPos());
        return null;
    }
}
#end
