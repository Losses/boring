package tests;

import boring.NegativeSentinelOps;
import std.Test;

class NegativeSentinelOpsTests {
    @:test("a negative sentinel local keeps one domain across its uses")
    public static function separatorIndex():Void {
        #if rust_output
        Test.equals(2, NegativeSentinelOps.separatorIndex("ab-cd"));
        Test.equals(0, NegativeSentinelOps.separatorIndex("-"));
        Test.equals(-1, NegativeSentinelOps.separatorIndex("ab"));
        #end
    }
}
