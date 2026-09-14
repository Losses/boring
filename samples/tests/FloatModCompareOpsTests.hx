package tests;

import boring.FloatModCompareOps;
import std.Test;

class FloatModCompareOpsTests {
    @:test("a Float remainder compares zero in the Float domain")
    public static function even():Void {
        #if rust_output
        Test.equals(true, FloatModCompareOps.even(4.0));
        Test.equals(false, FloatModCompareOps.even(3.0));
        #end
    }
}
