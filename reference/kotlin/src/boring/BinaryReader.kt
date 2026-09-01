package boring

/**
 * Cursor-based big-endian reader over an immutable byte buffer. Assembled u32
 * values keep their two's-complement bits: f64 bit parts feed Double.fromBits as
 * raw bits, and code points (at most 0x10FFFF) are always positive under this
 * representation.
 */
class BinaryReader(private val bytes: ByteArray) {
    private var offset: Int = 0

    private fun ensureRemaining(length: Int) {
        if (bytes.size - offset < length) {
            throw VectorException.UnexpectedEof
        }
    }

    fun readU16(): Int {
        ensureRemaining(2)
        val value = ((bytes[offset].toInt() and 0xFF) shl 8) or
            (bytes[offset + 1].toInt() and 0xFF)
        offset += 2
        return value
    }

    fun readU32(): Int {
        ensureRemaining(4)
        val value = ((bytes[offset].toInt() and 0xFF) shl 24) or
            ((bytes[offset + 1].toInt() and 0xFF) shl 16) or
            ((bytes[offset + 2].toInt() and 0xFF) shl 8) or
            (bytes[offset + 3].toInt() and 0xFF)
        offset += 4
        return value
    }

    fun readF64(): Double {
        val high = readU32().toLong() and 0xFFFFFFFFL
        val low = readU32().toLong() and 0xFFFFFFFFL
        val bits = (high shl 32) or low
        return Double.fromBits(bits)
    }

    /**
     * Reads a WireF32Be field and widens the binary32 value to the f64
     * record field (binary spec 05); widening is exact.
     */
    fun readF32(): Double {
        return Float.fromBits(readU32()).toDouble()
    }

    /**
     * Reads a WireF16Be field, widens the binary16 value through binary32,
     * and answers the f64 record field (binary spec 05).
     */
    fun readF16(): Double {
        return Float.fromBits(Fp16.f16ToF32Bits(readU16())).toDouble()
    }

    fun readAscii(length: Int): String {
        ensureRemaining(length)
        val chars = CharArray(length)
        for (index in 0 until length) {
            chars[index] = (bytes[offset + index].toInt() and 0xFF).toChar()
        }
        offset += length
        return String(chars)
    }

    fun remaining(): Int {
        return bytes.size - offset
    }

    fun consumed(): Int {
        return offset
    }
}
