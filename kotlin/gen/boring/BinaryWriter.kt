package boring

class BinaryWriter {
    private val buffer: BytesBuffer = BytesBuffer()

    fun writeU16(value: Int) {
        this.buffer.addByte(((((value) ushr (8))) and (255)))
        this.buffer.addByte(((value) and (255)))
    }

    fun writeU32(value: Int) {
        this.buffer.addByte(((((value) ushr (24))) and (255)))
        this.buffer.addByte(((((value) ushr (16))) and (255)))
        this.buffer.addByte(((((value) ushr (8))) and (255)))
        this.buffer.addByte(((value) and (255)))
    }

    fun writeF64(value: Double) {
        val bits = FPHelper.doubleToI64(value)
        this.writeU32(bits.high)
        this.writeU32(bits.low)
    }

    fun writeAscii(value: String) {
        for (index in 0 until value.length) {
            this.buffer.addByte(((value[index].code) and (255)))
        }
    }

    fun finish(): ByteArray {
        return this.buffer.getBytes()
    }
}
