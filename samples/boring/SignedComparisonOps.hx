package boring;

#if rust_output
/**
    An ordered Int comparison whose left operand lowers in the signed i32
    domain (a String.indexOf result) while the right operand is a business
    u32 Int parameter. The named signedComparisonOperand rule reinterprets
    the u32 side so both sides share the Rust integer type.
*/
class SignedComparisonOps {
    public static function indexBelowLimit(text:String, limit:Int):Bool {
        return text.indexOf("x") < limit;
    }

    public static function indexAtOrAboveLimit(text:String, limit:Int):Bool {
        return text.indexOf("x") >= limit;
    }

    public static function indexEqualsLimit(text:String, limit:Int):Bool {
        return text.indexOf("x") == limit;
    }
}
#else
class SignedComparisonOps {}
#end
