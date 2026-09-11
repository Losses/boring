package boring;

#if swift_output
/**
    A local bound to a class reference is a Haxe value only at typing
    time; Swift has no class values, so the alias lowers to a local
    typealias and `S.staticMember` keeps resolving.
*/
class TypeAliasLocalSupport {
    public static final base:Int = 7;

    public static function twice(n:Int):Int
        return n * 2;
}

class TypeAliasLocalOps {
    public static function compute(n:Int):Int {
        final S = TypeAliasLocalSupport;
        return S.twice(n) + S.base;
    }
}
#else
class TypeAliasLocalOps {}
#end
