package tests;

import boring.FPHelperRustOps;
import std.Test;

class FPHelperRustTests {
    @:test("an FPHelper bit edge reinterprets a u32 Int argument")
    public static function valueOf():Void {
        #if rust_output
        Test.equals(true, FPHelperRustOps.valueOf(42) == 42.0);
        #end
    }
}
