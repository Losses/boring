package tests;

import boring.SignedIntAssignOps;
import std.Test;

class SignedIntAssignOpsTests {
    @:test("a u32 local assigned an i32-domain sum reinterprets the result")
    public static function advance():Void {
        #if rust_output
        Test.equals(3, SignedIntAssignOps.advance("abx"));
        Test.equals(0, SignedIntAssignOps.advance("abc"));
        #end
    }
}
