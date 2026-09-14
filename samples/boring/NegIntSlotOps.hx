package boring;

#if rust_output
/**
    Unary Int negation at a business u32 slot. Haxe Int values are unsigned in
    the engine modules while unary `-` requires the signed i32 domain, so a
    negated value reinterprets its bits at the function argument, the direct
    return, and the conditional arm so the i32 rendering does not leak.
*/
class NegIntSlotOps {
    public static function negate(value:Int):Int {
        return -value;
    }

    public static function negateArgument(value:Int):Int {
        return identity(-value);
    }

    public static function negateConditional(negative:Bool, value:Int):Int {
        return negative ? -value : value;
    }

    static function identity(value:Int):Int {
        return value;
    }
}
#else
class NegIntSlotOps {}
#end
