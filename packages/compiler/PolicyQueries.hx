#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.TypedExprTools;
import haxe.macro.Type;
import reflaxe.data.ClassFuncData;
import reflaxe.data.ClassVarData;
import reflaxe.data.EnumOptionData;
import RuntimeResidents;
import ExpressionPredicates;
import EnumQueryExpander;
import StructuralKeyValidator;

enum KeyDomain {
    IntKey;
    StringKey;
    StructKey(def:DefType, fields:Array<ClassField>);
    DataClassKey(cls:ClassType, fields:Array<ClassField>);
    EnumKey(en:EnumType);
}

/** Shared classification of haxe.Int64 implementation calls. Each target
    renders the classified operation its own way. */
enum Int64Op {
    Make(high:TypedExpr, low:TypedExpr);
    OfInt(value:TypedExpr);
    GetHigh(value:TypedExpr);
    GetLow(value:TypedExpr);
    Complement(value:TypedExpr);
    Add(l:TypedExpr, r:TypedExpr);
    Sub(l:TypedExpr, r:TypedExpr);
    Mul(l:TypedExpr, r:TypedExpr);
    MulInt(l:TypedExpr, r:TypedExpr);
    And(l:TypedExpr, r:TypedExpr);
    Or(l:TypedExpr, r:TypedExpr);
    Xor(l:TypedExpr, r:TypedExpr);
    Shl(l:TypedExpr, r:TypedExpr);
    Shr(l:TypedExpr, r:TypedExpr);
    Ushr(l:TypedExpr, r:TypedExpr);
    Eq(l:TypedExpr, r:TypedExpr);
    Neq(l:TypedExpr, r:TypedExpr);
    Lt(l:TypedExpr, r:TypedExpr);
    Gt(l:TypedExpr, r:TypedExpr);
    Lte(l:TypedExpr, r:TypedExpr);
    Gte(l:TypedExpr, r:TypedExpr);
}

/** The shared classification of a Std.string operand type. Each target
    renders one category its own way; the arm order below mirrors the
    order the five emitters already share. */
enum StdStringCategory {
    IsString;
    IsArray(element:Type);
    IsSortedSet(element:Type);
    IsSortedMap(key:Type, value:Type);
    IsRecordLike;
    IsInstanceToString;
    IsMarkedAbstract(abs:AbstractType);
    IsNull;
    IsFloat;
    IsInt;
    IsBool;
    IsTypeParameter;
    IsReadOnlyArray(underlying:Type);
    IsParameterlessEnum(en:EnumType);
    IsCyclicEnum(en:EnumType);
    IsPayloadEnum(en:EnumType);
    IsUnsupported;
}

/** One step of a variant switch arm walkthrough. The traversal and
    classification are shared; each target renders a step its own way. */
enum VariantArmStep {
    /** `var v = <subject>.payload(index)` capture. The consumer renders the
        reference text and writes it into its own subst map. */
    PayloadCapture(v:TVar, subject:TypedExpr, ef:EnumField, index:Int);

    /** `var v = source` chain. The consumer forwards the substitution when
        its own subst map already holds `source`, and renders a plain
        declaration otherwise. */
    ForwardOrDecl(v:TVar, init:TypedExpr, source:TVar);

    /** Plain local declaration. The consumer renders it with its own
        keyword and indentation. */
    PlainDecl(v:TVar, init:TypedExpr);

    /** Any other statement. `returnValue` is the inner expression of a
        non-void `return` (null otherwise); `isLast` is the position within
        its own statement list. */
    OtherStatement(s:TypedExpr, returnValue:Null<TypedExpr>, isLast:Bool);

    /** `var` without initializer. The consumer reports its target error. */
    MissingInit(s:TypedExpr);
}

/** One step of an enum-query expression classification. The kind
    detection, subject walk, and argument extraction are shared; each
    target renders the step with its own import calls and syntax. */
enum EnumQueryStep {
    /** `expr.length` on an enum collection: the constructor count. The
        rendered text is identical in every target. */
    LengthCount(count:Int);

    /** `expr[index]` on an aliased enum collection. The consumer renders the
        subject and index with its own indexing syntax. */
    AliasIndex(subj:TypedExpr, index:TypedExpr);

    /** `expr[index]` on the enum's own collection. The consumer imports
        the enum and renders its collection-access syntax. */
    EntryIndex(en:EnumType, index:TypedExpr);

    /** A marker-based query. `args` come from `callArgs`; consumers use
        `args[0]` for name queries and `args[1]` for lookups. */
    EnumKindQuery(kind:EnumQueryKind, en:EnumType, args:Array<TypedExpr>);
}

/** Shared policy queries for declaration and field-key decisions. */
class PolicyQueries {
    /** Hop count up the super chain to haxe.Exception; 0 when the chain does not reach it. */
    public static function exceptionDepth(cls:ClassType):Int {
        var depth = 0;
        var current = cls;
        while (current.superClass != null) {
            final parent = current.superClass.t.get();
            final parentPath = parent.pack.length == 0 ? parent.name : parent.pack.join(".") + "." + parent.name;
            if (parentPath == "haxe.Exception") {
                return depth + 1;
            }
            depth += 1;
            current = parent;
        }
        return 0;
    }

