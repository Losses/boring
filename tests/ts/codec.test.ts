import { describe, expect, test } from "bun:test";
import {
  BinaryReader,
  BinaryWriter,
  GlyphMetricsRecord,
  VECTOR_MAGIC,
  VectorException,
  decodeVector,
  encodeVector,
  vectorByteLength,
} from "@boring/codec";

describe("BinaryWriter and BinaryReader", () => {
  test("u16 and u32 round trip in big-endian order", () => {
    const writer = new BinaryWriter();
    writer.writeU16(0x1234);
    writer.writeU32(0x56789abc);
    const bytes = writer.finish();
    expect(bytes.byteLength).toBe(6);
    expect([...bytes]).toEqual([0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc]);
    const reader = new BinaryReader(bytes);
    expect(reader.readU16()).toBe(0x1234);
    expect(reader.readU32()).toBe(0x56789abc);
    expect(reader.remaining()).toBe(0);
  });

  test("f64 round trip preserves the bit pattern", () => {
    const writer = new BinaryWriter();
    writer.writeF64(-0.21875);
    const bytes = writer.finish();
    expect(bytes.byteLength).toBe(8);
    expect([...bytes]).toEqual([0xbf, 0xcc, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);
    const reader = new BinaryReader(bytes);
    expect(reader.readF64()).toBe(-0.21875);
  });

  test("ascii writes one byte per character", () => {
    const writer = new BinaryWriter();
    writer.writeAscii(VECTOR_MAGIC);
    expect([...writer.finish()]).toEqual([0x42, 0x52, 0x47, 0x31]);
  });

  test("buffer grows past the initial capacity", () => {
    const writer = new BinaryWriter();
    for (let i = 0; i < 100; i += 1) {
      writer.writeU32(i);
    }
    const bytes = writer.finish();
    expect(bytes.byteLength).toBe(400);
    const reader = new BinaryReader(bytes);
    for (let i = 0; i < 100; i += 1) {
      expect(reader.readU32()).toBe(i);
    }
  });
});

/** An action whose failure mode is under test. */
type ThrowingAction = () => void;

/** Runs the action and returns the thrown VectorException, or undefined. */
function catchVectorException(action: ThrowingAction): VectorException | undefined {
  try {
    action();
    return undefined;
  } catch (error) {
    return error instanceof VectorException ? error : undefined;
  }
}

describe("vector format", () => {
  test("round trip preserves records and length", () => {
    const records: GlyphMetricsRecord[] = [
      { codePoint: 19969, advanceEm: 1.0, bounds: { xMin: 0.03125, yMin: -0.875, xMax: 0.96875, yMax: 0.03125 } },
    ];
    const bytes = encodeVector(records);
    expect(bytes.byteLength).toBe(vectorByteLength(1));
    expect(decodeVector(bytes)).toEqual(records);
  });

  test("decode rejects a wrong magic with the BadMagic variant", () => {
    const writer = new BinaryWriter();
    writer.writeAscii("XXXX");
    writer.writeU32(0);
    const failure = catchVectorException(() => decodeVector(writer.finish()));
    expect(failure?.error.kind).toBe("BadMagic");
  });

  test("decode rejects trailing bytes with the TrailingBytes variant", () => {
    const records: GlyphMetricsRecord[] = [];
    const bytes = encodeVector(records);
    const padded = new Uint8Array(bytes.byteLength + 1);
    padded.set(bytes, 0);
    const failure = catchVectorException(() => decodeVector(padded));
    expect(failure?.error.kind).toBe("TrailingBytes");
    const variant = failure?.error;
    if (variant?.kind === "TrailingBytes") {
      expect(variant.remaining).toBe(1);
    }
  });

  test("decode rejects a truncated vector with the UnexpectedEof variant", () => {
    const bytes = new Uint8Array([
      0x42, 0x52, 0x47, 0x31, 0x00, 0x00, 0x00, 0x01,
    ]);
    const failure = catchVectorException(() => decodeVector(bytes));
    expect(failure?.error.kind).toBe("UnexpectedEof");
  });
});
