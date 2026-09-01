package boring

/**
 * IEEE 754 binary16 conversions over plain Int arithmetic (binary spec 05).
 * Both directions operate on bit patterns, so the same rounding runs on every
 * tree that consumes these bytes. f32ToF16Bits rounds with
 * round-to-nearest-even, flushes magnitude overflow to infinity, and quiets
 * NaN inputs.
 */
object Fp16 {
    /**
     * Widens binary16 bits to binary32 bits. Subnormal inputs normalize into
     * the binary32 normal range; infinity and NaN pass through with the NaN
     * kept quiet.
     */
    fun f16ToF32Bits(h16: Int): Int {
        val sign = (h16 ushr 15) and 1
        val exp5 = (h16 ushr 10) and 0x1F
        val mant10 = h16 and 0x3FF
        if (exp5 == 0) {
            if (mant10 == 0) {
                return sign shl 31
            }
            // A subnormal binary16 is mant10 * 2^-24; shifting the mantissa
            // into the implicit-bit position recovers the normal exponent.
            var mant = mant10
            var shift = 0
            while (mant and 0x400 == 0) {
                mant = mant shl 1
                shift += 1
            }
            return (sign shl 31) or ((113 - shift) shl 23) or ((mant and 0x3FF) shl 13)
        }
        if (exp5 == 0x1F) {
            if (mant10 == 0) {
                return (sign shl 31) or 0x7F800000
            }
            return (sign shl 31) or 0x7FC00000 or ((mant10 and 0x3FF) shl 13)
        }
        return (sign shl 31) or ((exp5 - 15 + 127) shl 23) or (mant10 shl 13)
    }

    /**
     * Rounds binary32 bits to binary16 bits with round-to-nearest-even.
     * Magnitude at or above 2^16 rounds to infinity (the boundary 65520 is
     * the tie between 65504 and 65536 and rounds up); NaN inputs keep a
     * quiet mantissa.
     */
    fun f32ToF16Bits(b32: Int): Int {
        val sign = b32 ushr 31
        val exp8 = (b32 ushr 23) and 0xFF
        val mant23 = b32 and 0x7FFFFF
        if (exp8 == 0xFF) {
            if (mant23 == 0) {
                return (sign shl 15) or 0x7C00
            }
            return (sign shl 15) or 0x7E00 or (mant23 ushr 13)
        }
        // Every binary32 subnormal lies far below half of the smallest
        // binary16 subnormal, so it rounds to a signed zero.
        if (exp8 == 0) {
            return sign shl 15
        }
        val exp5 = exp8 - 127 + 15
        if (exp5 >= 31) {
            return (sign shl 15) or 0x7C00
        }
        if (exp5 > 0) {
            var sig11 = roundShift(mant23 or 0x800000, 13)
            if (sig11 == 0x800) {
                if (exp5 + 1 >= 31) {
                    return (sign shl 15) or 0x7C00
                }
                return (sign shl 15) or ((exp5 + 1) shl 10)
            }
            return (sign shl 15) or (exp5 shl 10) or (sig11 and 0x3FF)
        }
        // Subnormal binary16 target: h is the 24-bit significand shifted into
        // the 10-bit subnormal scale, at least 14 places below the window.
        val shift = 14 - exp5
        if (shift > 24) {
            return sign shl 15
        }
        val h = roundShift(mant23 or 0x800000, shift)
        // Rounding past the largest subnormal produces the smallest normal
        // binary16, 2^-14, whose bit pattern is an exponent of one.
        if (h == 0x400) {
            return (sign shl 15) or 0x0400
        }
        return (sign shl 15) or h
    }

    /**
     * Shifts a 24-bit significand right and rounds to nearest with ties to
     * even. shift stays within [13, 24] for every caller above.
     */
    private fun roundShift(value: Int, shift: Int): Int {
        val base = value ushr shift
        val rest = value and ((1 shl shift) - 1)
        val half = 1 shl (shift - 1)
        if (rest > half || (rest == half && (base and 1) == 1)) {
            return base + 1
        }
        return base
    }
}
