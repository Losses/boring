#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.TypedExprTools;
import haxe.macro.Type;
import reflaxe.data.ClassFuncData;
import reflaxe.data.ClassVarData;
import RuntimeResidents;
import ExpressionPredicates;

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
}
#end
