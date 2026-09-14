package tests;

import boring.SignedLoopBoundOps;
import std.Test;

class SignedLoopBoundOpsTests {
    @:test("a signed loop bound clamps into the u32 range endpoint")
    public static function fill():Void {
        #if rust_output
        Test.equals(3, SignedLoopBoundOps.fill(2, 4));
        Test.equals(0, SignedLoopBoundOps.fill(2, -3));
        #end
    }
}
