package tests;

import std.Test;

#if rust_output
import boring.NumericCoalesceLocalOps;
#end

class NumericCoalesceLocalOpsTests {
    @:test("a coalesced Int local feeds a scalar argument without a bridge")
    public static function testCoalescedLocal():Void {
        #if rust_output
        Test.equals(6, NumericCoalesceLocalOps.pick(5));
        Test.equals(6, NumericCoalesceLocalOps.pick(null));
        Test.equals(3, NumericCoalesceLocalOps.sumPair(null, null));
        Test.equals(30, NumericCoalesceLocalOps.sumPair(10, 20));
        #end
        Test.equals(true, true);
    }
}
