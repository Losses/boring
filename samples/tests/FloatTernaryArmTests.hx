package tests;

import std.Test;

#if swift_output
import boring.FloatTernaryArmOps;
#end

class FloatTernaryArmTests {
    @:test("a mixed int arm widens inside a float ternary")
    public static function testCost():Void {
        #if swift_output
        Test.equals(4.0, FloatTernaryArmOps.cost(true));
        Test.equals(0.0, FloatTernaryArmOps.cost(false));
        Test.equals(8.0, FloatTernaryArmOps.doubled(true));
        #else
        Test.equals(true, true);
        #end
    }
}
