package tests;

import boring.FPHelperRustOps;
import std.Test;
#if rust_output
import haxe.io.FPHelper;
#end

class FPHelperRustTests {
    @:test("an FPHelper bit edge reinterprets a u32 Int argument")
    public static function valueOf():Void {
        #if rust_output
        // i32ToFloat is a bit reinterpretation (like TS/Dart/Kotlin), so
        // i32ToFloat(42) is the denormal whose raw bits are 42, not 42.0;
        // the round-trip through floatToI32 must reproduce those bits.
        Test.equals(42, FPHelper.floatToI32(FPHelperRustOps.valueOf(42)));
        #end
    }

    @:test("floatToI32 reads stay signed through u32 struct fields")
    public static function decompose():Void {
        #if rust_output
        // Bit semantics: 1.0f has raw bits 0x3F800000, so the implicit
        // mantissa bit is set and the unbiased exponent is -23; 2^23 has
        // raw bits 0x4B000000, exponent field 150 -> exp2 = 0.
        Test.equals(8388608, FPHelperRustOps.decompose(1.0).mant24);
        Test.equals(-23, FPHelperRustOps.decompose(1.0).exp2);
        Test.equals(8388608, FPHelperRustOps.decompose(8388608.0).mant24);
        Test.equals(0, FPHelperRustOps.decompose(8388608.0).exp2);
        #end
    }
}
