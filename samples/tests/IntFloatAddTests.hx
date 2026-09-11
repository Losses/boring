package tests;

import std.Test;

#if swift_output
import boring.IntFloatAddOps;
#end

class IntFloatAddTests {
    @:test("an Int operand widens in a mixed Float addition")
    public static function testAdd():Void {
        #if swift_output
        Test.equals(3.5, IntFloatAddOps.addIntLeft(2));
        Test.equals(3.5, IntFloatAddOps.addIntRight(2));
        Test.equals(-1.0, IntFloatAddOps.addNested(2));
        #else
        Test.equals(true, true);
        #end
    }
}
