/**
 * IEEE 754 binary16 conversions over plain Int arithmetic (binary spec 05).
 * Both directions operate on bit patterns, so the same source translates to
 * identical code on every target; no platform holds a native binary16 type
 * across all four trees. f32ToF16Bits rounds with round-to-nearest-even,
 * flushes magnitude overflow to infinity, and quiets NaN inputs.
 */

package boring;

class Fp16 {
    /**
        Widens binary16 bits to binary32 bits. Subnormal inputs normalize into
        the binary32 normal range; infinity and NaN pass through with the NaN
        kept quiet.
    **/
    public static function f16ToF32Bits(h16:Int):Int {
        final sign = (h16 >>> 15) & 1;
        final exp5 = (h16 >>> 10) & 0x1F;
        final mant10 = h16 & 0x3FF;
        if (exp5 == 0) {
            if (mant10 == 0) {
                return sign << 31;
            }
            // A subnormal binary16 is mant10 * 2^-24; shifting the mantissa
            // into the implicit-bit position recovers the normal exponent.
            var mant = mant10;
            var shift = 0;
            while (mant & 0x400 == 0) {
                mant <<= 1;
                shift += 1;
            }
            return (sign << 31) | ((113 - shift) << 23) | ((mant & 0x3FF) << 13);
        }
        if (exp5 == 0x1F) {
            if (mant10 == 0) {
                return (sign << 31) | 0x7F800000;
            }
            return (sign << 31) | 0x7FC00000 | ((mant10 & 0x3FF) << 13);
        }
        // The binary32 exponent field is exp5 + 112; the sum keeps every
        // intermediate non-negative on unsigned targets.
        return (sign << 31) | ((exp5 + 112) << 23) | (mant10 << 13);
    }

    /**
        Rounds binary32 bits to binary16 bits with round-to-nearest-even.
        Magnitude at or above 2^16 rounds to infinity (the boundary 65520 is
        the tie between 65504 and 65536 and rounds up); NaN inputs keep a
        quiet mantissa.
    **/
    public static function f32ToF16Bits(b32:Int):Int {
        final sign = b32 >>> 31;
        final exp8 = (b32 >>> 23) & 0xFF;
        final mant23 = b32 & 0x7FFFFF;
        if (exp8 == 0xFF) {
            if (mant23 == 0) {
                return (sign << 15) | 0x7C00;
            }
            return (sign << 15) | 0x7E00 | (mant23 >>> 13);
        }
        // Every binary32 subnormal lies far below half of the smallest
        // binary16 subnormal, so it rounds to a signed zero.
        if (exp8 == 0) {
            return sign << 15;
        }
        // The binary16 exponent field is exp8 - 112; the domain checks
        // compare on exp8 so no intermediate goes negative on unsigned
        // targets.
        if (exp8 >= 143) {
            return (sign << 15) | 0x7C00;
        }
        if (exp8 >= 113) {
            var exp5 = exp8 - 112;
            var sig11 = roundShift(mant23 | 0x800000, 13);
            if (sig11 == 0x800) {
                exp5 += 1;
                if (exp5 >= 31) {
                    return (sign << 15) | 0x7C00;
                }
                sig11 = 0x400;
            }
            return (sign << 15) | (exp5 << 10) | (sig11 & 0x3FF);
        }
        // Subnormal binary16 target: h is the 24-bit significand shifted into
        // the 10-bit subnormal scale, at least 14 places below the window.
        final shift = 126 - exp8;
        if (shift > 24) {
            return sign << 15;
        }
        final h = roundShift(mant23 | 0x800000, shift);
        // Rounding past the largest subnormal produces the smallest normal
        // binary16, 2^-14, whose bit pattern is an exponent of one.
        if (h == 0x400) {
            return (sign << 15) | 0x0400;
        }
        return (sign << 15) | h;
    }

    /**
        Shifts a 24-bit significand right and rounds to nearest with ties to
        even. shift stays within [13, 24] for every caller above.
    **/
    static function roundShift(value:Int, shift:Int):Int {
        final base = value >>> shift;
        final rest = value & ((1 << shift) - 1);
        final half = 1 << (shift - 1);
        if (rest > half || (rest == half && (base & 1) == 1)) {
            return base + 1;
        }
        return base;
    }
}
