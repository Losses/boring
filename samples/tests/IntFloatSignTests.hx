package tests;

import boring.IntFloatSignOps;
import std.Test;

class IntFloatSignTests {
    @:test("a wrapped Int stays -1.0 through an Int-vs-Float comparison widening")
    public static function testComparison():Void {
        // 3 - 4 wraps in the u32 domain on the Rust target; the widened
        // Float must read the signed value.
        Test.equals(true, IntFloatSignOps.belowHalf(3, 4));
        Test.equals(false, IntFloatSignOps.belowHalf(4, 3));
    }

    @:test("a wrapped Int stays -1.0 through a collapsed-local comparison widening")
    public static function testCollapsedComparison():Void {
        Test.equals(true, IntFloatSignOps.equalsCollapsed(3, 4));
    }

    @:test("a wrapped Int stays -1.0 through a Float compound assignment")
    public static function testCompoundAssign():Void {
        Test.equals(-0.5, IntFloatSignOps.compoundSum(3, 4));
        Test.equals(4.5, IntFloatSignOps.compoundSum(4, 3));
    }

    @:test("a wrapped Int stays -1.0 through an array-literal Float element")
    public static function testArrayElem():Void {
        Test.equals(-1.0, IntFloatSignOps.firstElem(3, 4));
        Test.equals(1.0, IntFloatSignOps.firstElem(4, 3));
    }

    @:test("a wrapped Int stays -1.0 through an Option<Float> return boundary")
    public static function testOptionalReturn():Void {
        final v = IntFloatSignOps.asOptional(3, 4);
        Test.equals(true, v != null);
        Test.equals(-1.0, v);
    }

    @:test("a wrapped Int stays -1.0 through a guarded ternary fallback")
    public static function testTernaryFallback():Void {
        Test.equals(-1.0, IntFloatSignOps.ternaryFallback(3, 4));
        Test.equals(1.0, IntFloatSignOps.ternaryFallback(4, 3));
    }

    @:test("a wrapped Int stays -1.0 through a value-type Float constructor")
    public static function testValueCtor():Void {
        Test.equals(-1.0, IntFloatSignOps.valueCtor(3, 4));
        Test.equals(1.0, IntFloatSignOps.valueCtor(4, 3));
    }
}
