package tests;

import boring.StringBufOps;
import std.StringBuf;
import std.Test;

class StringBufTests {
	@:test("empty buffer has length zero and empty toString")
	public static function testEmptyBuffer():Void {
		final buf = new StringBuf();
		Test.equals(0, buf.length);
		Test.equals("", buf.toString());
	}

	@:test("add appends strings and updates length")
	public static function testAddStrings():Void {
		final res = StringBufOps.buildParts("hello", " ", "world");
		Test.equals("hello world", res);
		Test.equals(11, StringBufOps.measureLength(["hello", " ", "world"]));
	}

	@:test("add with supplementary characters counts UTF-16 code units")
	public static function testSupplementaryCharacters():Void {
		final buf = new StringBuf();
		buf.add("hi");
		buf.add("🚀");
		buf.add("!");
		Test.equals("hi🚀!", buf.toString());
		Test.equals(5, buf.length);
	}

	@:test("addChar appends BMP characters")
	public static function testAddChar():Void {
		final res = StringBufOps.buildWithChars("item-", 65, 66);
		Test.equals("item-AB", res);
	}

	@:test("buffer extends after toString calls")
	public static function testIncremental():Void {
		final steps = StringBufOps.buildIncremental();
		Test.equals("step1", steps[0]);
		Test.equals("step1-step2", steps[1]);
	}
}
