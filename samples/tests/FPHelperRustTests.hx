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

    @:test("floatToI32 reads stay signed through u32 struct fields")
    public static function decompose():Void {
        #if rust_output
        Test.equals(1, FPHelperRustOps.decompose(1.0).mant24);
        Test.equals(8388608, FPHelperRustOps.decompose(8388608.0).mant24);
        #end
    }
}
