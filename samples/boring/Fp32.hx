/**
 * IEEE 754 binary32 bit edges for the wire float widths of binary spec 05.
 * The conversions are plain Int arithmetic over the binary64 bit parts that
 * haxe.io.FPHelper already exposes, so every target runs identical rounding
 * code. On the f32 module-real configuration of feature spec 23 the FPHelper calls
 * widen losslessly before the integer math, so the same source narrows the
 * module real to binary32 bits there as well.
 */

package boring;

class Fp32 {
    /**
        Rounds the module real to binary32 bits with round-to-nearest-even.
        NaN keeps the quiet bit plus the top payload bits of the source;
        magnitude overflow rounds to infinity.
    **/
    public static function toBits(value:Float):Int {
        final d = haxe.io.FPHelper.doubleToI64(value);
        return f64HalvesToF32Bits(d.low, d.high);
    }

    /**
        Widens binary32 bits to the module real. Every binary32 value is
        exactly representable in binary64, so the widening never rounds.
    **/
    public static function fromBits(bits:Int):Float {
        final sign = bits >>> 31;
        final exp8 = (bits >>> 23) & 0xFF;
        final mant23 = bits & 0x7FFFFF;
        if (exp8 == 0xFF) {
            // Infinity passes through; NaN keeps the quiet bit and payload.
            final high = (sign << 31) | 0x7FF00000 | (mant23 == 0 ? 0 : 0x80000 | (mant23 >>> 3));
            final low = (mant23 & 7) << 29;
            return haxe.io.FPHelper.i64ToDouble(low, high);
        }
        if (exp8 == 0) {
            // Subnormal binary32: zero stays zero, otherwise normalize the
            // leading bit into the binary64 exponent.
            if (mant23 == 0) {
                return haxe.io.FPHelper.i64ToDouble(0, sign << 31);
            }
            var mant = mant23;
            var shift = 0;
            while (mant & 0x800000 == 0) {
                mant <<= 1;
                shift += 1;
            }
            final frac = mant & 0x7FFFFF;
            final high = (sign << 31) | ((897 - shift) << 20) | (frac >>> 3);
            final low = (frac & 7) << 29;
            return haxe.io.FPHelper.i64ToDouble(low, high);
        }
        final high = (sign << 31) | ((exp8 + 896) << 20) | (mant23 >>> 3);
        final low = (mant23 & 7) << 29;
        return haxe.io.FPHelper.i64ToDouble(low, high);
    }

    /**
        Converts raw binary64 bit parts to binary32 bits with round-to-nearest-
        even. Exposed so tests can drive exact bit patterns; VectorCodec
        reaches it through toBits.
    **/
    public static function f64HalvesToF32Bits(low:Int, high:Int):Int {
        final sign = high >>> 31;
        final exp11 = (high >>> 20) & 0x7FF;
        if (exp11 == 0x7FF) {
            // Infinity passes through; NaN keeps the quiet bit plus the top
            // payload bits of the source.
            if ((high & 0xFFFFF) == 0 && low == 0) {
                return (sign << 31) | 0x7F800000;
            }
            return (sign << 31) | 0x7F800000 | 0x400000 | ((high >>> 10) & 0x3FF);
        }
        // Every binary64 subnormal lies far below half of the smallest
        // binary32 subnormal, so it rounds to a signed zero.
        if (exp11 == 0) {
            return sign << 31;
        }
        final mantHigh = high & 0xFFFFF;
        var sig24 = 0x800000 | (mantHigh << 3) | (low >>> 29);
        final dropped = low & 0x1FFFFFFF;
        final half = 0x10000000;
        if (dropped > half || (dropped == half && (sig24 & 1) == 1)) {
            sig24 += 1;
        }
        // e2 is the biased exponent after a rounding carry; the binary32
        // exponent field is e2 - 896, and every threshold comparison stays
        // on e2 so no intermediate goes negative on unsigned targets.
        var e2 = exp11;
        if (sig24 == 0x1000000) {
            sig24 = 0x800000;
            e2 += 1;
        }
        if (e2 >= 1151) {
            return (sign << 31) | 0x7F800000;
        }
        if (e2 >= 897) {
            return (sign << 31) | ((e2 - 896) << 23) | (sig24 & 0x7FFFFF);
        }
        return (sign << 31) | subnormalTarget(mantHigh, low, 896 - e2);
    }

    /**
        Rounds a 53-bit significand (implicit bit set) into the 23-bit
        subnormal binary32 mantissa. k is the number of extra binary places the
        value lies below the normal exponent range; the 53-bit field splits
        into the top 23 bits and the low 30 bits of the low half.
    **/
    static function subnormalTarget(mantHigh:Int, low:Int, k:Int):Int {
        if (k >= 24) {
            return 0;
        }
        final top = (0x100000 | mantHigh) << 2 | (low >>> 30);
        final rest = low & 0x3FFFFFFF;
        final halfRest = 0x20000000;
        var h:Int = k == 0 ? top : (top >>> k);
        if (k == 0) {
            if (rest > halfRest || (rest == halfRest && (h & 1) == 1)) {
                h += 1;
            }
        } else {
            final r = top & ((1 << k) - 1);
            final halfR = 1 << (k - 1);
            // With k >= 1 the low-half remainder sits entirely below the
            // dropped-bit granularity: any nonzero rest breaks a half tie
            // upward, and rest == 0 is the only exact tie.
            if (r > halfR || (r == halfR && rest > 0) || (r == halfR && rest == 0 && (h & 1) == 1)) {
                h += 1;
            }
        }
        // Rounding past the largest subnormal produces the smallest normal,
        // whose bit pattern is an exponent of one with a zero mantissa.
        if (h == 0x800000) {
            return 0x00800000;
        }
        return h;
    }
}
