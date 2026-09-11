package tests;

import std.Test;

#if swift_output
import boring.LocalThrowOps;
#end

class LocalThrowTests {
    @:test("a local throwing function call carries the try marker")
    public static function testLocalStep():Void {
        #if swift_output
        Test.equals(6, LocalThrowOps.localStep(5));
        #else
        Test.equals(true, true);
        #end
    }

    @:test("a local function throwing through another local function call")
    public static function testLocalNested():Void {
        #if swift_output
        Test.equals(12, LocalThrowOps.localNested(5));
        #else
        Test.equals(true, true);
        #end
    }

    @:test("a local call in a condition carries the try marker")
    public static function testLocalCondition():Void {
        #if swift_output
        Test.equals(true, LocalThrowOps.localCondition(3));
        #else
        Test.equals(true, true);
        #end
    }

    @:test("a local call inside an array literal carries the try marker")
    public static function testLocalArray():Void {
        #if swift_output
        Test.equals(4, LocalThrowOps.localArray(3)[0]);
        #else
        Test.equals(true, true);
        #end
    }

    @:test("the local fault is caught by the caller")
    public static function testCaughtLocal():Void {
        #if swift_output
        Test.equals(5007, LocalThrowOps.caughtLocal(0));
        #else
        Test.equals(true, true);
        #end
    }
}
