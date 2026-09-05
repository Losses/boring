#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;

/** Shared policy queries for data-class and structural field keys. */
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
}
#end
