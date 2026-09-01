package tests;

import boring.Fp32;
import std.Test;

/**
 * Bit-exact binary32 edge checks per binary spec 05. The half inputs and
 * every expected pattern were verified against the native setFloat32 edge;
 * the float literals are exact at binary16 precision, so the checks hold on
 * the f32 module-real configuration of feature spec 23 as well.
 */
class Fp32Tests {
	@:test("binary64 halves round to binary32 bits with ties to even")
	public static function halvesToBits():Void {
		// An exact half remainder under an even significand stays; the same
		// remainder under an odd significand rounds up.
		Test.equals(0x3F800002, Fp32.f64HalvesToF32Bits(0x30000000, 0x3FF00000), "odd significand rounds up at the half");
		Test.equals(0x3F800000, Fp32.f64HalvesToF32Bits(0x10000000, 0x3FF00000), "even significand stays at the half");
		// A subnormal target that rounds past the largest subnormal produces
		// the smallest normal, exponent one with a zero mantissa.
		Test.equals(0x00800000, Fp32.f64HalvesToF32Bits(0xE0000000, 0x380FFFFF), "rounding past the largest subnormal produces the smallest normal");
	}

	@:test("binary32 bits widen exactly and round back")
	public static function bitsRoundTrip():Void {
		Test.equals(0.5, Fp32.fromBits(0x3F000000), "0x3F000000 widens to 0.5");
		Test.equals(-0.21875, Fp32.fromBits(0xBE600000), "0xBE600000 widens to -0.21875");
		Test.equals(0x3F000000, Fp32.toBits(0.5), "0.5 rounds to 0x3F000000");
		Test.equals(0xBE600000, Fp32.toBits(-0.21875), "-0.21875 rounds to 0xBE600000");
	}
}
