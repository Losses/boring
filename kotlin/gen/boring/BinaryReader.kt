package boring

class BinaryReader(private val bytes: ByteArray) {
    private var offset: Int = 0

    private fun ensureRemaining(length: Int) {
        if ((this.bytes.size - this.offset < length)) {
            throw VectorException.UnexpectedEof
        }
    }

    fun readU16(): Int {
        this.ensureRemaining(2)
        val value = (((((( this.bytes[this.offset].toInt() and 0xFF ))) shl (8))) or ((( this.bytes[this.offset + 1].toInt() and 0xFF ))))
        this.offset += 2
        return value
    }

    fun readU32(): Int {
        this.ensureRemaining(4)
        val value = (((((((((( this.bytes[this.offset].toInt() and 0xFF ))) shl (24))) or ((((( this.bytes[this.offset + 1].toInt() and 0xFF ))) shl (16))))) or ((((( this.bytes[this.offset + 2].toInt() and 0xFF ))) shl (8))))) or ((( this.bytes[this.offset + 3].toInt() and 0xFF ))))
        this.offset += 4
        return value
    }

    fun readF64(): Double {
        val high = this.readU32()
        val low = this.readU32()
        return FPHelper.i64ToDouble(low, high)
    }

    fun readAscii(length: Int): String {
        this.ensureRemaining(length)
        val parts = Array(length) { index ->
            (((( this.bytes[this.offset + index].toInt() and 0xFF ))).toChar()).toString()
        }
        this.offset += length
        return parts.joinToString("")
    }

    fun remaining(): Int {
        return this.bytes.size - this.offset
    }

    fun consumed(): Int {
        return this.offset
    }
}
