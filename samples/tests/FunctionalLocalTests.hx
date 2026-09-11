package tests;

import std.Test;

#if swift_output
import boring.FunctionalLocalOps;
#end

class FunctionalLocalTests {
    @:test("sumOfFloat in a local function lowers onto reduce")
    public static function testDoubled():Void {
        #if swift_output
        Test.equals(12.0, FunctionalLocalOps.doubled([1.5, 2.0, 2.5]));
        #else
        Test.equals(true, true);
        #end
    }

    @:test("forEach in a local function lowers onto the array method")
    public static function testCounted():Void {
        #if swift_output
        Test.equals(10, FunctionalLocalOps.counted([1, 2, 3, 4]));
        #else
        Test.equals(true, true);
        #end
    }
}
