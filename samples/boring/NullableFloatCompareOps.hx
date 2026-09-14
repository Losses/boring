package boring;

#if rust_output
/**
    A null-coalescing Float local compared against an integer literal. The
    collapsed local is a scalar Float; the comparison widens the literal
    into the Float domain so both Rust operands share one type. The named
    nullableCollapsedFloatCompare rule covers the equality and inequality
    positions.
*/
class NullableFloatCompareOps {
    public static function structuralZero(leading:Null<Float>, trailing:Null<Float>):Bool {
        final lead = leading == null ? 0. : leading;
        final trail = trailing == null ? 0. : trailing;
        final structural = lead + trail;
        return structural == 0 && lead == 0;
    }

    public static function notZero(value:Null<Float>):Bool {
        final amount = value == null ? 0. : value;
        return amount != 0;
    }
}
#else
class NullableFloatCompareOps {}
#end
