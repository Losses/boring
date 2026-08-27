package boring

object VectorSort {
    fun byCodePoint(records: MutableList<GlyphMetrics>): MutableList<GlyphMetrics> {
        for (write in 1 until records.size) {
            val record = records[write]
            val key = record.codePoint
            var read = write - 1
            while ((read >= 0 && records[read].codePoint > key)) {
                records[read + 1] = records[read]
                read -= 1
            }
            records[read + 1] = record
        }
        return records
    }
}