    /** Tail-name scheme shared by the StringBuf trailing-unit checks
        (stdlib/08): the first probe reads `tail`, later probes append
        their ordinal. */
    public static function freshTailName(counter:Int):String {
        return counter == 1 ? "tail" : "tail" + counter;
    }

    /** Options of one enum sorted by construct index, in a fresh array. */
    public static function sortedEnumOptions(options:Array<EnumOptionData>):Array<EnumOptionData> {
        final sorted = options.copy();
        sorted.sort((a, b) -> Reflect.compare(a.field.index, b.field.index));
        return sorted;
    }

    /** True when every option carries no payload (a parameterless enum). */
    public static function isValueEnumOptions(sorted:Array<EnumOptionData>):Bool {
        for (o in sorted)
            if (o.args.length > 0)
                return false;
        return true;
    }

    /** Anonymous-structure fields sorted by source position, in a fresh array. */
    public static function sortedAnonFields(anonRef:Ref<AnonType>):Array<ClassField> {
        final fields = anonRef.get().fields.copy();
        fields.sort((a, b) -> Reflect.compare(Context.getPosInfos(a.pos).min, Context.getPosInfos(b.pos).min));
        return fields;
    }

    public static function canEmitDataClassComparator(cls:ClassType):Bool {
        for (f in cls.fields.get())
            if (switch (f.kind) {
                    case FVar(read, write): !(read.match(AccCall) && write.match(AccNever)) && !isDataClassFieldKey(f.type);
                    case _: false;
                })
                return false;
        return true;
    }

    public static function isDataClassFieldKey(t:Type):Bool {
        return switch (t) {
            case TAbstract(a, params): a.get()
                    .name == "Int" || (a.get()
                    .name == "Null" && params.length == 1 && isDataClassFieldKey(params[0])) || (a.get().pack.join(".") == "std"
                    && a.get().name == "ReadOnlyArray" && params.length == 1 && isDataClassFieldKey(params[0]));
            case TEnum(_, _): true;
            case TInst(c, _): c.get().name == "String" || c.get().meta.has(":dataClass");
            case TLazy(f): isDataClassFieldKey(f());
            case _: switch (Context.follow(t)) {
                    case TAbstract(a, params): a.get()
                            .name == "Int" || (a.get()
                            .name == "Null" && params.length == 1 && isDataClassFieldKey(params[0])) || (a.get().pack.join(".") == "std"
                            && a.get().name == "ReadOnlyArray" && params.length == 1 && isDataClassFieldKey(params[0]));
                    case TEnum(_, _): true;
                    case TInst(c, _): c.get().name == "String" || c.get().meta.has(":dataClass");
                    case _: false;
                };
        };
    }

    public static function validateDataClassField(root:ClassType, field:ClassField, path:String):Void {
        if (switch (field.kind) {
                case FVar(read, write): read.match(AccCall) && write.match(AccNever);
                case _: false;
            })
            return;
        if (!isDataClassFieldKey(field.type)) {
            Context.error("dataClass key " + root.name + " field " + path + " has unsupported type " + field.type, field.pos);
            return;
        }
        switch (Context.follow(field.type)) {
            case TInst(c, _) if (c.get().meta.has(":dataClass")):
                for (f in c.get().fields.get())
                    if (switch (f.kind) {
                            case FVar(read, write): !(read.match(AccCall) && write.match(AccNever));
                            case _: false;
                        })
                        validateDataClassField(root, f, path + "." + f.name);
            case _:
        }
    }

    public static function classifyKey(t:Null<Type>, ?pos:haxe.macro.Expr.Position):KeyDomain {
        if (t == null) {
            final p = pos != null ? pos : Context.currentPos();
            Context.error("sorted keyed tables support Int, String, structure, and dataClass keys; parameterless enums are supported; enums with payloads are not keys",
                p);
            return IntKey;
        }
        final p = pos != null ? pos : Context.currentPos();
        return switch (t) {
            case TAbstract(a, _):
                if (a.get().name == "Int") {
                    IntKey;
                } else {
                    Context.error("sorted keyed tables support Int, String, structure, and dataClass keys; parameterless enums are supported; enums with payloads are not keys",
                        p);
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
                        validateDataClassField(cls, f, f.name);
                    DataClassKey(cls, fields);
                } else {
                    Context.error("sorted keyed tables support Int, String, structure, and dataClass keys; parameterless enums are supported; enums with payloads are not keys",
                        p);
                    IntKey;
                }
            case TEnum(e, _):
                final en = e.get();
                var parameterless = true;
                for (ef in en.constructs)
                    switch (Context.follow(ef.type)) {
                        case TFun(args, _) if (args.length > 0): parameterless = false;
                        case _:
                    }
                if (parameterless) {
                    EnumKey(en);
                } else {
                    Context.error("sorted keyed tables support Int, String, structure, and dataClass keys; parameterless enums are supported; enums with payloads are not keys",
                        p);
                    IntKey;
                }
            case TType(defRef, _):
                final def = defRef.get();
                final fields = StructuralKeyValidator.validateStructDef(def, p, [def.name]);
                StructKey(def, fields);
            case TLazy(f):
                classifyKey(f(), p);
            case _:
                Context.error("sorted keyed tables support Int, String, structure, and dataClass keys; parameterless enums are supported; enums with payloads are not keys",
                    p);
                IntKey;
        }
    }

