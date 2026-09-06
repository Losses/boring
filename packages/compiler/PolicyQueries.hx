#if (macro || reflaxe_runtime)
import haxe.macro.Context;
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
}
#end
