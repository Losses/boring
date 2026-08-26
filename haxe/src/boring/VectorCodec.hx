package boring;

import haxe.io.Bytes;

/**
 * Shared vector format codec: 4 magic bytes, one u32 record count, then one
 * 44-byte record per glyph metric (u32 code point, five f64 values), all
 * big-endian. The TypeScript and Rust suites read and write the same bytes.
 */
class VectorCodec {
	public static inline var MAGIC:String = "BRG1";

	public static function encode(records:Array<GlyphMetrics>):Bytes {
		final writer = new BinaryWriter();
		writer.writeAscii(MAGIC);
		writer.writeU32(records.length);
		for (record in records) {
			writer.writeU32(record.codePoint);
			writer.writeF64(record.advanceEm);
			writer.writeF64(record.bounds.xMin);
			writer.writeF64(record.bounds.yMin);
			writer.writeF64(record.bounds.xMax);
			writer.writeF64(record.bounds.yMax);
		}
		return writer.finish();
	}

	public static function decode(bytes:Bytes):Array<GlyphMetrics> {
		final reader = new BinaryReader(bytes);
		final magic = reader.readAscii(MAGIC.length);
		if (magic != MAGIC) {
			throw new haxe.Exception('bad vector magic: $magic');
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
			records.push({
				codePoint: codePoint,
				advanceEm: advanceEm,
				bounds: { xMin: xMin, yMin: yMin, xMax: xMax, yMax: yMax }
			});
		}
		if (reader.remaining() != 0) {
			throw new haxe.Exception('trailing bytes in vector: ${reader.remaining()}');
		}
		return records;
	}
}