    public static function isStructKeyCandidate(fields:Array<ClassField>):Bool {
        for (f in fields) {
            if (!isFieldKeyCandidate(f.type))
                return false;
        }
        return true;
    }

    public static function isFieldKeyCandidate(t:Type):Bool {
        return switch (t) {
            case TAbstract(a, _): final n = a.get().name; n == "Int" || n == "Bool";
            case TInst(c, _):
                c.get().name == "String";
            case TType(d, _):
                switch (d.get().type) {
                    case TAnonymous(anon):
                        isStructKeyCandidate(anon.get().fields);
                    case _: false;
                }
            case TLazy(fn):
                isFieldKeyCandidate(fn());
            case _: false;
        };
    }

    public static function isInlineOnly(classType:ClassType, varFields:Array<ClassVarData>, funcFields:Array<ClassFuncData>):Bool {
        if (varFields.length == 0 && funcFields.length == 0)
            return true;
        if (varFields.length == 0 && funcFields.length > 0) {
            for (f in funcFields) {
                switch (f.field.kind) {
                    case FMethod(MethInline) | FMethod(MethMacro):
                    case _:
                        return false;
                }
            }
            return true;
        }
        return false;
    }

    public static function isSyntheticImpl(name:String):Bool {
        return StringTools.endsWith(name, "_Impl_");
    }

    public static function isMapType(t:Type):Bool {
        return switch (Context.follow(t)) {
            case TInst(def, params) if (def.get().pack.join(".") == "haxe" && def.get().name == "IMap" && params.length == 2): true;
            case TInst(def, _): isMapImplementation(def.get());
            case TType(def, params): def.get().pack.length == 0 && def.get().name == "Map" && params.length == 2;
            case TAbstract(def, params) if (def.get().pack.join(".") == "haxe.ds" && def.get().name == "Map" && params.length == 2): true;
            case TAbstract(a, params) if (a.get().name == "Null" && params.length == 1): isMapType(params[0]);
            case _: false;
        };
    }

    public static function isMapImplementation(cls:ClassType):Bool {
        return cls.pack.join(".") == "haxe.ds" && ["StringMap", "IntMap", "ObjectMap", "HashMap"].indexOf(cls.name) >= 0;
    }

    public static function isMapBackingType(t:Type):Bool {
        return switch (Context.follow(t)) {
            case TInst(def, _):
                final cls = def.get();
                isMapImplementation(cls);
            case _: false;
        };
    }

    public static function isTestExtern(cls:ClassType):Bool {
        return RuntimeResidents.externsOf("runtime.TestCore").indexOf(cls.module) >= 0
            || (cls.pack.join(".") == "std" && RuntimeResidents.testExternNativeFaces().indexOf(cls.name) >= 0);
    }

    public static function isGetterOnlyProperty(field:ClassField):Bool {
        switch (field.kind) {
            case FVar(read, write):
                return read.match(AccCall) && write.match(AccNever);
            case _:
                return false;
        }
    }

    public static function isFunctionType(t:Null<Type>):Bool {
        if (t == null) {
            return false;
        }
        return switch (Context.follow(t)) {
            case TFun(_, _): true;
            case _: false;
        };
    }

    public static function isStringBuf(e:TypedExpr):Bool {
        if (e == null)
            return false;
        return switch (Context.follow(e.t)) {
            case TInst(c, _): final cls = c.get(); (cls.pack.join(".") == "std" && cls.name == "StringBuf") || (cls.pack.length == 0 && cls.name == "StringBuf");
            case _: false;
        };
    }

    public static function isParameterlessEnum(en:EnumType):Bool {
        for (ef in en.constructs)
            switch (ef.type) {
                case TFun(args, _) if (args.length > 0):
                    return false;
                case _:
            }
        return true;
    }

    /** Classifies a Std.string operand type once for every target;
        renderers keep their per-category emission. */
    public static function stdStringCategory(t:Type):StdStringCategory {
        return switch (Context.follow(t)) {
            case TInst(c, _) if (c.get().name == "String"): IsString;
            case TInst(c, [element]) if (c.get().name == "Array"): IsArray(element);
            case TInst(c, [element]) if (c.get().module == "std.SortedSet"): IsSortedSet(element);
            case TInst(c, [key, value]) if (c.get().module == "std.SortedMap"): IsSortedMap(key, value);
            case TInst(c, _) if (StaticFieldHelper.hasSelfConstructionStatic(c.get()) || c.get().meta.has(":dataClass")): IsRecordLike;
            case TInst(c, _) if (hasInstanceToString(c.get())): IsInstanceToString;
            case TAbstract(a, _) if (ValueTypeSupport.isMarkedAbstract(a.get())): IsMarkedAbstract(a.get());
            case TAbstract(a, [inner]) if (a.get().name == "Null"): IsNull;
            case TAbstract(a, _) if (a.get().name == "Float"): IsFloat;
            case TAbstract(a, _) if (a.get().name == "Int"): IsInt;
            case TAbstract(a, _) if (a.get().name == "Bool"): IsBool;
            case TInst(c, _) if (c.get().kind.match(KTypeParameter(_))): IsTypeParameter;
            case TAbstract(a, params) if (a.get().module == "std.ReadOnlyArray"):
                IsReadOnlyArray(haxe.macro.TypeTools.applyTypeParameters(a.get().type, a.get().params, params));
            case TEnum(en, _) if (isParameterlessEnum(en.get())): IsParameterlessEnum(en.get());
            case TEnum(en, _) if (EnumCycleDetector.isCyclic(en.get())): IsCyclicEnum(en.get());
            case TEnum(en, _): IsPayloadEnum(en.get());
            case _: IsUnsupported;
        };
    }

