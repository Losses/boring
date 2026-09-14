package boring;

#if rust_output
import boring.HaxeExceptionOps.HaxeExceptionFault;

/**
    A two step fallibility chain where the middle function only repeats the
    failure set of the leaf function. The leaf function carries two domains,
    so its synthetic union is the middle function's whole failure set. The
    outer function then adds a third caller edge, and its own union must
    include the middle union so the `?` conversion keeps a From rule.
**/
class UnionChainOps {
    public static function pair(value:Int):Int {
        if (value < 0)
            throw new HaxeExceptionFault("pair-alpha");
        if (value > 10)
            throw new ValueException(ValueError.StartAfterEnd);
        return value;
    }

    public static function adopt(value:Int):Int {
        return pair(value);
    }

    public static function outer(value:Int):Int {
        return adopt(value);
    }
}
#else
class UnionChainOps {}
#end
