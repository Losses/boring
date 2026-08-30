package boring;

import std.ReadOnlyArray;

import haxe.io.Bytes;

/**
 * Shared vector format codec per binary specs 01 and 05: a 4-byte magic that
 * declares the block float width (BRG1 f64, BRG2 f32, BRG3 f16), one u32
 * record count, then one fixed-width record per glyph metric (u32 code point
 * plus five floats at the block width), all big-endian. The TypeScript,
 * Rust, and Kotlin suites read and write the same bytes. Encode reads
 * through the read-only array type and decode returns it, per
 * docs/specs/features/18-immutability.md.
 */
class VectorCodec {
	public static inline var MAGIC_F64:String = "BRG1";
	public static inline var MAGIC_F32:String = "BRG2";
	public static inline var MAGIC_F16:String = "BRG3";

	// The Kotlin subset carries no switch lowering, so width dispatch runs
	// through enum equality branches everywhere in this class.
	public static function magicOf(width:FloatWidth):String {
		if (width == F64) {
			return MAGIC_F64;
		} else if (width == F32) {
			return MAGIC_F32;
		} else {
			return MAGIC_F16;
		}
	}

	/**
		Unknown magics answer null, which decode reports as BadMagic; a
		reader built before a width existed rejects the block explicitly
		instead of misreading its records.
	**/
	public static function widthOfMagic(magic:String):Null<FloatWidth> {
		if (!isKnownMagic(magic)) {
			return null;
		}
		return knownWidthOf(magic);
	}

	static function isKnownMagic(magic:String):Bool {
		return magic == MAGIC_F64 || magic == MAGIC_F32 || magic == MAGIC_F16;
	}

	// decode reaches the width through the known-magic guard, so the enum
	// flows on without a nullable wrapper.
	static function knownWidthOf(magic:String):FloatWidth {
		if (magic == MAGIC_F64) return F64;
		if (magic == MAGIC_F32) return F32;
		return F16;
	}

	public static function byteLength(recordCount:Int, width:FloatWidth):Int {
		if (width == F64) {
			return 8 + recordCount * 44;
		} else if (width == F32) {
			return 8 + recordCount * 24;
		} else {
			return 8 + recordCount * 14;
		}
	}

	public static function encode(records:ReadOnlyArray<GlyphMetrics>, width:FloatWidth = FloatWidth.F64):Bytes {
		final writer = new BinaryWriter();
		writer.writeAscii(magicOf(width));
		writer.writeU32(records.length);
		for (index in 0...records.length) {
			final record = records[index];
			writer.writeU32(record.codePoint);
			// The width dispatch stays inline: a helper taking the writer
			// would move the class into parameter position, which the Rust
			// face borrows differently from local use.
			if (width == F64) {
				writer.writeF64(record.advanceEm);
			} else if (width == F32) {
				writer.writeF32(record.advanceEm);
			} else {
				writer.writeF16(record.advanceEm);
			}
			if (width == F64) {
				writer.writeF64(record.bounds.xMin);
			} else if (width == F32) {
				writer.writeF32(record.bounds.xMin);
			} else {
				writer.writeF16(record.bounds.xMin);
			}
			if (width == F64) {
				writer.writeF64(record.bounds.yMin);
			} else if (width == F32) {
				writer.writeF32(record.bounds.yMin);
			} else {
				writer.writeF16(record.bounds.yMin);
			}
			if (width == F64) {
				writer.writeF64(record.bounds.xMax);
			} else if (width == F32) {
				writer.writeF32(record.bounds.xMax);
			} else {
				writer.writeF16(record.bounds.xMax);
			}
			if (width == F64) {
				writer.writeF64(record.bounds.yMax);
			} else if (width == F32) {
				writer.writeF32(record.bounds.yMax);
			} else {
				writer.writeF16(record.bounds.yMax);
			}
		}
		return writer.finish();
	}

	public static function decode(bytes:Bytes):ReadOnlyArray<GlyphMetrics> {
		final reader = new BinaryReader(bytes);
		final magic = reader.readAscii(4);
		if (!isKnownMagic(magic)) {
			throw new VectorException(BadMagic);
		}
		final width = knownWidthOf(magic);
		final count = reader.readU32();
		if (count < 0) {
			throw new VectorException(CountOverflow);
		}
		final records = new Array<GlyphMetrics>();
		for (index in 0...count) {
			final codePoint = reader.readU32();
			final advanceEm = width == F64 ? reader.readF64() : (width == F32 ? reader.readF32() : reader.readF16());
			final xMin = width == F64 ? reader.readF64() : (width == F32 ? reader.readF32() : reader.readF16());
			final yMin = width == F64 ? reader.readF64() : (width == F32 ? reader.readF32() : reader.readF16());
			final xMax = width == F64 ? reader.readF64() : (width == F32 ? reader.readF32() : reader.readF16());
			final yMax = width == F64 ? reader.readF64() : (width == F32 ? reader.readF32() : reader.readF16());
			records[index] = {
				codePoint: codePoint,
				advanceEm: advanceEm,
				bounds: { xMin: xMin, yMin: yMin, xMax: xMax, yMax: yMax }
			};
		}
		if (reader.remaining() != 0) {
			throw new VectorException(TrailingBytes(reader.remaining()));
		}
		return records;
	}

}