    public static function hasInstanceToString(cls:ClassType):Bool {
        for (field in cls.fields.get())
            if (field.name == "toString")
                return true;
        if (cls.superClass == null)
            return false;
        return hasInstanceToString(cls.superClass.t.get());
    }

    public static function indexedStoreOf(s:TypedExpr):Null<{arr:TVar, idx:TVar, value:TypedExpr}> {
        switch (ExpressionPredicates.stripWrap(s).expr) {
            case TBinop(OpAssign, target, value):
                switch (ExpressionPredicates.stripWrap(target).expr) {
                    case TArray(arr, idx):
                        final arrLocal = ExpressionPredicates.stripWrap(arr);
                        final idxLocal = ExpressionPredicates.stripWrap(idx);
                        switch [arrLocal.expr, idxLocal.expr] {
                            case [TLocal(a), TLocal(ix)]: return {arr: a, idx: ix, value: value};
                            case _:
                        }
                    case _:
                }
            case _:
        }
        return null;
    }

    public static function inSourceScope(pos:haxe.macro.Expr.Position):Bool {
        final file = Context.getPosInfos(pos).file;
        for (root in Intercept.sourceRoots()) {
            final prefix = root.charAt(root.length - 1) == "/" ? root : root + "/";
            if (StringTools.startsWith(file, prefix) || StringTools.startsWith(file, "./" + prefix) || file.indexOf("/" + prefix) >= 0) {
                return true;
            }
        }
        return false;
    }

    public static function isFpHelperInt64Call(fn:TypedExpr):Bool {
        return switch (ExpressionPredicates.stripWrap(fn).expr) {
            case TField(_, FStatic(classRef, fieldRef)): classRef.get()
                    .module == "haxe.io.FPHelper" && (fieldRef.get().name == "doubleToI64" || fieldRef.get().name == "f32ToI64");
            case _: false;
        };
    }

    /** Classifies a haxe.Int64 implementation static call once; each
        target renders the classified operation its own way. Arity
        mismatches and unknown names return null exactly as the five
        per-target dispatch tables did. */
    public static function int64OpOf(fn:TypedExpr, args:Array<TypedExpr>):Null<Int64Op> {
        return switch (ExpressionPredicates.stripWrap(fn).expr) {
            case TField(_, FStatic(classRef, fieldRef)) if (classRef.get().module == "haxe.Int64" && classRef.get().name == "Int64_Impl_"):
                switch (fieldRef.get().name) {
                    case "make" if (args.length == 2): Make(args[0], args[1]);
                    case "ofInt" if (args.length == 1): OfInt(args[0]);
                    case "getHigh" | "get_high" if (args.length == 1): GetHigh(args[0]);
                    case "getLow" | "get_low" if (args.length == 1): GetLow(args[0]);
                    case "complement" if (args.length == 1): Complement(args[0]);
                    case "add" if (args.length == 2): Add(args[0], args[1]);
                    case "sub" if (args.length == 2): Sub(args[0], args[1]);
                    case "mul" if (args.length == 2): Mul(args[0], args[1]);
                    case "mulInt" if (args.length == 2): MulInt(args[0], args[1]);
                    case "and" if (args.length == 2): And(args[0], args[1]);
                    case "or" if (args.length == 2): Or(args[0], args[1]);
                    case "xor" if (args.length == 2): Xor(args[0], args[1]);
                    case "shl" if (args.length == 2): Shl(args[0], args[1]);
                    case "shr" if (args.length == 2): Shr(args[0], args[1]);
                    case "ushr" if (args.length == 2): Ushr(args[0], args[1]);
                    case "eq" if (args.length == 2): Eq(args[0], args[1]);
                    case "neq" if (args.length == 2): Neq(args[0], args[1]);
                    case "lt" if (args.length == 2): Lt(args[0], args[1]);
                    case "gt" if (args.length == 2): Gt(args[0], args[1]);
                    case "lte" if (args.length == 2): Lte(args[0], args[1]);
                    case "gte" if (args.length == 2): Gte(args[0], args[1]);
                    default: null;
                }
            default: null;
        }
    }

    public static function isHasOwnPropertyValue(e:TypedExpr):Bool {
        return switch (ExpressionPredicates.stripWrap(e).expr) {
            case TField(_, FInstance(_, _, cf)) | TField(_, FAnon(cf)) if (cf.get().name == "hasOwnProperty"): true;
            case _: false;
        };
    }

    public static function mapAssignment(e:TypedExpr):Null<{receiver:TypedExpr, key:TypedExpr}> {
        return switch (ExpressionPredicates.stripWrap(e).expr) {
            case TArray(arr, key):
                final receiver = mapBackingReceiver(arr);
                receiver == null ? null : {receiver: receiver, key: key};
            case _: null;
        };
    }

