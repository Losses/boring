package tests;

import boring.UStringOps;
import std.Test;
import std.UString;

class UStringTests {
	@:test("ascii content counts and reads through the general tier")
	public static function testAsciiTier():Void {
		Test.equals(6, UStringOps.asciiCount());
		Test.equals(116, UStringOps.codeAt("tiqian", 0));
		Test.equals(null, UStringOps.codeAt("tiqian", 6));
	}

	@:test("bmp cjk counts and reads by code point")
	public static function testBmpTier():Void {
		Test.equals(4, UStringOps.bmpCount());
		Test.equals(0x63D0, UStringOps.codeAt("提椠排版", 0));
		Test.equals(0x6920, UStringOps.codeAt("提椠排版", 1));
		Test.equals(0x7248, UStringOps.codeAt("提椠排版", 3));
		Test.equals(null, UStringOps.codeAt("提椠排版", 4));
	}

	@:test("supplementary cjk occupies one character index")
	public static function testSupplementaryTier():Void {
		Test.equals(3, UStringOps.supplementaryCount());
		Test.equals(0x20000, UStringOps.codeAt("𠀀一𠀁", 0));
		Test.equals(0x4E00, UStringOps.codeAt("𠀀一𠀁", 1));
		Test.equals(0x20001, UStringOps.codeAt("𠀀一𠀁", 2));
		Test.equals(null, UStringOps.codeAt("𠀀一𠀁", 3));
	}

	@:test("slice addresses characters on every storage")
	public static function testSlice():Void {
		Test.equals("椠排", UStringOps.middleSlice("提椠排版"));
		Test.equals("一𠀁", UStringOps.middleSlice("𠀀一𠀁"));
		Test.equals("提椠排版", UStringOps.clampedSlice("提椠排版"));
	}

	@:test("code point round trip preserves content")
	public static function testRoundTrip():Void {
		Test.equals("提椠排版", UStringOps.roundTrip("提椠排版"));
		Test.equals("𠀀一𠀁", UStringOps.roundTrip("𠀀一𠀁"));
		Test.equals("𠀀", UString.fromCodePoint(0x20000));
		Test.equals("一", UString.fromCodePoint(0x4E00));
	}

	@:test("character reversal keeps supplementary characters whole")
	public static function testReversal():Void {
		Test.equals("版排椠提", UStringOps.reversedText("提椠排版"));
		Test.equals("𠀁一𠀀", UStringOps.reversedText("𠀀一𠀁"));
	}

	@:test("substring addresses utf-16 unit positions on every target")
	public static function testSubstring():Void {
		Test.equals("椠排", UStringOps.substringRange("提椠排版", 1, 3));
		Test.equals("𠀀", UStringOps.substringRange("𠀀一𠀁", 0, 2));
		Test.equals("一", UStringOps.substringRange("𠀀一𠀁", 2, 3));
		Test.equals("一𠀁", UStringOps.substringRange("𠀀一𠀁", 2, 5));
		Test.equals("𠀁", UStringOps.substringFrom("𠀀一𠀁", 3));
		Test.equals("iq", UStringOps.substringLiteral());
	}
}
