package tests;

import boring.RuntimeExportOps;
import std.Test;

/**
    Assertion coverage for the runtime-export ops (docs/specs/stdlib/05).
    The bit-pattern checks use dyadic rationals the binary32 edge widens
    to exactly, so every target reports the same integer bits.
**/
class RuntimeExportTests {
	@:test("binary32 float bits widen from a round number")
	public static function testFloatToBits():Void {
		Test.equals(0x3F800000, RuntimeExportOps.floatToBits(1.0));
		Test.equals(0x3F000000, RuntimeExportOps.floatToBits(0.5));
		Test.equals(0x40200000, RuntimeExportOps.floatToBits(2.5));
	}

	@:test("binary32 bit patterns widen to a float")
	public static function testBitsToFloat():Void {
		Test.equals(1.0, RuntimeExportOps.bitsToFloat(0x3F800000));
		Test.equals(0.5, RuntimeExportOps.bitsToFloat(0x3F000000));
		Test.equals(2.5, RuntimeExportOps.bitsToFloat(0x40200000));
	}

	@:test("binary32 bits round-trip through the edge helpers")
	public static function testFloatRoundTrip():Void {
		Test.equals(1.0, RuntimeExportOps.roundTripFloat(1.0));
		Test.equals(0.5, RuntimeExportOps.roundTripFloat(0.5));
		Test.equals(2.5, RuntimeExportOps.roundTripFloat(2.5));
	}

	@:test("UString code-point helpers are exported from the runtime module")
	public static function testUStringExports():Void {
		Test.equals(6, RuntimeExportOps.asciiCount());
		Test.equals(116, RuntimeExportOps.codeAt("tiqian", 0));
		Test.equals(null, RuntimeExportOps.codeAt("tiqian", 6));
		Test.equals("tiqian", RuntimeExportOps.codePointsRoundTrip("tiqian"));
		Test.equals("提椠排版", RuntimeExportOps.codePointsRoundTrip("提椠排版"));
	}
}
