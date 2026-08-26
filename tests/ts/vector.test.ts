import { describe, expect, test } from "bun:test";
import { decodeVector, encodeVector, toVectorFile } from "@boring/codec";

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
