/**
 * P-13 canonical float encoding (Astra ruling), the language-independent
 * reference encoder behind cross-target float hashing and fingerprinting.
 *
 * Canonical bits at each declared width:
 *   - ±0.0 and -0.0 both encode as zero bits (0x0000000000000000 / 0x00000000);
 *   - a nonzero non-NaN value encodes its IEEE-754 bits at the declared width;
 *   - every NaN encodes the fixed quiet-NaN token for that width
 *     (0x7ff8000000000000 for binary64, 0x7fc00000 for binary32) -- the payload
 *     and the quiet/signaling flag are never retained;
 *   - Infinity retains its IEEE bits (0x7ff0000000000000 / 0xfff0000000000000
 *     for binary64, 0x7f800000 / 0xff800000 for binary32).
 *
 * Byte order is big-endian everywhere. A binary32 value is encoded from its
 * binary32 bit pattern directly and never widened to binary64 first, so an f32
 * NaN payload cannot leak f64 bits into the stream.
 *
 * The canonical-bit primitive is shared by two distinct consumers:
 *   - the runtime hash helper (HaxeFloatHash), which feeds the canonical bits
 *     into each target's own hash combiner -- feed = big-endian bytes of the
 *     canonical bits, width = 64 or 32; each target declares its own seed;
 *   - the protocol fingerprint encoder, which writes the same canonical bytes
 *     big-endian into the fingerprint stream -- feed = big-endian bytes,
 *     width = 64 or 32, no seed (the digest is applied to the finished stream).
 *
 * Equality is unchanged by canonicalization: NaN remains unequal to every
 * value including itself, and the two signed zeroes remain equal. Canonical
 * encoding only makes the hash/fingerprint agree with that equality.
 */

export type CanonicalFloatWidth = "F64" | "F32";

export const F64_BYTE_WIDTH = 8;
export const F32_BYTE_WIDTH = 4;

export const F64_QUIET_NAN_TOKEN: bigint = 0x7ff8000000000000n;
export const F32_QUIET_NAN_TOKEN: bigint = 0x7fc00000n;

const SCRATCH = new DataView(new ArrayBuffer(F64_BYTE_WIDTH));

/** Raw IEEE binary64 bits of value, big-endian assembled into a bigint. */
function f64Bits(value: number): bigint {
  SCRATCH.setFloat64(0, value, false);
  const high = SCRATCH.getUint32(0, false);
  const low = SCRATCH.getUint32(4, false);
  return (BigInt(high) << 32n) | BigInt(low);
}

/** Raw IEEE binary32 bits of value, big-endian assembled into an unsigned 32-bit integer. */
function f32Bits(value: number): number {
  SCRATCH.setFloat32(0, value, false);
  return SCRATCH.getUint32(0, false);
}

/**
 * The canonical float bit token for value at the declared width, as a
 * nonnegative bigint. value is a JavaScript number carrying the declared
 * precision (a binary32 value already rounded to f32 before this call).
 */
export function canonicalFloatBits(value: number, width: CanonicalFloatWidth): bigint {
  if (width === "F32") {
    if (value === 0) return 0n; // both +0.0 and -0.0
    if (Number.isNaN(value)) return F32_QUIET_NAN_TOKEN;
    return BigInt(f32Bits(value));
  }
  if (value === 0) return 0n; // both +0.0 and -0.0
  if (Number.isNaN(value)) return F64_QUIET_NAN_TOKEN;
  return f64Bits(value);
}

/** The canonical float bytes (big-endian) for value at the declared width. */
export function canonicalFloatBytes(value: number, width: CanonicalFloatWidth): Uint8Array {
  const bits = canonicalFloatBits(value, width);
  const length = width === "F64" ? F64_BYTE_WIDTH : F32_BYTE_WIDTH;
  const out = new Uint8Array(length);
  for (let i = 0; i < length; i += 1) {
    const shift = BigInt((length - 1 - i) * 8);
    out[i] = Number((bits >> shift) & 0xffn);
  }
  return out;
}
