package tests;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import std.Test;

class StringCodecTests {
    @:test("encodes and decodes ASCII")
    public static function asciiRoundTrip():Void {
        final bytes = Bytes.ofString("abc");
        Test.equals(3, bytes.length);
        Test.equals(0x61, bytes.get(0));
        Test.equals("abc", bytes.getString(0, 3));
    }

    @:test("encodes and decodes a two-byte character")
    public static function cjkRoundTrip():Void {
        final bytes = Bytes.ofString("\u6C49");
        Test.equals(3, bytes.length);
        Test.equals(0xE6, bytes.get(0));
        Test.equals("\u6C49", bytes.getString(0, 3));
    }

    @:test("encodes and decodes an astral character")
    public static function astralRoundTrip():Void {
        final bytes = Bytes.ofString("\u{20BB7}");
        Test.equals(4, bytes.length);
        Test.equals("\u{20BB7}", bytes.getString(0, 4));
    }

    @:test("empty string encodes to zero bytes")
    public static function emptyEncode():Void {
        final bytes = Bytes.ofString("");
        Test.equals(0, bytes.length);
        Test.equals("", bytes.getString(0, 0));
    }

    @:test("invalid bytes decode to U+FFFD")
    public static function invalidDecodesToReplacement():Void {
        final bytes = Bytes.alloc(2);
        bytes.set(0, 0xFF);
        bytes.set(1, 0xFE);
        Test.equals("\u{FFFD}", bytes.getString(0, 2));
    }

    @:test("a truncated multi-byte sequence decodes to U+FFFD")
    public static function truncatedSequence():Void {
        final bytes = Bytes.ofString("\u6C49");
        Test.equals("\u{FFFD}", bytes.getString(0, 2));
    }

    @:test("getString decodes a middle sub-range")
    public static function subRangeDecode():Void {
        final bytes = Bytes.ofString("a\u6C49b");
        Test.equals("\u6C49", bytes.getString(1, 3));
    }

    @:test("concat joins both operands in order")
    public static function concatJoins():Void {
        final left = Bytes.ofString("ab");
        final right = Bytes.ofString("\u6C49");
        #if boring_oracle
        final buffer = new BytesBuffer();
        buffer.add(left);
        buffer.add(right);
        final joined = buffer.getBytes();
        #else
        final joined = Bytes.concat(left, right);
        #end
        Test.equals(5, joined.length);
        Test.equals(0x61, joined.get(0));
        Test.equals("ab\u6C49", joined.getString(0, 5));
    }

    @:test("concat with an empty operand still copies")
    public static function concatEmpty():Void {
        final left = Bytes.ofString("ab");
        final right = Bytes.alloc(0);
        #if boring_oracle
        final buffer = new BytesBuffer();
        buffer.add(left);
        buffer.add(right);
        final joined = buffer.getBytes();
        #else
        final joined = Bytes.concat(left, right);
        #end
        Test.equals(2, joined.length);
        Test.equals("ab", joined.getString(0, 2));
    }

    @:test("concat never shares storage with its operands")
    public static function concatNoAlias():Void {
        final left = Bytes.ofString("ab");
        final right = Bytes.ofString("cd");
        #if boring_oracle
        final buffer = new BytesBuffer();
        buffer.add(left);
        buffer.add(right);
        final joined = buffer.getBytes();
        #else
        final joined = Bytes.concat(left, right);
        #end
        left.set(0, 0x7A);
        Test.equals(0x61, joined.get(0));
    }
}
