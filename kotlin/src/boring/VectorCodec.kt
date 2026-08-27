package boring

import java.util.ArrayList

/**
 * Shared vector format codec: 4 magic bytes, one u32 record count, then one
 * 44-byte record per glyph metric (u32 code point, five f64 values), all
 * big-endian. The TypeScript, Rust, and Haxe suites read and write the same
 * bytes.
 */
object VectorCodec {
    const val MAGIC: String = "BRG1"

    fun encode(records: List<GlyphMetrics>): ByteArray {
        val writer = BinaryWriter()
        writer.writeAscii(MAGIC)
        writer.writeU32(records.size)
        for (index in records.indices) {
            val record = records[index]
            writer.writeU32(record.codePoint)
            writer.writeF64(record.advanceEm)
            writer.writeF64(record.bounds.xMin)
            writer.writeF64(record.bounds.yMin)
            writer.writeF64(record.bounds.xMax)
            writer.writeF64(record.bounds.yMax)
        }
        return writer.finish()
    }

    fun decode(bytes: ByteArray): ArrayList<GlyphMetrics> {
        val reader = BinaryReader(bytes)
        val magic = reader.readAscii(MAGIC.length)
        if (magic != MAGIC) {
            throw VectorException.BadMagic
        }
        val count = reader.readU32()
        val records = ArrayList<GlyphMetrics>(count)
        for (index in 0 until count) {
            val codePoint = reader.readU32()
            val advanceEm = reader.readF64()
            val xMin = reader.readF64()
            val yMin = reader.readF64()
            val xMax = reader.readF64()
            val yMax = reader.readF64()
            records.add(
                GlyphMetrics(
                    codePoint = codePoint,
                    advanceEm = advanceEm,
                    bounds = GlyphBounds(
                        xMin = xMin,
                        yMin = yMin,
                        xMax = xMax,
                        yMax = yMax
                    )
                )
            )
        }
        if (reader.remaining() != 0) {
            throw VectorException.TrailingBytes(reader.remaining())
        }
        return records
    }
}
