/**
 * Shared vector format per binary specs 01 and 05: a 4-byte magic that
 * declares the block float width (BRG1 f64, BRG2 f32, BRG3 f16), one u32
 * record count, then one fixed-width record per glyph metric (u32 codePoint
 * plus five floats at the block width). The same bytes are produced and
 * consumed by the Haxe, Kotlin, and Rust suites.
 */

import { BinaryReader, BinaryWriter } from "./codec.ts";
import { GlyphMetricsRecord } from "./records.ts";
import { VectorException } from "./vector-error.ts";

export type FloatWidth = "F64" | "F32" | "F16";

export const VECTOR_MAGIC = "BRG1";
export const VECTOR_MAGIC_F32 = "BRG2";
export const VECTOR_MAGIC_F16 = "BRG3";
export const RECORD_BYTE_LENGTH = 44;
const HEADER_BYTE_LENGTH = 8;
const F64_COUNT_PER_RECORD = 5;

export function magicOf(width: FloatWidth): string {
  if (width === "F64") return VECTOR_MAGIC;
  if (width === "F32") return VECTOR_MAGIC_F32;
  return VECTOR_MAGIC_F16;
}

/**
 * Unknown magics answer null, which decodeVector reports as BadMagic; a
 * reader built before a width existed rejects the block explicitly instead
 * of misreading its records.
 */
export function widthOfMagic(magic: string): FloatWidth | null {
  if (magic === VECTOR_MAGIC) return "F64";
  if (magic === VECTOR_MAGIC_F32) return "F32";
  if (magic === VECTOR_MAGIC_F16) return "F16";
  return null;
}

function writeFloat(writer: BinaryWriter, value: number, width: FloatWidth): void {
  if (width === "F64") {
    writer.writeF64(value);
  } else if (width === "F32") {
    writer.writeF32(value);
  } else {
    writer.writeF16(value);
  }
}

function readFloat(reader: BinaryReader, width: FloatWidth): number {
  if (width === "F64") return reader.readF64();
  if (width === "F32") return reader.readF32();
  return reader.readF16();
}

export function encodeVector(
  records: readonly GlyphMetricsRecord[],
  width: FloatWidth = "F64",
): Uint8Array {
  const writer = new BinaryWriter();
  writer.writeAscii(magicOf(width));
  const count = records.length;
  writer.writeU32(count);
  for (let i = 0; i < count; i += 1) {
    const record = records[i]!;
    writer.writeU32(record.codePoint);
    writeFloat(writer, record.advanceEm, width);
    writeFloat(writer, record.bounds.xMin, width);
    writeFloat(writer, record.bounds.yMin, width);
    writeFloat(writer, record.bounds.xMax, width);
    writeFloat(writer, record.bounds.yMax, width);
  }
  return writer.finish();
}

export function decodeVector(bytes: Uint8Array): readonly GlyphMetricsRecord[] {
  const reader = new BinaryReader(bytes);
  const width = widthOfMagic(reader.readAscii(4));
  if (width === null) {
    throw new VectorException({ kind: "BadMagic" });
  }
  const count = reader.readU32();
  if (count > 0x7fffffff) {
    throw new VectorException({ kind: "CountOverflow" });
  }
  const records: GlyphMetricsRecord[] = new Array<GlyphMetricsRecord>(count);
  for (let i = 0; i < count; i += 1) {
    const codePoint = reader.readU32();
    const advanceEm = readFloat(reader, width);
    const xMin = readFloat(reader, width);
    const yMin = readFloat(reader, width);
    const xMax = readFloat(reader, width);
    const yMax = readFloat(reader, width);
    // DecodeBoundaryFreeze per docs/specs/features/18-immutability.md.
    const bounds = Object.freeze({ xMin, yMin, xMax, yMax });
    records[i] = Object.freeze({ codePoint, advanceEm, bounds });
  }
  if (reader.remaining() !== 0) {
    throw new VectorException({ kind: "TrailingBytes", remaining: reader.remaining() });
  }
  return Object.freeze(records);
}

export function recordByteLength(width: FloatWidth): number {
  if (width === "F64") return 4 + F64_COUNT_PER_RECORD * 8;
  if (width === "F32") return 4 + F64_COUNT_PER_RECORD * 4;
  return 4 + F64_COUNT_PER_RECORD * 2;
}

export function vectorByteLength(recordCount: number, width: FloatWidth = "F64"): number {
  return HEADER_BYTE_LENGTH + recordCount * recordByteLength(width);
}