    public static function mapBackingReceiver(e:TypedExpr):Null<TypedExpr> {
        return switch (ExpressionPredicates.stripWrap(e).expr) {
            case TField(receiver, FInstance(_, _, cf)) if (cf.get().name == "h" && isMapBackingType(receiver.t)): receiver;
            case TField(receiver, FAnon(cf)) if (cf.get().name == "h" && isMapBackingType(receiver.t)): receiver;
            case _: null;
        };
    }

    public static function mentionsLocal(e:TypedExpr, v:TVar):Bool {
        var found = false;
        function walk(x:TypedExpr) {
            switch (x.expr) {
                case TLocal(l) if (l.id == v.id):
                    found = true;
                case _:
            }
            TypedExprTools.iter(x, walk);
        }
        walk(e);
        return found;
    }

    public static function pathOf(pack:Array<String>, name:String):String {
        return pack.length == 0 ? name : pack.join(".") + "." + name;
    }

    public static function statementsOf(e:TypedExpr):Array<TypedExpr> {
        return switch (e.expr) {
            case TBlock(stmts): stmts;
            case _: [e];
        }
    }

    /** Returns the statement prefix, value expression, and StringBuf receiver of a block. */
    public static function blockValueParts(e:TypedExpr):{
        body:Array<TypedExpr>,
        value:Null<TypedExpr>,
        stringBufSubject:Null<TypedExpr>
    } {
        final stmts = statementsOf(e);
        if (stmts.length == 0)
            return {body: [], value: null, stringBufSubject: null};
        final last = stmts[stmts.length - 1];
        if (isStringBufToStringCall(last))
            return {
                body: stmts.slice(0, stmts.length - 1),
                value: null,
                stringBufSubject: stringBufToStringSubject(ExpressionPredicates.stripWrap(last))
            };
        final value = switch (last.expr) {
            case TReturn(_) | TThrow(_) | TVar(_, _) | TIf(_, _, _) | TWhile(_, _, _) | TBlock(_) | TBreak | TContinue | TBinop(OpAssign, _, _) |
                TBinop(OpAssignOp(_), _, _): null;
            case _: last;
        };
        return {
            body: value == null ? stmts : stmts.slice(0, stmts.length - 1),
            value: value,
            stringBufSubject: null
        };
    }

    /** Classifies the statements of one variant switch arm into shared steps.
        Traversal covers payload captures, forwarding chains, nested
        TBlock/TMeta, and the trailing value expression. The subst map,
        rendered text, keywords, and indentation stay in each target. */
    public static function variantArmPlan(e:TypedExpr):Array<VariantArmStep> {
        final steps:Array<VariantArmStep> = [];
        function walk(stmts:Array<TypedExpr>) {
            for (idx in 0...stmts.length) {
                final s = stmts[idx];
                switch (s.expr) {
                    case TVar(v, null):
                        steps.push(MissingInit(s));
                    case TVar(v, init):
                        switch (ExpressionPredicates.stripWrap(init).expr) {
                            case TEnumParameter(subject, ef, index):
                                steps.push(PayloadCapture(v, subject, ef, index));
                            case TLocal(source):
                                steps.push(ForwardOrDecl(v, init, source));
                            case _:
                                steps.push(PlainDecl(v, init));
                        }
                    case TBlock(bs):
                        walk(bs);
                    case TMeta(_, inner):
                        walk([inner]);
                    case TReturn(r):
                        steps.push(OtherStatement(s, r, idx == stmts.length - 1));
                    case _:
                        steps.push(OtherStatement(s, null, idx == stmts.length - 1));
                }
            }
        }
        walk(statementsOf(e));
        return steps;
    }

    /** Classifies one enum-query expression into a shared step. Returns null
        when the expression is not an enum query; the consumer then falls back
        to its generic rendering. Import calls and target syntax stay in each
        target. */
    public static function enumQueryPlan(e:TypedExpr):Null<EnumQueryStep> {
        switch (e.expr) {
            case TField(subj, fa):
                final name = switch (fa) {
                    case FInstance(_, _, cf) | FAnon(cf): cf.get().name;
                    case FDynamic(n): n;
                    case _: "";
                };
                final en = EnumQueryExpander.collectionEnum(subj);
                if (name == "length" && en != null)
                    return LengthCount(EnumQueryExpander.constructorCount(en));
            case TArray(subj, index):
                final en = EnumQueryExpander.collectionEnum(subj);
                if (en != null) {
                    if (EnumQueryExpander.aliasEnum(subj) != null)
                        return AliasIndex(subj, index);
                    return EntryIndex(en, index);
                }
            case _:
        }
        final kind = EnumQueryExpander.markerKind(e);
        if (kind == null)
            return null;
        return EnumKindQuery(kind, EnumQueryExpander.enumOf(e), EnumQueryExpander.callArgs(e));
    }

    public static function lambdaBody(e:TypedExpr):TypedExpr {
        if (e == null)
            return e;
        return switch (e.expr) {
            case TBlock(stmts) if (stmts.length > 0): lambdaBody(stmts[stmts.length - 1]);
            case TReturn(ret) if (ret != null): lambdaBody(ret);
            case TParenthesis(inner) | TCast(inner, _) | TMeta(_, inner): lambdaBody(inner);
            case _: e;
        }
    }

