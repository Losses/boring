package boring.protocol;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;

/**
 * P-23 canonical float observation bytes (encode64/encode32). The bytes are the
 * authoritative observation for cross-target float equality: both
 * signed zeroes encode as zero bits, every NaN as the width's quiet-NaN token,
 * and any other value as its IEEE bits, all big-endian. encode32 never widens a
 * binary32 value to binary64 before reading its bits, so an f32 NaN payload
 * cannot leak f64 bits into the stream.
 */
@:mainOnly
class FloatCanonical {
    public static function encode64(value:Float):Bytes {
        final out = new BytesBuffer();
        var high = 0;
        var low = 0;
        if (value == 0.0) {
            high = 0;
            low = 0;
        } else if (Math.isNaN(value)) {
            high = 0x7FF80000;
            low = 0;
        } else {
            final bits = haxe.io.FPHelper.doubleToI64(value);
            high = bits.high;
            low = bits.low;
        }
        out.addByte((high >>> 24) & 0xFF);
        out.addByte((high >>> 16) & 0xFF);
        out.addByte((high >>> 8) & 0xFF);
        out.addByte(high & 0xFF);
        out.addByte((low >>> 24) & 0xFF);
        out.addByte((low >>> 16) & 0xFF);
        out.addByte((low >>> 8) & 0xFF);
        out.addByte(low & 0xFF);
        return out.getBytes();
    }

    public static function encode32(value:Float):Bytes {
        final out = new BytesBuffer();
        var bits = 0;
        if (value == 0.0) {
            bits = 0;
        } else if (Math.isNaN(value)) {
            bits = 0x7FC00000;
        } else {
            bits = haxe.io.FPHelper.floatToI32(value);
        }
        out.addByte((bits >>> 24) & 0xFF);
        out.addByte((bits >>> 16) & 0xFF);
        out.addByte((bits >>> 8) & 0xFF);
        out.addByte(bits & 0xFF);
        return out.getBytes();
    }

    /** The lowercase hex text of the observation bytes (test-facing). */
    public static function hex(b:haxe.io.Bytes):String {
        final digits = "0123456789abcdef";
        var out = "";
        for (i in 0...b.length) {
            final v = b.get(i);
            out += digits.charAt((v >>> 4) & 0xF);
            out += digits.charAt(v & 0xF);
        }
        return out;
    }
}
