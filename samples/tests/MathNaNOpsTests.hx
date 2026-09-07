package tests;

import boring.MathNaNOps;
import boring.MathNaNTestSupport;
import std.Test;

class MathNaNOpsTests {
    @:test("Math.min propagates NaN and handles finite and infinity edges")
    public static function minValues():Void {
        MathNaNTestSupport.assertNaN(MathNaNOps.minOf(Math.NaN, 2.0), "min NaN, finite");
        MathNaNTestSupport.assertNaN(MathNaNOps.minOf(2.0, Math.NaN), "min finite, NaN");
        MathNaNTestSupport.assertNaN(MathNaNOps.minOf(Math.NaN, Math.NaN), "min NaN, NaN");
        Test.equals(-3.0, MathNaNOps.minOf(-3.0, 4.0));
        Test.equals(-3.0, MathNaNOps.minOf(4.0, -3.0));
        Test.equals(2.0, MathNaNOps.minOf(2.0, Math.POSITIVE_INFINITY));
        Test.equals(2.0, MathNaNOps.minOf(Math.POSITIVE_INFINITY, 2.0));
        Test.equals(Math.NEGATIVE_INFINITY, MathNaNOps.minOf(Math.NEGATIVE_INFINITY, 2.0));
        Test.equals(Math.NEGATIVE_INFINITY, MathNaNOps.minOf(2.0, Math.NEGATIVE_INFINITY));
        Test.equals(Math.NEGATIVE_INFINITY, MathNaNOps.minOf(Math.POSITIVE_INFINITY, Math.NEGATIVE_INFINITY));
        Test.equals(Math.NEGATIVE_INFINITY, MathNaNOps.minOf(Math.NEGATIVE_INFINITY, Math.POSITIVE_INFINITY));
        MathNaNTestSupport.assertNaN(MathNaNOps.minOf(Math.NaN, Math.POSITIVE_INFINITY), "min NaN, infinity");
        MathNaNTestSupport.assertNaN(MathNaNOps.minOf(Math.POSITIVE_INFINITY, Math.NaN), "min infinity, NaN");
        MathNaNTestSupport.assertNegativeZero(MathNaNOps.minOf(-0.0, 0.0), "min -0, +0");
        MathNaNTestSupport.assertNegativeZero(MathNaNOps.minOf(0.0, -0.0), "min +0, -0");
        Test.equals(Math.NEGATIVE_INFINITY, MathNaNOps.minOf(-0.0, Math.NEGATIVE_INFINITY));
        Test.equals(Math.NEGATIVE_INFINITY, MathNaNOps.minOf(Math.NEGATIVE_INFINITY, -0.0));
        Test.equals(Math.NEGATIVE_INFINITY, MathNaNOps.minOf(0.0, Math.NEGATIVE_INFINITY));
        Test.equals(Math.NEGATIVE_INFINITY, MathNaNOps.minOf(Math.NEGATIVE_INFINITY, 0.0));
        MathNaNTestSupport.assertNegativeZero(MathNaNOps.minOf(-0.0, Math.POSITIVE_INFINITY), "min -0, +infinity");
        MathNaNTestSupport.assertNegativeZero(MathNaNOps.minOf(Math.POSITIVE_INFINITY, -0.0), "min +infinity, -0");
        MathNaNTestSupport.assertPositiveZero(MathNaNOps.minOf(0.0, Math.POSITIVE_INFINITY), "min +0, +infinity");
        MathNaNTestSupport.assertPositiveZero(MathNaNOps.minOf(Math.POSITIVE_INFINITY, 0.0), "min +infinity, +0");
        Test.equals(4.0, MathNaNOps.minInts(4, 9), "min widens Int operands");
    }

    @:test("Math.max propagates NaN and handles finite and infinity edges")
    public static function maxValues():Void {
        MathNaNTestSupport.assertNaN(MathNaNOps.maxOf(Math.NaN, 2.0), "max NaN, finite");
        MathNaNTestSupport.assertNaN(MathNaNOps.maxOf(2.0, Math.NaN), "max finite, NaN");
        MathNaNTestSupport.assertNaN(MathNaNOps.maxOf(Math.NaN, Math.NaN), "max NaN, NaN");
        Test.equals(4.0, MathNaNOps.maxOf(-3.0, 4.0));
        Test.equals(4.0, MathNaNOps.maxOf(4.0, -3.0));
        Test.equals(Math.POSITIVE_INFINITY, MathNaNOps.maxOf(2.0, Math.POSITIVE_INFINITY));
        Test.equals(Math.POSITIVE_INFINITY, MathNaNOps.maxOf(Math.POSITIVE_INFINITY, 2.0));
        Test.equals(2.0, MathNaNOps.maxOf(Math.NEGATIVE_INFINITY, 2.0));
        Test.equals(2.0, MathNaNOps.maxOf(2.0, Math.NEGATIVE_INFINITY));
        Test.equals(Math.POSITIVE_INFINITY, MathNaNOps.maxOf(Math.POSITIVE_INFINITY, Math.NEGATIVE_INFINITY));
        Test.equals(Math.POSITIVE_INFINITY, MathNaNOps.maxOf(Math.NEGATIVE_INFINITY, Math.POSITIVE_INFINITY));
        MathNaNTestSupport.assertNaN(MathNaNOps.maxOf(Math.NaN, Math.NEGATIVE_INFINITY), "max NaN, infinity");
        MathNaNTestSupport.assertNaN(MathNaNOps.maxOf(Math.NEGATIVE_INFINITY, Math.NaN), "max infinity, NaN");
        MathNaNTestSupport.assertPositiveZero(MathNaNOps.maxOf(-0.0, 0.0), "max -0, +0");
        MathNaNTestSupport.assertPositiveZero(MathNaNOps.maxOf(0.0, -0.0), "max +0, -0");
        Test.equals(Math.POSITIVE_INFINITY, MathNaNOps.maxOf(-0.0, Math.POSITIVE_INFINITY));
        Test.equals(Math.POSITIVE_INFINITY, MathNaNOps.maxOf(Math.POSITIVE_INFINITY, -0.0));
        Test.equals(Math.POSITIVE_INFINITY, MathNaNOps.maxOf(0.0, Math.POSITIVE_INFINITY));
        Test.equals(Math.POSITIVE_INFINITY, MathNaNOps.maxOf(Math.POSITIVE_INFINITY, 0.0));
        MathNaNTestSupport.assertNegativeZero(MathNaNOps.maxOf(-0.0, Math.NEGATIVE_INFINITY), "max -0, -infinity");
        MathNaNTestSupport.assertNegativeZero(MathNaNOps.maxOf(Math.NEGATIVE_INFINITY, -0.0), "max -infinity, -0");
        MathNaNTestSupport.assertPositiveZero(MathNaNOps.maxOf(0.0, Math.NEGATIVE_INFINITY), "max +0, -infinity");
        MathNaNTestSupport.assertPositiveZero(MathNaNOps.maxOf(Math.NEGATIVE_INFINITY, 0.0), "max -infinity, +0");
        Test.equals(9.0, MathNaNOps.maxInts(4, 9), "max widens Int operands");
    }
}
