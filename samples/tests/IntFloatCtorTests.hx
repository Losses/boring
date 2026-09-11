package tests;

import std.Test;

#if swift_output
import boring.IntFloatCtorOps;
#end

class IntFloatCtorTests {
    @:test("an Int argument widens into a Float constructor parameter")
    public static function testWidening():Void {
        #if swift_output
        Test.equals(true, IntFloatCtorOps.ctorValue(3) == 3.0);
        Test.equals(true, IntFloatCtorOps.sum(4) == 4.25);
        #else
        Test.equals(true, true);
        #end
    }
}
