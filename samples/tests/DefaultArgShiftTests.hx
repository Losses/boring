package tests;

import boring.DefaultArgShiftOps;
import std.Test;

/**
    Argument alignment for a parameter whose registered coalescing default reads
    an earlier parameter. A call that passes an explicit null for the defaulted
    slot, or that omits the slot while a later argument keeps its position, must
    resolve the read against the argument this call actually passes.
 */
class DefaultArgShiftTests {
    @:test("explicit null at a parameter-reading default resolves the earlier argument")
    public static function testExplicitNull():Void {
        Test.equals("alpha", DefaultArgShiftOps.callExplicitNull());
        Test.equals("beta", DefaultArgShiftOps.callLaterGiven());
    }

    @:test("chain later parameter with explicit null reads the earlier argument")
    public static function testChainExplicitNull():Void {
        Test.equals(9.0, DefaultArgShiftOps.callChainedLaterNull());
    }

    @:test("chain omission forms keep their resolved values")
    public static function testChainOmissions():Void {
        Test.equals(5.0, DefaultArgShiftOps.callChainedBothOmitted());
        Test.equals(7.0, DefaultArgShiftOps.callChainedLaterOmitted());
        Test.equals(9.5, DefaultArgShiftOps.callChainedBothGiven());
    }

    @:test("instance method parameter-reading default resolves the receiver argument")
    public static function testInstanceMethod():Void {
        Test.equals("core", DefaultArgShiftOps.callInstanceNull());
    }

    @:test("middle slot omitted with later arguments keeps every slot")
    public static function testMiddleSlot():Void {
        Test.equals("fresh:3:9", DefaultArgShiftOps.callMiddleNull());
        Test.equals("given:3:7", DefaultArgShiftOps.callMiddleSkipped());
    }

    @:test("constructor parameter-reading default resolves the constructor argument")
    public static function testConstructor():Void {
        Test.equals(10.0, DefaultArgShiftOps.ctorExplicitNull());
        Test.equals(4.5, DefaultArgShiftOps.ctorLaterGiven());
    }

    @:test("explicit values at every slot are unchanged")
    public static function testExplicitValues():Void {
        Test.equals("beta", DefaultArgShiftOps.callLaterGiven());
    }
}
