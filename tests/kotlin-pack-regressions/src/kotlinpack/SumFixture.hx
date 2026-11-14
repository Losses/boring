package kotlinpack;

import std.Functional;

using std.Functional;

/**
    The sumOfFloat selector shape: a binary32 module sums Float values through
    a binary64 accumulator, so the Kotlin selector must widen to Double before
    sumOf resolves. A bare Float selector leaves kotlinc choosing between the
    Int and UInt overloads.
**/
class SumFixture {
    /** The exact sum of [values], narrowed to binary32 once. */
    public static function of(values:Array<Float>):Float {
        function accumulate():Float {
            return values.sumOfFloat(value -> value);
        }
        return accumulate();
    }
}
