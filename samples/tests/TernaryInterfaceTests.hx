package tests;

import std.Test;

#if swift_output
import boring.TernaryInterfaceOps;
#end

class TernaryInterfaceTests {
    @:test("ternary arms widen to the interface they unified on")
    public static function testChoose():Void {
        #if swift_output
        Test.equals("alpha", TernaryInterfaceOps.label(0));
        Test.equals("beta", TernaryInterfaceOps.label(1));
        #else
        Test.equals(true, true);
        #end
    }
}
