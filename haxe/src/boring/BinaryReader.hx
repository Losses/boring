package boring;

import haxe.io.Bytes;

/**
 * Cursor-based big-endian reader over an immutable byte buffer. Assembled u32
 * values keep their two's-complement bits: f64 halves feed FPHelper as raw
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

	public function readU16():Int {
		final value = (bytes.get(offset) << 8) | bytes.get(offset + 1);
		offset += 2;
		return value;
	}

	public function readU32():Int {
		final value = (bytes.get(offset) << 24)
			| (bytes.get(offset + 1) << 16)
			| (bytes.get(offset + 2) << 8)
			| bytes.get(offset + 3);
		offset += 4;
		return value;
	}

	public function readF64():Float {
		final high = readU32();
		final low = readU32();
		return haxe.io.FPHelper.i64ToDouble(low, high);
	}

	public function readAscii(length:Int):String {
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