    public static function pushOf(s:TypedExpr):Null<{arr:TVar, arg:TypedExpr}> {
        switch (ExpressionPredicates.stripWrap(s).expr) {
            case TCall(fn, args) if (args.length == 1):
                switch (ExpressionPredicates.stripWrap(fn).expr) {
                    case TField(subj, fa) if (ExpressionPredicates.fieldName(fa) == "push"):
                        switch (ExpressionPredicates.stripWrap(subj).expr) {
                            case TLocal(a): return {arr: a, arg: args[0]};
                            case _:
                        }
                    case _:
                }
            case _:
        }
        return null;
    }

    public static function stdStringArg(e:TypedExpr):Null<TypedExpr> {
        return switch (ExpressionPredicates.stripWrap(e).expr) {
            case TCall({expr: TField(_, FStatic(c, cf))}, args) if (c.get().module == "Std" && cf.get().name == "string" && args.length == 1): args[0];
            case _: null;
        };
    }

    public static function stringBufMutationParts(fn:TypedExpr):Null<{name:String, subj:TypedExpr}> {
        return switch (fn.expr) {
            case TField(subj, FInstance(_, _, cf)) if (isStringBuf(subj)): final n = cf.get()
                    .name; n == "add" || n == "addChar" ? {name: n, subj: subj} : null;
            case _: null;
        };
    }

    public static function unwrapLambda(e:TypedExpr):Null<TFunc> {
        if (e == null)
            return null;
        return switch (e.expr) {
            case TFunction(f): f;
            case TParenthesis(inner) | TCast(inner, _) | TMeta(_, inner): unwrapLambda(inner);
            case _: null;
        };
    }

    public static function valueTypeLocalValues(wrapper:TypedExpr):Map<Int, TypedExpr> {
        final values:Map<Int, TypedExpr> = [];
        switch (wrapper.expr) {
            case TBlock(stmts):
                for (stmt in stmts)
                    switch (stmt.expr) {
                        case TVar(v, init) if (init != null && !StringTools.startsWith(v.name, "this")): values.set(v.id, init);
                        case _:
                    }
            case _:
        }
        return values;
    }

    public static function flattenAdd(e:TypedExpr, into:Array<TypedExpr>):Void {
        switch (e.expr) {
            case TBinop(OpAdd, a, b):
                flattenAdd(a, into);
                into.push(b);
            case _:
                into.push(e);
        }
    }

    public static function isValueEnum(en:EnumType):Bool {
        for (ef in en.constructs)
            switch (Context.follow(ef.type)) {
                case TFun(args, _) if (args.length > 0):
                    return false;
                case _:
            }
        return true;
    }

    public static function kTypeOf(fn:TypedExpr):Null<Type> {
        return switch (fn.t) {
            case TFun(_, TInst(_, params)) if (params.length > 0): params[0];
            case _: null;
        };
    }

    public static function vTypeOf(fn:TypedExpr):Null<Type> {
        return switch (fn.t) {
            case TFun(_, TInst(_, params)) if (params.length > 1): params[1];
            case _: null;
        };
    }

    public static function structureSignature(anon:Ref<AnonType>):String {
        final entries = [for (f in anon.get().fields) f.name + ":" + Std.string(f.type)];
        entries.sort(Reflect.compare);
        return entries.join(";");
    }

    public static function isStringSubject(e:TypedExpr):Bool {
        return switch (Context.follow(ExpressionPredicates.stripCast(e).t)) {
            case TInst(c, _): c.get().name == "String";
            case _: false;
        };
    }

    public static function findStaticField(cls:ClassType, name:String):Null<ClassField> {
        for (field in cls.statics.get())
            if (field.name == name)
                return field;
        return null;
    }

    public static function findFunc(funcFields:Array<ClassFuncData>, name:String, missingError:String):ClassFuncData {
        for (f in funcFields)
            if (f.field.name == name)
                return f;
        Context.error(missingError, Context.currentPos());
        return null;
    }

    public static function findConstructor(funcFields:Array<ClassFuncData>):Null<ClassFuncData> {
        for (f in funcFields) {
            if (f.field.name == "new")
                return f;
        }
        return null;
    }

    public static function matchInterval(e:TypedExpr):Null<{
        index:TVar,
        start:TypedExpr,
        bound:TypedExpr,
        body:Array<TypedExpr>
    }> {
        switch (e.expr) {
            case TBlock(stmts) if (stmts.length == 3):
                return intervalCore(stmts[0], stmts[1], stmts[2]);
            case TBlock(stmts) if (stmts.length == 2):
                return intervalShort(stmts[0], stmts[1]);
            case _:
                return null;
        }
    }

