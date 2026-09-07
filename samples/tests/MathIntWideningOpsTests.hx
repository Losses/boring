package tests;

import boring.MathIntWideningOps;
import std.Test;

class MathIntWideningOpsTests {
    @:test("Math Int widening preserves floor, ceil, and predicates")
    public static function testPositive():Void {
        Test.equals(4, MathIntWideningOps.floorOf(4));
        Test.equals(4, MathIntWideningOps.ceilOf(4));
        Test.equals(2.0, MathIntWideningOps.sqrtOf(4));
        Test.equals(false, MathIntWideningOps.nanOf(4));
        Test.equals(true, MathIntWideningOps.finiteOf(4));
    }

    @:test("Math Int widening handles negative square roots")
    public static function testNegative():Void {
        Test.equals(-4, MathIntWideningOps.floorOf(-4));
        Test.equals(-4, MathIntWideningOps.ceilOf(-4));
        Test.ok(MathIntWideningOps.sqrtOf(-4) != MathIntWideningOps.sqrtOf(-4), "sqrt(-4) is NaN");
        Test.equals(false, MathIntWideningOps.nanOf(-4));
        Test.equals(true, MathIntWideningOps.finiteOf(-4));
    }

    @:test("Math Int widening handles zero")
    public static function testZero():Void {
        Test.equals(0, MathIntWideningOps.floorOf(0));
        Test.equals(0, MathIntWideningOps.ceilOf(0));
        Test.equals(0.0, MathIntWideningOps.sqrtOf(0));
        Test.equals(false, MathIntWideningOps.nanOf(0));
        Test.equals(true, MathIntWideningOps.finiteOf(0));
    }
}
