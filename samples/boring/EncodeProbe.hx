package boring;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;

/**
 * Minimal reproduction: a Bytes-returning function named "encode" on a class
 * that is NOT a runtime shim. The runtimeShimIsFallible("encode") name rule
 * wrongly adds .unwrap() to its call sites, failing with E0599 when the
 * Rust return type is Vec<u8> (not Result).
 */
class EncodeProbe {
    public static function encode(value:Int):Bytes {
        final buf = new BytesBuffer();
        buf.addByte((value >>> 8) & 0xFF);
        buf.addByte(value & 0xFF);
        return buf.getBytes();
    }

    public static function roundTrip(value:Int):Int {
        final bytes = encode(value);
        return (bytes.get(0) << 8) | bytes.get(1);
    }

    public static function encodeWithReturn(value:Int):Bytes {
        return encode(value);
    }
}