    public static function intervalCore(counterDecl:TypedExpr, boundDecl:TypedExpr, whileExpr:TypedExpr):Null<{
        index:TVar,
        start:TypedExpr,
        bound:TypedExpr,
        body:Array<TypedExpr>
    }> {
        switch [counterDecl.expr, boundDecl.expr, whileExpr.expr] {
            case [TVar(counter, start), TVar(boundVar, bound), TWhile(cond, body, true)] if (start != null && bound != null):
                final condOk = switch (ExpressionPredicates.stripWrap(cond).expr) {
                    case TBinop(OpLt, l, r):
                        final lc = ExpressionPredicates.stripWrap(l);
                        final rc = ExpressionPredicates.stripWrap(r);
                        switch [lc.expr, rc.expr] {
                            case [TLocal(c), TLocal(b)]: c.id == counter.id && b.id == boundVar.id;
                            case _: false;
                        }
                    case _: false;
                }
                if (!condOk) {
                    return null;
                }
                final bodyStmts = statementsOf(body);
                if (bodyStmts.length == 0) {
                    return null;
                }
                var increment = -1;
                for (j in 0...bodyStmts.length)
                    switch (ExpressionPredicates.stripWrap(bodyStmts[j]).expr) {
                        case TVar(_, inc) if (inc != null):
                            switch (ExpressionPredicates.stripWrap(inc).expr) {
                                case TUnop(OpIncrement, true, {expr: TLocal(c)}) if (c.id == counter.id): increment = j;
                                case _:
                            }
                        case TUnop(OpIncrement, true, {expr: TLocal(c)}) if (c.id == counter.id): increment = j;
                        case _:
                    }
                if (increment < 0)
                    return null;
                return {
                    index: counter,
                    start: start,
                    bound: bound,
                    body: [for (j in 0...bodyStmts.length) if (j != increment) bodyStmts[j]]
                };
            case _:
                return null;
        }
    }

    public static function intervalShort(counterDecl:TypedExpr, whileExpr:TypedExpr):Null<{
        index:TVar,
        start:TypedExpr,
        bound:TypedExpr,
        body:Array<TypedExpr>
    }> {
        switch [counterDecl.expr, whileExpr.expr] {
            case [TVar(counter, start), TWhile(cond, body, true)] if (start != null):
                switch (ExpressionPredicates.stripWrap(cond).expr) {
                    case TBinop(OpLt, left, right):
                        final subject = ExpressionPredicates.stripParentheses(left);
                        switch (subject.expr) {
                            case TLocal(c) if (c.id == counter.id):
                                final bodyStmts = statementsOf(body);
                                if (bodyStmts.length == 0)
                                    return null;
                                var increment = -1;
                                for (j in 0...bodyStmts.length)
                                    switch (ExpressionPredicates.stripWrap(bodyStmts[j]).expr) {
                                        case TBinop(OpAssignOp(OpAdd), {expr: TLocal(c)}, _) if (c.id == counter.id): increment = j;
                                        case TUnop(OpIncrement, true, {expr: TLocal(c)}) if (c.id == counter.id): increment = j;
                                        case TVar(_, inc) if (inc != null):
                                            switch (ExpressionPredicates.stripWrap(inc).expr) {
                                                case TUnop(OpIncrement, true, {expr: TLocal(c)}) if (c.id == counter.id): increment = j;
                                                case _:
                                            }
                                        case _:
                                    }
                                if (increment < 0)
                                    return null;
                                return {
                                    index: counter,
                                    start: start,
                                    bound: right,
                                    body: [for (j in 0...bodyStmts.length) if (j != increment) bodyStmts[j]]
                                };
                            case _:
                                return null;
                        }
                    case _:
                        return null;
                }
            case _:
        }
        return null;
    }

    public static function regroupLoops(stmts:Array<TypedExpr>):Array<TypedExpr> {
        final out:Array<TypedExpr> = [];
        var i = 0;
        while (i < stmts.length) {
            if (i + 2 < stmts.length) {
                final loop = intervalCore(stmts[i], stmts[i + 1], stmts[i + 2]);
                if (loop != null) {
                    final grouped:TypedExpr = {
                        expr: TBlock([stmts[i], stmts[i + 1], stmts[i + 2]]),
                        pos: stmts[i].pos,
                        t: stmts[i + 2].t
                    };
                    out.push(grouped);
                    i += 3;
                    continue;
                }
            }
            if (i + 1 < stmts.length) {
                final loop = intervalShort(stmts[i], stmts[i + 1]);
                if (loop != null) {
                    final grouped:TypedExpr = {
                        expr: TBlock([stmts[i], stmts[i + 1]]),
                        pos: stmts[i].pos,
                        t: stmts[i + 1].t
                    };
                    out.push(grouped);
                    i += 2;
                    continue;
                }
            }
            out.push(stmts[i]);
            i += 1;
        }
        return out;
    }

    public static function stringToolsHexArgs(args:Array<TypedExpr>):{value:TypedExpr, digits:Null<TypedExpr>} {
        final value = args[0];
        final digits = args.length > 1 && !ExpressionPredicates.isNullExpr(args[1]) ? args[1] : null;
        if (ExpressionPredicates.isNegativeIntLiteral(value) || (digits != null && ExpressionPredicates.isNegativeIntLiteral(digits))) {
            Context.error("StringTools.hex accepts non-negative arguments only", value.pos);
        }
        return {value: value, digits: digits};
    }

    public static function isNullableType(t:Null<Type>):Bool {
        if (t == null) {
            return false;
        }
        return switch (t) {
            case TAbstract(a, params) if (a.get().name == "Null" && params.length == 1): true;
            case TLazy(f): isNullableType(f());
            case _: false;
        };
    }

