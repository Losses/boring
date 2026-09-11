package tests;

import std.Test;

#if swift_output
import boring.FPHelperSwiftOps;
#end

class FPHelperSwiftTests {
    @:test("binary32 bit edges round-trip through the runtime pair")
    public static function testRoundTrip():Void {
        #if swift_output
        Test.equals(1065353216, FPHelperSwiftOps.bitsOf(1.0));
        Test.equals(true, FPHelperSwiftOps.valueOf(1065353216) == 1.0);
        Test.equals(true, FPHelperSwiftOps.roundTrip(2.5) == 2.5);
        #else
        Test.equals(true, true);
        #end
    }
}
