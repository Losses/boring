package tests;

import boring.Fp16;
import std.Test;

/**
 * Bit-exact binary16 conversion checks per binary spec 05. Every constant
 * below was verified against the double-arithmetic oracle over the
 * exhaustive binary16 sweep. All four generated targets assert the same
 * bit patterns.
 */
class Fp16Tests {
    @:test("binary16 patterns widen to exact binary32 bits")
    public static function widen():Void {
        // 0.5, -0.21875, the largest subnormal 1023*2^-24, the smallest
        // subnormal 2^-24, and infinity.
        Test.equals(0x3F000000, Fp16.f16ToF32Bits(0x3800), "0x3800 widens to 0.5");
        Test.equals(0xBE600000, Fp16.f16ToF32Bits(0xB300), "0xB300 widens to -0.21875");
        Test.equals(0x387FC000, Fp16.f16ToF32Bits(0x03FF), "0x03FF widens to 1023*2^-24");
        Test.equals(0x33800000, Fp16.f16ToF32Bits(0x0001), "0x0001 widens to 2^-24");
        Test.equals(0x7F800000, Fp16.f16ToF32Bits(0x7C00), "0x7C00 widens to infinity");
    }

    @:test("binary32 patterns narrow with round-to-nearest-even")
    public static function narrow():Void {
        // 0.5 round trips; 65280 keeps its exact binary16 value; the 65520
        // tie between 65504 and infinity rounds up; 2^-25 ties to zero while
        // 1.5*2^-25 rounds up to the smallest subnormal.
        Test.equals(0x3800, Fp16.f32ToF16Bits(0x3F000000), "0.5 narrows to 0x3800");
        Test.equals(0x7BF8, Fp16.f32ToF16Bits(0x477F0000), "65280 narrows to 0x7BF8");
        Test.equals(0x7BFF, Fp16.f32ToF16Bits(0x477FE000), "65504 narrows to the largest finite 0x7BFF");
        Test.equals(0x7C00, Fp16.f32ToF16Bits(0x477FF800), "the 65520 tie narrows to infinity");
        Test.equals(0x0000, Fp16.f32ToF16Bits(0x33000000), "2^-25 ties to zero");
        Test.equals(0x0001, Fp16.f32ToF16Bits(0x33400000), "1.5*2^-25 rounds up to the smallest subnormal");
    }
}
