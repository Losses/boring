package tests;

import std.Test;

#if swift_output
import boring.TernaryOptionalOps;
#end

class TernaryOptionalTests {
    @:test("an optional ternary branch unwraps for a non-optional result")
    public static function testChoose():Void {
        #if swift_output
        Test.equals(7, TernaryOptionalOps.choose(7, 1));
        Test.equals(121856, TernaryOptionalOps.choose(7, 56320));
        #else
        Test.equals(true, true);
        #end
    }
}
