package boring;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;

/**
 * Sequential big-endian writer over a growable byte buffer. The u32 domain of
 * this repository is code points and record counts, both far below 2^31, so
 * signed Int carries every value used here without sign concerns.
 */
class BinaryWriter {
	final buffer:BytesBuffer;

	public function new() {
		buffer = new BytesBuffer();
	}

	public function writeU16(value:Int):Void {
		buffer.addByte((value >>> 8) & 0xFF);
		buffer.addByte(value & 0xFF);
	}

	public function writeU32(value:Int):Void {
		buffer.addByte((value >>> 24) & 0xFF);
		buffer.addByte((value >>> 16) & 0xFF);
		buffer.addByte((value >>> 8) & 0xFF);
		buffer.addByte(value & 0xFF);
	}

	public function writeF64(value:Float):Void {
		final bits = haxe.io.FPHelper.doubleToI64(value);
		// The Int64 halves carry raw two's-complement bits; writing them as
		// two u32 words keeps the byte order identical on every target.
		writeU32(bits.high);
		writeU32(bits.low);
	}

	public function writeAscii(value:String):Void {
		for (index in 0...value.length) {
			buffer.addByte(value.charCodeAt(index) & 0xFF);
		}
	}

	public function finish():Bytes {
		return buffer.getBytes();
	}
}
