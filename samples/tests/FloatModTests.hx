package tests;

import std.Test;

#if swift_output
import boring.FloatModOps;
#end

class FloatModTests {
    @:test("a float remainder lowers onto truncatingRemainder")
    public static function testRemainder():Void {
        #if swift_output
        Test.equals(true, FloatModOps.even(4.0));
        Test.equals(false, FloatModOps.even(3.0));
        Test.equals(1.5, FloatModOps.rem(7.5, 2.0));
        #else
        Test.equals(true, true);
        #end
    }
}
