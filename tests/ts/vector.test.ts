import { describe, expect, test } from "bun:test";
import { VectorException, decodeVector, encodeVector, toVectorFile } from "@boring/codec";

const VECTOR_JSON = import.meta.dir + "/../vectors/roundtrip.json";
const VECTOR_BIN = import.meta.dir + "/../vectors/roundtrip.bin";

async function loadExpected() {
  const text = await Bun.file(VECTOR_JSON).text();
  const parsed: unknown = JSON.parse(text);
  return toVectorFile(parsed);
}

describe("committed cross-language vector", () => {
  test("decoded binary matches the JSON description", async () => {
    const expected = await loadExpected();
    const bytes = new Uint8Array(await Bun.file(VECTOR_BIN).arrayBuffer());
    expect(decodeVector(bytes)).toEqual(expected.records);
  });

  test("re-encoding the decoded records reproduces the committed bytes", async () => {
    const expected = await loadExpected();
    const bytes = new Uint8Array(await Bun.file(VECTOR_BIN).arrayBuffer());
    expect(encodeVector(expected.records)).toEqual(bytes);
  });
});

describe("record count domain", () => {
  // The decodable count domain is [0, 2^31) per docs/specs/binary/01-binary-record-layout.md.
  type CountCase = [label: string, countBytes: readonly number[]];
  const countCases: ReadonlyArray<CountCase> = [
    ["0xFFFFFFFF", [0xff, 0xff, 0xff, 0xff]],
    ["0x80000000", [0x80, 0x00, 0x00, 0x00]],
  ];

  for(const [label, countBytes] of countCases) {
    test(`a count of ${label} throws the CountOverflow variant`, () => {
      const bytes = new Uint8Array([0x42, 0x52, 0x47, 0x31, ...countBytes]);
      try {
        decodeVector(bytes);
        expect.unreachable();
      } catch(error) {
        expect(error).toBeInstanceOf(VectorException);
        expect((error as VectorException).error.kind).toBe("CountOverflow");
      }
    });
  }
});
