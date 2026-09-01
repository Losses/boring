import { describe, expect, test } from "bun:test";
import {
  FloatWidth,
  VectorException,
  decodeVector,
  encodeVector,
  f16ToF32Bits,
  f32ToF16Bits,
  magicOf,
  recordByteLength,
  toVectorFile,
  vectorByteLength,
  widthOfMagic,
} from "@boring/codec";

const VECTOR_JSON = import.meta.dir + "/../vectors/roundtrip.json";
const VECTOR_BIN_F32 = import.meta.dir + "/../vectors/roundtrip-f32.bin";
const VECTOR_BIN_F16 = import.meta.dir + "/../vectors/roundtrip-f16.bin";

async function loadExpected() {
  const text = await Bun.file(VECTOR_JSON).text();
  const parsed: unknown = JSON.parse(text);
  return toVectorFile(parsed);
}

// Binary spec 05: a block declares its float width in the magic; the f32
// and f16 committed vectors carry the same records as the f64 vector.
describe("block float widths", () => {
  // One committed-binary case per block float width (binary spec 05).
  type WidthCase = [width: FloatWidth, path: string, magic: string, recordBytes: number];
  const widthCases: ReadonlyArray<WidthCase> = [
    ["F32", VECTOR_BIN_F32, "BRG2", 24],
    ["F16", VECTOR_BIN_F16, "BRG3", 14],
  ];

  for (const [width, path, magic, recordBytes] of widthCases) {
    test(`${width} committed binary decodes to the JSON records`, async () => {
      const expected = await loadExpected();
      const bytes = new Uint8Array(await Bun.file(path).arrayBuffer());
      expect(decodeVector(bytes)).toEqual(expected.records);
    });

    test(`${width} re-encoding the decoded records reproduces the committed bytes`, async () => {
      const expected = await loadExpected();
      const bytes = new Uint8Array(await Bun.file(path).arrayBuffer());
      expect(encodeVector(expected.records, width)).toEqual(bytes);
    });

    test(`${width} travels under the ${magic} magic`, async () => {
      const bytes = new Uint8Array(await Bun.file(path).arrayBuffer());
      expect(String.fromCharCode(...bytes.slice(0, 4))).toBe(magic);
      expect(magicOf(width)).toBe(magic);
      expect(widthOfMagic(magic)).toBe(width);
    });

    test(`${width} records occupy ${recordBytes} bytes each`, () => {
      expect(recordByteLength(width)).toBe(recordBytes);
      expect(vectorByteLength(4, width)).toBe(8 + 4 * recordBytes);
    });
  }

  test("unknown width magics are rejected as BadMagic", () => {
    const bytes = new Uint8Array([0x42, 0x52, 0x47, 0x34, 0x00, 0x00, 0x00, 0x00]);
    expect(widthOfMagic("BRG4")).toBeNull();
    try {
      decodeVector(bytes);
      expect.unreachable();
    } catch (error) {
      expect(error).toBeInstanceOf(VectorException);
      expect((error as VectorException).error.kind).toBe("BadMagic");
    }
  });
});

// Bit-exact binary16 edge constants shared with the Haxe, Kotlin, and Rust
// targets; every value was verified against the double-arithmetic oracle.
describe("binary16 edge constants", () => {
  test("binary16 patterns widen to exact binary32 bits", () => {
    // >>> 0 normalizes the signed 32-bit pattern of negative results.
    expect(f16ToF32Bits(0x3800) >>> 0).toBe(0x3f000000);
    expect(f16ToF32Bits(0xb300) >>> 0).toBe(0xbe600000);
    expect(f16ToF32Bits(0x03ff) >>> 0).toBe(0x387fc000);
    expect(f16ToF32Bits(0x0001) >>> 0).toBe(0x33800000);
    expect(f16ToF32Bits(0x7c00) >>> 0).toBe(0x7f800000);
  });

  test("binary32 patterns narrow with round-to-nearest-even", () => {
    expect(f32ToF16Bits(0x3f000000)).toBe(0x3800);
    expect(f32ToF16Bits(0x477f0000)).toBe(0x7bf8);
    expect(f32ToF16Bits(0x477fe000)).toBe(0x7bff);
    expect(f32ToF16Bits(0x477ff800)).toBe(0x7c00);
    expect(f32ToF16Bits(0x33000000)).toBe(0x0000);
    expect(f32ToF16Bits(0x33400000)).toBe(0x0001);
  });
});
