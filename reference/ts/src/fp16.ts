/**
 * IEEE 754 binary16 conversions over plain integer arithmetic (binary spec
 * 05). Both directions operate on bit patterns so every tree computes the
 * same rounding. f32ToF16Bits rounds with round-to-nearest-even, flushes
 * magnitude overflow to infinity, and quiets NaN inputs.
 */

export function f16ToF32Bits(h16: number): number {
  const sign = (h16 >>> 15) & 1;
  const exp5 = (h16 >>> 10) & 0x1f;
  const mant10 = h16 & 0x3ff;
  if (exp5 === 0) {
    if (mant10 === 0) {
      return sign << 31;
    }
    // A subnormal binary16 is mant10 * 2^-24; shifting the mantissa into
    // the implicit-bit position recovers the normal exponent.
    let mant = mant10;
    let shift = 0;
    while ((mant & 0x400) === 0) {
      mant <<= 1;
      shift += 1;
    }
    return (sign << 31) | ((113 - shift) << 23) | ((mant & 0x3ff) << 13);
  }
  if (exp5 === 0x1f) {
    if (mant10 === 0) {
      return (sign << 31) | 0x7f800000;
    }
    return (sign << 31) | 0x7fc00000 | ((mant10 & 0x3ff) << 13);
  }
  return (sign << 31) | ((exp5 - 15 + 127) << 23) | (mant10 << 13);
}

export function f32ToF16Bits(b32: number): number {
  const sign = b32 >>> 31;
  const exp8 = (b32 >>> 23) & 0xff;
  const mant23 = b32 & 0x7fffff;
  if (exp8 === 0xff) {
    if (mant23 === 0) {
      return (sign << 15) | 0x7c00;
    }
    return (sign << 15) | 0x7e00 | (mant23 >>> 13);
  }
  // Every binary32 subnormal lies far below half of the smallest binary16
  // subnormal, so it rounds to a signed zero.
  if (exp8 === 0) {
    return sign << 15;
  }
  let exp5 = exp8 - 127 + 15;
  if (exp5 >= 31) {
    return (sign << 15) | 0x7c00;
  }
  if (exp5 > 0) {
    let sig11 = roundShift(mant23 | 0x800000, 13);
    if (sig11 === 0x800) {
      exp5 += 1;
      if (exp5 >= 31) {
        return (sign << 15) | 0x7c00;
      }
      sig11 = 0x400;
    }
    return (sign << 15) | (exp5 << 10) | (sig11 & 0x3ff);
  }
  // Subnormal binary16 target: h is the 24-bit significand shifted into
  // the 10-bit subnormal scale, at least 14 places below the window.
  const shift = 14 - exp5;
  if (shift > 24) {
    return sign << 15;
  }
  const h = roundShift(mant23 | 0x800000, shift);
  // Rounding past the largest subnormal lands on the smallest normal
  // binary16, 2^-14, whose bit pattern is an exponent of one.
  if (h === 0x400) {
    return (sign << 15) | 0x0400;
  }
  return (sign << 15) | h;
}

function roundShift(value: number, shift: number): number {
  const base = value >>> shift;
  const rest = value & ((1 << shift) - 1);
  const half = 1 << (shift - 1);
  if (rest > half || (rest === half && (base & 1) === 1)) {
    return base + 1;
  }
  return base;
}