    public static function collectTypeParamsInto(t:Null<Type>, skip:Array<String>, found:Array<String>):Void {
        if (t == null) {
            return;
        }
        switch (t) {
            case TInst(c, params):
                final cls = c.get();
                if (switch (cls.kind) {
                        // Haxe 4.3 carries the parameter's constraints on
                        // the kind constructor.
                        case KTypeParameter(_): true;
                        case _: false;
                    }) {
                    if (skip.indexOf(cls.name) < 0 && found.indexOf(cls.name) < 0) {
                        found.push(cls.name);
                    }
                    }
                for (p in params)
                    collectTypeParamsInto(p, skip, found);
            case TAbstract(_, params) | TType(_, params) | TEnum(_, params):
                for (p in params)
                    collectTypeParamsInto(p, skip, found);
            case TFun(args, ret):
                for (arg in args)
                    collectTypeParamsInto(arg.t, skip, found);
                collectTypeParamsInto(ret, skip, found);
            case TLazy(fun):
                collectTypeParamsInto(fun(), skip, found);
            case _:
        }
    }

    // Marks a declared local's name as used so fresh-name minting avoids
    // it. Kotlin lowers a `_` local to a generated name, so its scan
    // passes excludeUnderscore; the other targets reserve the raw name.
    public static function noteDeclaredLocalName(v:TVar, usedNames:Map<String, Bool>, excludeUnderscore:Bool):Void {
        if (v.name != "`" && (!excludeUnderscore || v.name != "_")) {
            usedNames.set(v.name, true);
        }
    }

    // Records that a local's initializer is an Int64 helper call whose
    // two parts the emitter must keep available. Shared by the four targets
    // whose scanLocals keeps this as a standalone initializer check;
    // Rust folds the same detection into a wider call scan.
    public static function noteFpInt64Init(v:TVar, init:Null<TypedExpr>, fpInt64Halves:Map<Int, Bool>):Void {
        if (init == null) {
            return;
        }
        switch (ExpressionPredicates.stripWrap(init).expr) {
            case TCall(fn, _) if (isFpHelperInt64Call(fn)):
                fpInt64Halves.set(v.id, true);
            case _:
        }
    }

    /** True when the expression reads an Int64 helper call directly or a
        local whose initializer was one (recorded via noteFpInt64Init). */
    public static function isFpHelperInt64Halves(e:TypedExpr, fpInt64Halves:Map<Int, Bool>):Bool {
        return switch (ExpressionPredicates.stripWrap(e).expr) {
            case TCall(fn, _): isFpHelperInt64Call(fn);
            case TLocal(v): fpInt64Halves.exists(v.id);
            case _: false;
        }
    }

    /** Tests whether an expression is a StringBuf toString call. */
    public static function isStringBufToStringCall(e:Null<TypedExpr>):Bool {
        if (e == null)
            return false;
        return switch (ExpressionPredicates.stripWrap(e).expr) {
            case TCall(fn, _):
                switch (fn.expr) {
                    case TField(subj, FInstance(_, _, cf)): cf.get().name == "toString" && isStringBuf(subj);
                    case _: false;
                }
            case _: false;
        };
    }

    /** Returns the receiver of a StringBuf toString call, or the call itself. */
    public static function stringBufToStringSubject(call:TypedExpr):TypedExpr {
        return switch (call.expr) {
            case TCall(fn, _):
                switch (fn.expr) {
                    case TField(subj, _): subj;
                    case _: call;
                }
            case _: call;
        };
    }

    /** Tests whether an expression is a single-catch try region. */
    public static function isTryRegion(e:Null<TypedExpr>):Bool {
        if (e == null)
            return false;
        return switch (ExpressionPredicates.stripWrap(e).expr) {
            case TTry(_, catches): catches.length == 1;
            case _: false;
        };
    }

    /** Returns the body and catch binding of a single-catch try region. */
    public static function tryRegionParts(e:TypedExpr):Null<{body:TypedExpr, c:{v:TVar, expr:TypedExpr}}> {
        return switch (ExpressionPredicates.stripWrap(e).expr) {
            case TTry(body, catches) if (catches.length == 1): {body: body, c: catches[0]};
            case _: null;
        };
    }

    /** Returns the argument names carried by an enum field. */
    public static function payloadNames(ef:EnumField):Array<String> {
        return switch (ef.type) {
            case TFun(args, _): [for (a in args) a.name];
            case _: [];
        };
    }
}

// Naming state for cyclic enum Std.string helpers. The cache maps
// "module:TypeName" to the emitted helper name so a recursive Std.string
// inside body generation resolves to the helper already being emitted;
// open() mints the next name and registers it, close() unregisters on
// every completed body path. Target emitters keep the helper body,
// wrapper syntax, name conversion, and call spelling.
final class EnumStringHelperNaming {
    final cache:Map<String, String> = [];
    var counter:Int = 0;

    public function new() {}

    public function existing(en:EnumType):Null<String> {
        return cache.get(en.module + ":" + en.name);
    }

    public function open(en:EnumType, base:String):String {
        final name = base + counter++;
        cache.set(en.module + ":" + en.name, name);
        return name;
    }

    public function close(en:EnumType):Void {
        cache.remove(en.module + ":" + en.name);
    }
}
#end
