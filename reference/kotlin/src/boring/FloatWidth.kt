package boring

/**
 * Block float width of a vector block (binary spec 05). The width is a
 * property of the encoded bytes, declared by the magic, and stays independent
 * of the module real width that feature spec 23 selects at compile time.
 */
enum class FloatWidth(val magic: String, val recordByteLength: Int) {
    F64("BRG1", 4 + 5 * 8),
    F32("BRG2", 4 + 5 * 4),
    F16("BRG3", 4 + 5 * 2);

    companion object {
        /**
         * Unknown magics answer null, which VectorCodec.decode reports as
         * BadMagic; a reader built before a width existed rejects the block
         * when the magic is unknown.
         */
        fun ofMagic(magic: String): FloatWidth? {
            for (width in entries) {
                if (width.magic == magic) {
                    return width
                }
            }
            return null
        }
    }
}
