package boring

/**
 * Shared vector format codec per binary specs 01 and 05: 4 magic bytes that
 * declare the block float width (BRG1 f64, BRG2 f32, BRG3 f16), one u32
 * record count, then one fixed-width record per glyph metric (u32 code point
 * plus five floats at the block width), all big-endian. The Haxe,
 * TypeScript, and Rust suites read and write the same bytes. Decode fills
 * through the array initializer ruled in docs/specs/stdlib/04-haxe-ds-vector.md
 * and returns the read-only List view ruled in
 * docs/specs/features/18-immutability.md.
 */
object VectorCodec {
    const val MAGIC: String = "BRG1"

    fun encode(records: List<GlyphMetrics>, width: FloatWidth = FloatWidth.F64): ByteArray {
        val writer = BinaryWriter()
        writer.writeAscii(width.magic)
        writer.writeU32(records.size)
        for (index in records.indices) {
            val record = records[index]
            writer.writeU32(record.codePoint)
            writeFloat(writer, record.advanceEm, width)
            writeFloat(writer, record.bounds.xMin, width)
            writeFloat(writer, record.bounds.yMin, width)
            writeFloat(writer, record.bounds.xMax, width)
            writeFloat(writer, record.bounds.yMax, width)
        }
        return writer.finish()
    }

    fun byteLength(recordCount: Int, width: FloatWidth = FloatWidth.F64): Int {
        return 8 + recordCount * width.recordByteLength
    }

    fun decode(bytes: ByteArray): List<GlyphMetrics> {
        val reader = BinaryReader(bytes)
        val magic = reader.readAscii(4)
        val width = FloatWidth.ofMagic(magic) ?: throw VectorException.BadMagic
        val count = reader.readU32()
        if (count < 0) {
            throw VectorException.CountOverflow
        }
        val records = Array(count) {
            val codePoint = reader.readU32()
            val advanceEm = readFloat(reader, width)
            val xMin = readFloat(reader, width)
            val yMin = readFloat(reader, width)
            val xMax = readFloat(reader, width)
            val yMax = readFloat(reader, width)
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
        }
        if (reader.remaining() != 0) {
            throw VectorException.TrailingBytes(reader.remaining())
        }
        return records.asList()
    }

    private fun writeFloat(writer: BinaryWriter, value: Double, width: FloatWidth) {
        when (width) {
            FloatWidth.F64 -> writer.writeF64(value)
            FloatWidth.F32 -> writer.writeF32(value)
            FloatWidth.F16 -> writer.writeF16(value)
        }
    }

    private fun readFloat(reader: BinaryReader, width: FloatWidth): Double {
        return when (width) {
            FloatWidth.F64 -> reader.readF64()
            FloatWidth.F32 -> reader.readF32()
            FloatWidth.F16 -> reader.readF16()
        }
    }
}
