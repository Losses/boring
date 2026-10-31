import { describe, expect, test } from "bun:test";
import {
  canonicalFloatBits,
  canonicalFloatBytes,
  F64_QUIET_NAN_TOKEN,
  F32_QUIET_NAN_TOKEN,
} from "@boring/codec";

/** Builds a binary64 number from its exact IEEE bit pattern, so a test can
 * address NaN payloads and the quiet/signaling flag that a literal NaN hides. */
function f64FromBits(bits: bigint): number {
  const view = new DataView(new ArrayBuffer(8));
  view.setUint32(0, Number((bits >> 32n) & 0xffffffffn), false);
  view.setUint32(4, Number(bits & 0xffffffffn), false);
  return view.getFloat64(0, false);
}

/** Builds a binary32 number from its exact IEEE bit pattern. */
function f32FromBits(bits: number): number {
  const view = new DataView(new ArrayBuffer(4));
  view.setUint32(0, bits, false);
  return view.getFloat32(0, false);
}

const f64Hex = (value: number): string =>
  Buffer.from(canonicalFloatBytes(value, "F64")).toString("hex");
const f32Hex = (value: number): string =>
  Buffer.from(canonicalFloatBytes(value, "F32")).toString("hex");

describe("canonical float encoding (P-13)", () => {
  test("both signed zeroes encode as zero bits at f64", () => {
    expect(f64Hex(0)).toBe("0000000000000000");
    expect(f64Hex(-0)).toBe("0000000000000000");
    expect(canonicalFloatBits(0, "F64")).toBe(0n);
    expect(canonicalFloatBits(-0, "F64")).toBe(0n);
  });

  test("both signed zeroes encode as zero bits at f32", () => {
    expect(f32Hex(0)).toBe("00000000");
    expect(f32Hex(-0)).toBe("00000000");
    expect(canonicalFloatBits(0, "F32")).toBe(0n);
    expect(canonicalFloatBits(-0, "F32")).toBe(0n);
  });

  test("nonzero finite values encode their IEEE bits", () => {
    expect(f64Hex(1)).toBe("3ff0000000000000");
    expect(f64Hex(-1)).toBe("bff0000000000000");
    expect(f64Hex(0.5)).toBe("3fe0000000000000");
    expect(f64Hex(-0.21875)).toBe("bfcc000000000000");
    expect(f32Hex(1)).toBe("3f800000");
    expect(f32Hex(-1)).toBe("bf800000");
    expect(f32Hex(0.5)).toBe("3f000000");
  });

  test("Infinity retains its IEEE bits", () => {
    expect(f64Hex(Infinity)).toBe("7ff0000000000000");
    expect(f64Hex(-Infinity)).toBe("fff0000000000000");
    expect(f32Hex(Infinity)).toBe("7f800000");
    expect(f32Hex(-Infinity)).toBe("ff800000");
  });

  test("every NaN encodes the fixed quiet-NaN token regardless of payload or sign", () => {
    const nanPayloads: readonly bigint[] = [
      0x7ff8000000000000n, // canonical quiet NaN
      0x7ff0000000000001n, // signaling NaN, smallest payload
      0x7ff7ffffffffffffn, // signaling NaN, largest payload (quiet bit clear)
      0xfff8000000000000n, // negative quiet NaN
      0xfff0000000000001n, // negative signaling NaN
    ];
    for (const payload of nanPayloads) {
      const value = f64FromBits(payload);
      expect(Number.isNaN(value)).toBe(true);
      expect(canonicalFloatBits(value, "F64")).toBe(F64_QUIET_NAN_TOKEN);
      expect(f64Hex(value)).toBe("7ff8000000000000");
    }
  });

  test("f32 NaN encodes the f32 quiet-NaN token without widening to f64", () => {
    const signaling = f32FromBits(0x7f800001);
    const negativeQuiet = f32FromBits(0xffc00000);
    expect(Number.isNaN(signaling)).toBe(true);
    expect(Number.isNaN(negativeQuiet)).toBe(true);
    expect(canonicalFloatBits(signaling, "F32")).toBe(F32_QUIET_NAN_TOKEN);
    expect(f32Hex(signaling)).toBe("7fc00000");
    expect(f32Hex(negativeQuiet)).toBe("7fc00000");
  });

  test("f64 token keeps the full 64-bit width (never truncates to f32)", () => {
    expect(canonicalFloatBytes(NaN, "F64").byteLength).toBe(8);
    expect(canonicalFloatBytes(NaN, "F32").byteLength).toBe(4);
  });
});
