package tests;

import boring.NumberParsingOps;
import std.Test;

class NumberParsingTests {
	@:test("parseFloat accepts complete decimal tokens")
	public static function floatSuccess():Void {
		Test.equals(1.0, NumberParsingOps.parseFloat("  +1.  "));
		Test.equals(0.5, NumberParsingOps.parseFloat(".5"));
		Test.equals(125.0, NumberParsingOps.parseFloat("-1.25E+2"));
	}

	@:test("parseFloat rejects malformed and partial tokens as NaN")
	public static function floatFailure():Void {
		Test.equals(true, NumberParsingOps.failedFloat(""));
		Test.equals(true, NumberParsingOps.failedFloat("12x"));
		Test.equals(true, NumberParsingOps.failedFloat("1e"));
		Test.equals(true, NumberParsingOps.failedFloat("0x10"));
	}

	@:test("parseInt accepts decimal and hexadecimal tokens")
	public static function intSuccess():Void {
		Test.equals(42, NumberParsingOps.parseInt(" -42 "));
		Test.equals(16, NumberParsingOps.parseInt("0x10"));
		Test.equals(26, NumberParsingOps.parseInt("+0X1a"));
	}

	@:test("parseInt rejects partial and overflowing tokens as null")
	public static function intFailure():Void {
		Test.equals(true, NumberParsingOps.failedInt("12x"));
		Test.equals(true, NumberParsingOps.failedInt("0x"));
		Test.equals(true, NumberParsingOps.failedInt("2147483648"));
	}
}
