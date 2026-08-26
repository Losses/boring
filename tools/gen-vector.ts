/**
 * Regenerates tests/vectors/roundtrip.bin from tests/vectors/roundtrip.json
 * and prints the canonical hex form. The committed binary is fixed evidence:
 * tests in every language read it, and this tool runs only when the format
 * itself changes.
 */

import { encodeVector, toVectorFile } from "@boring/codec";

const REPO_ROOT = import.meta.dir + "/..";
const JSON_PATH = REPO_ROOT + "/tests/vectors/roundtrip.json";
const BIN_PATH = REPO_ROOT + "/tests/vectors/roundtrip.bin";

async function main(): Promise<void> {
  const text = await Bun.file(JSON_PATH).text();
  const parsed: unknown = JSON.parse(text);
  const vector = toVectorFile(parsed);
  const bytes = encodeVector(vector.records);
  await Bun.write(BIN_PATH, bytes);
  const hex = Buffer.from(bytes).toString("hex");
  console.log(`wrote ${BIN_PATH} (${bytes.byteLength} bytes)`);
  console.log(`hex: ${hex}`);
}

await main();
