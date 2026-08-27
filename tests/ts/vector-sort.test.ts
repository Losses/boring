import { describe, expect, test } from "bun:test";
import { vectorSortByCodePoint } from "@boring/codec";
import type { GlyphMetricsRecord } from "@boring/codec";

// Corpora and oracles are inline constants shared verbatim with the Haxe
// and Rust sort tests (tests/haxe/Main.hx, tests/rust/vector.rs); the three
// trees must produce identical outputs.

const SORTED_KEYS_SMALL: number[] = [
  0x20, 0x4e00, 0x6371, 0x694a, 0x74fc, 0x76ef, 0x78e2, 0x7ad5, 0x82a1,
];

const SORTED_KEYS: number[] = [
  0x20, 0x3105, 0x3105, 0x4e00, 0x4e00, 0x4e00, 0x4ff3, 0x51e6, 0x53d9, 0x55cc, 0x57bf,
  0x59b2, 0x5ba5, 0x5d98, 0x5f8b, 0x617e, 0x6371, 0x6564, 0x6757, 0x694a, 0x6b3d, 0x6d30,
  0x6f23, 0x7116, 0x7309, 0x74fc, 0x76ef, 0x78e2, 0x7ad5, 0x7cc8, 0x7ebb, 0x80ae, 0x82a1,
  0x8494, 0x8687, 0x887a, 0x8a6d, 0x9fff, 0xff01, 0xff01,
];

const SHUFFLED_KEYS: number[] = [
  0x82a1, 0x78e2, 0x76ef, 0x6371, 0x4e00, 0x0020, 0x7ad5, 0x74fc, 0x694a, 0x6f23, 0x6d30,
  0x8a6d, 0x617e, 0x7ebb, 0x3105, 0x5ba5, 0x6b3d, 0x8687, 0x7116, 0x7cc8, 0xff01, 0x8494,
  0x80ae, 0x59b2, 0x4ff3, 0x4e00, 0x9fff, 0x57bf, 0xff01, 0x6564, 0x53d9, 0x5d98, 0x6757,
  0x3105, 0x5f8b, 0x7309, 0x55cc, 0x51e6, 0x4e00, 0x887a,
];

function buildRecords(keys: readonly number[]): GlyphMetricsRecord[] {
  const count = keys.length;
  const records: GlyphMetricsRecord[] = new Array(count);
  for (let i = 0; i < count; i += 1) {
    // advanceEm marks the input position, so stability assertions can read
    // the original order back from the sorted array.
    records[i] = {
      codePoint: keys[i]!,
      advanceEm: i,
      bounds: { xMin: 0, yMin: 0, xMax: 0, yMax: 0 },
    };
  }
  return records;
}

describe("vectorSortByCodePoint", () => {
  test("sorts a 9-element input array through the insertion tier", () => {
    const records = buildRecords(SHUFFLED_KEYS.slice(0, 9));
    const result = vectorSortByCodePoint(records);
    expect(result).toBe(records);
    expect(result.map((record) => record.codePoint)).toEqual(SORTED_KEYS_SMALL);
  });

  test("sorts a 40-element input array through the packed tier", () => {
    const records = buildRecords(SHUFFLED_KEYS);
    const result = vectorSortByCodePoint(records);
    expect(result.map((record) => record.codePoint)).toEqual(SORTED_KEYS);
  });

  test("equal keys keep input order (stability)", () => {
    const records = buildRecords(SHUFFLED_KEYS);
    vectorSortByCodePoint(records);
    // For every pair of equal keys, the earlier input position comes first.
    const advancesByCodePoint = new Map<number, number[]>();
    for (const record of records) {
      const list = advancesByCodePoint.get(record.codePoint);
      if (list === undefined) {
        advancesByCodePoint.set(record.codePoint, [record.advanceEm]);
      } else {
        list.push(record.advanceEm);
      }
    }
    for (const advances of advancesByCodePoint.values()) {
      const count = advances.length;
      for (let i = 1; i < count; i += 1) {
        expect(advances[i]!).toBeGreaterThan(advances[i - 1]!);
      }
    }
  });

  test("an all-equal input array is returned unchanged element for element", () => {
    const keys = new Array<number>(8).fill(0x4e00);
    const records = buildRecords(keys);
    const result = vectorSortByCodePoint(records);
    expect(result.map((record) => record.advanceEm)).toEqual([0, 1, 2, 3, 4, 5, 6, 7]);
  });
});
