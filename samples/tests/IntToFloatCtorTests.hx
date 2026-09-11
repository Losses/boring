package tests;

import std.Test;

#if swift_output
import boring.IntToFloatCtorOps;
#end

class IntToFloatCtorTests {
    @:test("an Int argument widens at a Float value-type constructor")
    public static function testWiden():Void {
        #if swift_output
        Test.equals(5.0, IntToFloatCtorOps.fromInt(5));
        #else
        Test.equals(true, true);
        #end
    }
}
