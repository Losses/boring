package tests;

import boring.GlyphMetrics;
import boring.VectorCodec;
import boring.VectorError;
import std.ReadOnlyArray;
import std.Test;

class VectorCodecTests {
	@:test("encode then decode returns the input records")
	public static function roundtrip():Void {
		final records:ReadOnlyArray<GlyphMetrics> = TestData.glyphSamples();
		final decoded = VectorCodec.decode(VectorCodec.encode(records));
		Test.equals(records, decoded, "decode(encode(records)) must equal the input");
	}

	@:test("boolean assertion")
	public static function testBool():Void {
		Test.equals(true, true);
	}

	@:test("integer assertion")
	public static function testInt():Void {
		Test.equals(42, 42);
	}

	@:test("float assertion")
	public static function testFloat():Void {
		Test.equals(0.5, 0.5);
	}

	@:test("string assertion")
	public static function testString():Void {
		Test.equals("hello\nworld\ttest", "hello\nworld\ttest");
	}

	@:test("bytes assertion")
	public static function testBytes():Void {
		Test.equals(TestData.sampleBytes(), TestData.sampleBytes());
	}

	@:test("array assertion")
	public static function testArray():Void {
		Test.equals([1, 2, 3], [1, 2, 3]);
	}

	@:test("structure assertion")
	public static function testStructure():Void {
		Test.equals(TestData.sampleBounds(), TestData.sampleBounds());
	}

	@:test("enum assertion")
	public static function testEnum():Void {
		Test.equals(VectorError.BadMagic, VectorError.BadMagic);
	}

	@:test("nan assertion using ok")
	public static function testNaN():Void {
		final nanVal:Float = Math.NaN;
		Test.ok(nanVal != nanVal, "NaN is not equal to itself under IEEE-754");
	}

	@:test
	public static function testWithoutDescription():Void {
		Test.ok(true);
	}
}
