package boring.protocol;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import haxe.crypto.Sha256;

/**
 * One framed field of a P-23 protocol fingerprint (CanonicalFingerprint).
 * The value bytes are already canonical for the declared type tag; floats come
 * from FloatCanonical.encode64/encode32, and the marker signals null.
 */
typedef FingerprintField = {
    var key:String;
    var typeTag:Int;
    var isNull:Bool;
    var value:Bytes;
};

/**
 * P-23 protocol fingerprint: SHA-256 over a canonical byte framing. Every
 * field contributes, in declaration order: u16 key byte length (big-endian),
 * the key's UTF-8 bytes, a u8 type tag, a u8 null marker (0 present / 1 null),
 * then the canonical value bytes when present. SHA-256 is the fixed digest.
 */
@:mainOnly
class CanonicalFingerprint {
    public static final TAG_F64:Int = 1;
    public static final TAG_F32:Int = 2;
    public static final TAG_I64:Int = 3;
    public static final TAG_BOOL:Int = 4;
    public static final TAG_STR:Int = 5;

    public static function encode(fields:Array<FingerprintField>):Bytes {
        final buf = new BytesBuffer();
        for (field in fields) {
            final keyBytes = Bytes.ofString(field.key);
            buf.addByte((keyBytes.length >>> 8) & 0xFF);
            buf.addByte(keyBytes.length & 0xFF);
            buf.add(keyBytes);
            buf.addByte(field.typeTag & 0xFF);
            buf.addByte(field.isNull ? 1 : 0);
            if (!field.isNull) {
                buf.add(field.value);
            }
        }
        return Sha256.make(buf.getBytes());
    }
}
