import type { GlyphMetricsRecord } from "./records.ts";

// Sort runtime per docs/specs/features/17-sorting.md. Codec code calls
// vectorSortByCodePoint; comparator sorting anywhere else is a structure
// violation. The comparator below is the one sanctioned closure in the
// runtime.

// Code points below 2^21 with indices below 2^32 pack exactly into one
// float64: key * 2^32 + index < 2^53. A Float64Array sort with no
// comparator runs the engine's native numeric sort, and the index in the
// low bits breaks ties in input order, which is stability.
const PACK_BOUND = 2097152;
const PACK_SCALE = 4294967296;
const INSERTION_THRESHOLD = 32;

export function vectorSortByCodePoint(records: GlyphMetricsRecord[]): GlyphMetricsRecord[] {
  const count = records.length;
  if (count <= INSERTION_THRESHOLD) {
    insertionSortByCodePoint(records, count);
    return records;
  }
  const packed = new Float64Array(count);
  let packable = true;
  for (let i = 0; i < count; i += 1) {
    const key = records[i]!.codePoint;
    if (key >= PACK_BOUND) {
      packable = false;
      break;
    }
    packed[i] = key * PACK_SCALE + i;
  }
  if (packable) {
    packed.sort();
    const source = records.slice();
    for (let i = 0; i < count; i += 1) {
      records[i] = source[packed[i]! % PACK_SCALE]!;
    }
    return records;
  }
  return decoratedSortByCodePoint(records, count);
}

function insertionSortByCodePoint(records: GlyphMetricsRecord[], count: number): void {
  for (let write = 1; write < count; write += 1) {
    const record = records[write]!;
    const key = record.codePoint;
    let read = write - 1;
    while (read >= 0 && records[read]!.codePoint > key) {
      records[read + 1] = records[read]!;
      read -= 1;
    }
    records[read + 1] = record;
  }
}

function decoratedSortByCodePoint(
  records: GlyphMetricsRecord[],
  count: number,
): GlyphMetricsRecord[] {
  const indices = new Array<number>(count);
  for (let i = 0; i < count; i += 1) {
    indices[i] = i;
  }
  indices.sort((a, b) => records[a]!.codePoint - records[b]!.codePoint || a - b);
  const source = records.slice();
  for (let i = 0; i < count; i += 1) {
    records[i] = source[indices[i]!]!;
  }
  return records;
}
