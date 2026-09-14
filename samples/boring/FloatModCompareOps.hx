package boring;

#if rust_output
/**
    A Float remainder compared against an integer literal. The remainder
    carries the Float domain from its Float left operand, so the comparison
    widens the integer literal into that domain. The named emittedFloatMod
    rule covers the arithmetic result type.
*/
class FloatModCompareOps {
    public static function even(value:Float):Bool {
        return value % 2 == 0;
    }
}
#else
class FloatModCompareOps {}
#end
