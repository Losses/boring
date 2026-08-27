package boring

object VectorCodec {
    fun encode(records: List<GlyphMetrics>): ByteArray {
        val writer = BinaryWriter()
        writer.writeAscii("BRG1")
        writer.writeU32(records.size)
        for (index in 0 until records.size) {
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

    fun decode(bytes: ByteArray): List<GlyphMetrics> {
        val reader = BinaryReader(bytes)
        val magic = reader.readAscii("BRG1".length)
        if ((magic != "BRG1")) {
            throw VectorException.BadMagic
        }
        val count = reader.readU32()
        val records = Array(count) { index ->
            val codePoint = reader.readU32()
            val advanceEm = reader.readF64()
            val xMin = reader.readF64()
            val yMin = reader.readF64()
            val xMax = reader.readF64()
            val yMax = reader.readF64()
            GlyphMetrics(
        codePoint = codePoint,
        advanceEm = advanceEm,
        bounds = BoundsEm(
        xMin = xMin,
        yMin = yMin,
        xMax = xMax,
        yMax = yMax
    )
    )
        }
        if ((reader.remaining() != 0)) {
            throw VectorException.TrailingBytes(reader.remaining())
        }
        return records.asList()
    }
}
