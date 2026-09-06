#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.TypedExprTools;
import haxe.macro.Type;
import reflaxe.data.ClassFuncData;
import reflaxe.data.ClassVarData;
import RuntimeResidents;
import ExpressionPredicates;
import StructuralKeyValidator;

enum IntervalCapability {
    MatchesDoWhileLoops;
    RequiresInitializedCounter;
    UnwrapsBoundSubject;
}

enum KeyDomain {
    IntKey;
    StringKey;
    StructKey(def:DefType, fields:Array<ClassField>);
    DataClassKey(cls:ClassType, fields:Array<ClassField>);
    EnumKey(en:EnumType);
}

/** Shared policy queries for declaration and field-key decisions. */
class PolicyQueries {
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

    public static function matchInterval(e:TypedExpr, caps:Array<IntervalCapability>):Null<{
        index:TVar,
        start:TypedExpr,
        bound:TypedExpr,
        body:Array<TypedExpr>
    }> {
        switch (e.expr) {
            case TBlock(stmts) if (stmts.length == 3):
                return intervalCore(stmts[0], stmts[1], stmts[2]);
            case TBlock(stmts) if (stmts.length == 2):
                return intervalShort(stmts[0], stmts[1], caps);
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
            case [TVar(counter, start), TVar(boundVar, bound), TWhile(cond, body, true)]:
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
                switch (bodyStmts[0].expr) {
                    case TVar(captured, inc):
                        final captureOk = inc != null && switch (ExpressionPredicates.stripWrap(inc).expr) {
                            case TUnop(OpIncrement, true, subj):
                                switch (ExpressionPredicates.stripWrap(subj).expr) {
                                    case TLocal(c): c.id == counter.id;
                                    case _: false;
                                }
                            case _: false;
                        } if (!captureOk) {
                            return null;
                        }
                        return {
                            index: captured,
                            start: start,
                            bound: bound,
                            body: bodyStmts.slice(1)
                        };
                    case _:
                        return null;
                }
            case _:
                return null;
        }
    }

    public static function intervalShort(counterDecl:TypedExpr, whileExpr:TypedExpr, caps:Array<IntervalCapability>):Null<{
        index:TVar,
        start:TypedExpr,
        bound:TypedExpr,
        body:Array<TypedExpr>
    }> {
        final acceptDoWhile = caps.indexOf(MatchesDoWhileLoops) >= 0;
        switch [counterDecl.expr, whileExpr.expr] {
            case [TVar(counter, start), TWhile(cond, body, normal)]
                if ((normal || acceptDoWhile) && (start != null || caps.indexOf(RequiresInitializedCounter) < 0)):
                switch (ExpressionPredicates.stripWrap(cond).expr) {
                    case TBinop(OpLt, left, right):
                        final subject = caps.indexOf(UnwrapsBoundSubject) >= 0 ? ExpressionPredicates.stripWrap(left) : left;
                        switch (subject.expr) {
                            case TLocal(c) if (c.id == counter.id):
                                final bodyStmts = statementsOf(body);
                                if (bodyStmts.length == 0)
                                    return null;
                                switch (bodyStmts[0].expr) {
                                    case TVar(captured, inc) if (inc != null):
                                        switch (ExpressionPredicates.stripWrap(inc).expr) {
                                            case TUnop(OpIncrement, true, {expr: TLocal(c)}) if (c.id == counter.id):
                                                return {
                                                    index: captured,
                                                    start: start,
                                                    bound: right,
                                                    body: bodyStmts.slice(1)
                                                };
                                            case _:
                                        }
                                    case _:
                                }
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

    public static function regroupLoops(stmts:Array<TypedExpr>, caps:Array<IntervalCapability>):Array<TypedExpr> {
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
                final loop = intervalShort(stmts[i], stmts[i + 1], caps);
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
