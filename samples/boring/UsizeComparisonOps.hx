package boring;

#if rust_output
/**
    An ordered Int comparison whose right operand lowers as a Rust usize (a
    nullable Array length read). The named usizeComparisonOperand rule
    narrows the usize side to the business u32 comparison domain.
*/
class UsizeComparisonOps {
    public static function withinBounds(values:Null<Array<Int>>, index:Int):Bool {
        if (values == null || index < 0 || index >= values.length) {
            return false;
        }
        return true;
    }

    public static function lengthExceeds(values:Null<Array<Int>>, limit:Int):Bool {
        if (values == null) {
            return false;
        }
        return values.length > limit;
    }
}
#else
class UsizeComparisonOps {}
#end
