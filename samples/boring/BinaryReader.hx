package boring;

import haxe.io.Bytes;

/**
 * Cursor-based big-endian reader over an immutable byte buffer. Assembled u32
 * values keep their two's-complement bits: f64 bit parts feed FPHelper as raw
 * bits, and code points (at most 0x10FFFF) are always positive under this
 * representation.
 */
class BinaryReader {
    final bytes:Bytes;
    var offset:Int;

    public function new(bytes:Bytes) {
        this.bytes = bytes;
        offset = 0;
    }

    function ensureRemaining(length:Int):Void {
        if (bytes.length - offset < length) {
            throw new VectorException(UnexpectedEof);
        }
    }

    public function readU16():Int {
        ensureRemaining(2);
        final value = (bytes.get(offset) << 8) | bytes.get(offset + 1);
        offset += 2;
        return value;
    }

    public function readU32():Int {
        ensureRemaining(4);
        final value = (bytes.get(offset) << 24) | (bytes.get(offset + 1) << 16) | (bytes.get(offset + 2) << 8) | bytes.get(offset + 3);
        offset += 4;
        return value;
    }

    public function readF64():Float {
        final high = readU32();
        final low = readU32();
        return haxe.io.FPHelper.i64ToDouble(low, high);
    }

    public function readF32():Float {
        return Fp32.fromBits(readU32());
    }

    public function readF16():Float {
        return Fp32.fromBits(Fp16.f16ToF32Bits(readU16()));
    }

    public function readAscii(length:Int):String {
        ensureRemaining(length);
        final parts = new Array<String>();
        for (index in 0...length) {
            parts.push(String.fromCharCode(bytes.get(offset + index)));
        }
        offset += length;
        return parts.join("");
    }

    public function remaining():Int {
        return bytes.length - offset;
    }

    public function consumed():Int {
        return offset;
    }
}
