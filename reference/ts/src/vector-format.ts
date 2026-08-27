/**
 * Shared vector format: 4 ASCII magic bytes, one u32 record count, then one
 * 44-byte record per glyph metric (u32 codePoint, five f64 values). The same
 * bytes are produced and consumed by the Haxe, TypeScript, and Rust suites.
 */

import { BinaryReader, BinaryWriter } from "./codec.ts";
import { GlyphMetricsRecord } from "./records.ts";
import { VectorException } from "./vector-error.ts";

export const VECTOR_MAGIC = "BRG1";
export const RECORD_BYTE_LENGTH = 44;
const HEADER_BYTE_LENGTH = 8;
const F64_COUNT_PER_RECORD = 5;

export function encodeVector(records: readonly GlyphMetricsRecord[]): Uint8Array {
  const writer = new BinaryWriter();
  writer.writeAscii(VECTOR_MAGIC);
  const count = records.length;
  writer.writeU32(count);
  for (let i = 0; i < count; i += 1) {
    const record = records[i]!;
    writer.writeU32(record.codePoint);
    writer.writeF64(record.advanceEm);
    writer.writeF64(record.bounds.xMin);
    writer.writeF64(record.bounds.yMin);
    writer.writeF64(record.bounds.xMax);
    writer.writeF64(record.bounds.yMax);
  }
  return writer.finish();
}

export function decodeVector(bytes: Uint8Array): readonly GlyphMetricsRecord[] {
  const reader = new BinaryReader(bytes);
  const magic = reader.readAscii(VECTOR_MAGIC.length);
  if (magic !== VECTOR_MAGIC) {
    throw new VectorException({ kind: "BadMagic" });
  }
  const count = reader.readU32();
  if (count > 0x7fffffff) {
    throw new VectorException({ kind: "CountOverflow" });
  }
  const records: GlyphMetricsRecord[] = new Array<GlyphMetricsRecord>(count);
  for (let i = 0; i < count; i += 1) {
    const codePoint = reader.readU32();
    const advanceEm = reader.readF64();
    const xMin = reader.readF64();
    const yMin = reader.readF64();
    const xMax = reader.readF64();
    const yMax = reader.readF64();
    // DecodeBoundaryFreeze per docs/specs/features/18-immutability.md.
    const bounds = Object.freeze({ xMin, yMin, xMax, yMax });
    records[i] = Object.freeze({ codePoint, advanceEm, bounds });
  }
  if (reader.remaining() !== 0) {
    throw new VectorException({ kind: "TrailingBytes", remaining: reader.remaining() });
  }
  return Object.freeze(records);
}

export function vectorByteLength(recordCount: number): number {
  return HEADER_BYTE_LENGTH + recordCount * (4 + F64_COUNT_PER_RECORD * 8);
}
