package boring;

import std.ReadOnlyArray;

import haxe.io.Bytes;

/**
 * Shared vector format codec: 4 magic bytes, one u32 record count, then one
 * 44-byte record per glyph metric (u32 code point, five f64 values), all
 * big-endian. The TypeScript and Rust suites read and write the same bytes.
 * Encode reads through the read-only array type and decode returns it, per
 * docs/specs/features/18-immutability.md.
 */
class VectorCodec {
	public static inline var MAGIC:String = "BRG1";

	public static function encode(records:ReadOnlyArray<GlyphMetrics>):Bytes {
		final writer = new BinaryWriter();
		writer.writeAscii(MAGIC);
		writer.writeU32(records.length);
		for (index in 0...records.length) {
			final record = records[index];
			writer.writeU32(record.codePoint);
			writer.writeF64(record.advanceEm);
			writer.writeF64(record.bounds.xMin);
			writer.writeF64(record.bounds.yMin);
			writer.writeF64(record.bounds.xMax);
			writer.writeF64(record.bounds.yMax);
		}
		return writer.finish();
	}

	public static function decode(bytes:Bytes):ReadOnlyArray<GlyphMetrics> {
		final reader = new BinaryReader(bytes);
		final magic = reader.readAscii(MAGIC.length);
		if (magic != MAGIC) {
			throw new VectorException(BadMagic);
		}
		final count = reader.readU32();
		final records = new Array<GlyphMetrics>();
		for (index in 0...count) {
			final codePoint = reader.readU32();
			final advanceEm = reader.readF64();
			final xMin = reader.readF64();
			final yMin = reader.readF64();
			final xMax = reader.readF64();
			final yMax = reader.readF64();
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
