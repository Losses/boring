package tests;

import boring.BytesOps;
import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import std.Test;

class BytesTests {
    @:test("allocates and mutates fixed-length bytes")
    public static function fixedMutation():Void {
        final bytes = BytesOps.build();
        Test.equals(8, bytes.length);
        Test.equals(1, bytes.get(0));
        Test.equals(2, bytes.get(1));
        Test.equals(11, bytes.get(2));
        Test.equals(12, bytes.get(3));
        Test.equals(13, bytes.get(4));
        Test.equals(0xA5, bytes.get(5));
        Test.equals(0xA5, bytes.get(6));
        Test.equals(0, bytes.get(7));
    }

    @:test("appends whole byte segments through add")
    public static function bufferAdd():Void {
        final first = BytesOps.build();
        final second = Bytes.alloc(2);
        second.set(0, 0x42);
        second.set(1, 0x43);
        final buffer = new BytesBuffer();
        buffer.add(first);
        buffer.add(second);
        final joined = buffer.getBytes();
        Test.equals(10, joined.length);
        Test.equals(1, joined.get(0));
        Test.equals(0x43, joined.get(9));
        second.set(0, 0xFF);
        Test.equals(0x42, joined.get(8));
    }

    @:test("add with an empty argument appends nothing")
    public static function bufferAddEmpty():Void {
        final buffer = new BytesBuffer();
        buffer.addByte(7);
        buffer.add(Bytes.alloc(0));
        final out = buffer.getBytes();
        Test.equals(1, out.length);
        Test.equals(7, out.get(0));
    }
}
