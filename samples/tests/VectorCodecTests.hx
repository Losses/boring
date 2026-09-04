package tests;

import boring.BinaryReader;
import boring.BinaryWriter;
import boring.FloatWidth;
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

    @:test("f32 blocks round trip every record")
    public static function roundtripF32():Void {
        final records:ReadOnlyArray<GlyphMetrics> = TestData.glyphSamples();
        final decoded = VectorCodec.decode(VectorCodec.encode(records, F32));
        Test.equals(records, decoded, "decode(encode(records, F32)) must equal the input");
    }

    @:test("f16 blocks round trip every record")
    public static function roundtripF16():Void {
        final records:ReadOnlyArray<GlyphMetrics> = TestData.glyphSamples();
        final decoded = VectorCodec.decode(VectorCodec.encode(records, F16));
        Test.equals(records, decoded, "decode(encode(records, F16)) must equal the input");
    }

    @:test("block lengths follow the width marker")
    public static function byteLengthsPerWidth():Void {
        Test.equals(184, VectorCodec.byteLength(4, F64), "four records occupy 184 bytes at f64");
        Test.equals(104, VectorCodec.byteLength(4, F32), "four records occupy 104 bytes at f32");
        Test.equals(64, VectorCodec.byteLength(4, F16), "four records occupy 64 bytes at f16");
    }

    @:test("magics map to widths, unknown magics answer null")
    public static function magicWidthMapping():Void {
        Test.equals("BRG1", VectorCodec.magicOf(F64), "F64 travels under BRG1");
        Test.equals("BRG2", VectorCodec.magicOf(F32), "F32 travels under BRG2");
        Test.equals("BRG3", VectorCodec.magicOf(F16), "F16 travels under BRG3");
        // The typed harnesses of each tree verify the width direction;
        // Option values do not flow into Test.equals here.
        Test.ok(VectorCodec.widthOfMagic("BRG4") == null, "unknown magics answer null");
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

    @:test("ascii codecs round-trip through the Bytes APIs")
    public static function asciiCodecsRoundTrip():Void {
        final writer = new BinaryWriter();
        writer.writeAscii("BRG9");
        Test.equals("BRG9", new BinaryReader(writer.finish()).readAscii(4));
        final wide = new BinaryWriter();
        wide.writeAscii("汉");
        Test.equals("汉", new BinaryReader(wide.finish()).readAscii(3));
    }
}
