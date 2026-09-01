package boring

import java.util.ArrayList

/**
 * Sequential big-endian writer over a growable byte buffer. The u32 domain of
 * this repository is code points and record counts, both far below 2^31, so
 * signed Int carries every value used here without sign concerns.
 */
class BinaryWriter {
    private val buffer = ArrayList<Byte>()

    fun writeU16(value: Int) {
        buffer.add(((value ushr 8) and 0xFF).toByte())
        buffer.add((value and 0xFF).toByte())
    }

    fun writeU32(value: Int) {
        buffer.add(((value ushr 24) and 0xFF).toByte())
        buffer.add(((value ushr 16) and 0xFF).toByte())
        buffer.add(((value ushr 8) and 0xFF).toByte())
        buffer.add((value and 0xFF).toByte())
    }

    fun writeF64(value: Double) {
        val bits = value.toRawBits()
        // The Long parts carry raw two's-complement bits; writing them as
        // two u32 words keeps the byte order identical on every target.
        val high = (bits ushr 32).toInt()
        val low = bits.toInt()
        writeU32(high)
        writeU32(low)
    }

    /**
     * Rounds the module real to binary32 bits with round-to-nearest-even for
     * WireF32Be (binary spec 05); toFloat performs the rounding and
     * toRawBits reads the result bits.
     */
    fun writeF32(value: Double) {
        writeU32(value.toFloat().toRawBits())
    }

    /**
     * Rounds the module real to binary16 bits for WireF16Be (binary spec 05)
     * through the binary32 edge, matching the integer rounding of Fp16.
     */
    fun writeF16(value: Double) {
        writeU16(Fp16.f32ToF16Bits(value.toFloat().toRawBits()))
    }

    fun writeAscii(value: String) {
        for (index in 0 until value.length) {
            buffer.add((value[index].code and 0xFF).toByte())
        }
    }

    fun finish(): ByteArray {
        val bytes = ByteArray(buffer.size)
        for (i in 0 until buffer.size) {
            bytes[i] = buffer[i]
        }
        return bytes
    }
}
