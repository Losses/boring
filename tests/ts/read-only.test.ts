import { describe, expect, test } from "bun:test";
import {
  type GlyphMetricsRecord,
  decodeVector,
  encodeVector,
  toVectorFile,
} from "@boring/codec";

// features/18: decoded data is frozen at the boundary (DecodeBoundaryFreeze)
// and mutation fails at runtime. The type layer already rejects these
// mutations; the mutable view below checks the runtime layer independently,
// so a consumer that bypasses the types still cannot mutate decoded data.

type MutableCodePointRecord = { codePoint: number };

const RECORD: GlyphMetricsRecord = {
  codePoint: 65,
  advanceEm: 0.5,
  bounds: { xMin: 0.03125, yMin: -0.21875, xMax: 0.46875, yMax: 0.03125 },
};

function decodeSample(): readonly GlyphMetricsRecord[] {
  return decodeVector(encodeVector([RECORD]));
}

describe("read-only decoded data", () => {
  test("decoded records and their array are frozen", () => {
    const decoded = decodeSample();
    expect(Object.isFrozen(decoded)).toBe(true);
    expect(Object.isFrozen(decoded[0])).toBe(true);
    expect(Object.isFrozen(decoded[0]!.bounds)).toBe(true);
  });

  test("slot assignment through a mutable view throws TypeError", () => {
    const mutableView = decodeSample() as GlyphMetricsRecord[];
    expect(() => {
      mutableView[0] = RECORD;
    }).toThrow(TypeError);
  });

  test("array growth through a mutable view throws TypeError", () => {
    const mutableView = decodeSample() as GlyphMetricsRecord[];
    expect(() => {
      mutableView.push(RECORD);
    }).toThrow(TypeError);
  });

  test("record field assignment through a mutable view throws TypeError", () => {
    const first = decodeSample()[0]! as MutableCodePointRecord;
    expect(() => {
      first.codePoint = 66;
    }).toThrow(TypeError);
  });

  test("the JSON boundary output is frozen the same way", () => {
    const file = toVectorFile({ description: "sample", records: [RECORD] });
    expect(Object.isFrozen(file)).toBe(true);
    expect(Object.isFrozen(file.records)).toBe(true);
    const mutableRecords = file.records as GlyphMetricsRecord[];
    expect(() => {
      mutableRecords.push(RECORD);
    }).toThrow(TypeError);
    const firstRecord = file.records[0]! as MutableCodePointRecord;
    expect(() => {
      firstRecord.codePoint = 66;
    }).toThrow(TypeError);
  });
});
