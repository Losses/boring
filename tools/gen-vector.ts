/**
 * Regenerates the committed vector binaries from tests/vectors/roundtrip.json
 * and prints each canonical hex form. One JSON record set encodes at all
 * three block float widths of binary spec 05; every value in the set is an
 * exact binary16 value, so the three blocks carry equal values. The
 * committed binaries are fixed evidence: tests in every language read them,
 * and this tool runs only when the format itself changes.
 */

import { encodeVector, toVectorFile, type FloatWidth } from "@boring/codec";

const REPO_ROOT = import.meta.dir + "/..";
const JSON_PATH = REPO_ROOT + "/tests/vectors/roundtrip.json";
const WIDTHS: readonly FloatWidth[] = ["F64", "F32", "F16"];

const FILE_NAMES: Record<FloatWidth, string> = {
  F64: "roundtrip.bin",
  F32: "roundtrip-f32.bin",
  F16: "roundtrip-f16.bin",
};

async function main(): Promise<void> {
  const text = await Bun.file(JSON_PATH).text();
  const parsed: unknown = JSON.parse(text);
  const vector = toVectorFile(parsed);
  for (const width of WIDTHS) {
    const bytes = encodeVector(vector.records, width);
    const path = REPO_ROOT + "/tests/vectors/" + FILE_NAMES[width];
    await Bun.write(path, bytes);
    const hex = Buffer.from(bytes).toString("hex");
    console.log(`wrote ${path} (${bytes.byteLength} bytes)`);
    console.log(`hex: ${hex}`);
  }
}

await main();
