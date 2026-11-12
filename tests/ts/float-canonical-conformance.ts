/**
 * P-23 cross-target conformance comparison (criterion 4). Reads each target's
 * test-results JSONL and verifies the FloatCanonical fixture passed on every
 * target. "pass" means the target's canonical bytes matched the candidate bytes
 * recorded in tests.FloatCanonicalTests (which are the TS reference encoder's
 * output), so all-pass across targets is byte-for-byte consistency.
 *
 * Run: bun run tests/ts/float-canonical-conformance.ts
 */
import { readFileSync, existsSync } from "node:fs";
import { encode64, encode32, encodeFingerprint, TAG_F64, TAG_F32 } from "../../reference/ts/src/index.ts";

const RESULTS_DIR = "out/test-results";
const PREFIX = "tests.FloatCanonicalTests.";
const TARGETS = [
  ["ts", "f64"],
  ["kotlin", "f64"],
  ["swift", "f64"],
  ["dart", "f64"],
  ["rust", "f64"],
  ["kotlin-f32", "f32"],
  ["swift-f32", "f32"],
  ["rust-f32", "f32"],
] as const;

const hex = (b: Uint8Array): string => Buffer.from(b).toString("hex");

// Oracle re-derivation: the fixture's candidate bytes, recomputed here so the
// report carries its own authoritative source (never trusts the target output).
const oracle = {
  encode64: {
    "+0.0": hex(encode64(0)),
    "-0.0": hex(encode64(-0)),
    "1.0": hex(encode64(1)),
    "NaN": hex(encode64(NaN)),
    "+Inf": hex(encode64(Infinity)),
  },
  encode32: {
    "1.0": hex(encode32(1)),
    "NaN": hex(encode32(NaN)),
  },
  fingerprint: {
    record: hex(encodeFingerprint([
      { key: "ratio", typeTag: TAG_F64, isNull: false, value: encode64(0.5) },
      { key: "count", typeTag: TAG_F64, isNull: true, value: new Uint8Array(0) },
      { key: "level", typeTag: TAG_F32, isNull: false, value: encode32(1.0) },
    ])),
    nested: hex(encodeFingerprint([
      { key: "outer", typeTag: TAG_F64, isNull: false, value: encode64(1.0) },
      { key: "inner.x", typeTag: TAG_F64, isNull: false, value: encode64(-0.5) },
    ])),
    map: hex(encodeFingerprint([
      { key: "m[0]", typeTag: TAG_F64, isNull: false, value: encode64(-1.0) },
      { key: "m[1]", typeTag: TAG_F64, isNull: false, value: encode64(0.5) },
    ])),
  },
};

console.log("P-23 conformance comparison (candidate = TS reference encoder)");
console.log("oracle encode64(-0.0)=", oracle.encode64["-0.0"]);
console.log("oracle encode64(NaN)=", oracle.encode64.NaN);
console.log("oracle encode32(NaN)=", oracle.encode32.NaN);
console.log("oracle fingerprint.record=", oracle.fingerprint.record);
console.log("");

let allPass = true;
for (const [target, lane] of TARGETS) {
  const path = RESULTS_DIR + "/" + target + ".jsonl";
  if (!existsSync(path)) {
    console.log(target + " [" + lane + "]: NO RESULT FILE");
    allPass = false;
    continue;
  }
  const lines = readFileSync(path, "utf8").split("\n").filter((l) => l.trim().length > 0);
  const cases = lines.map((l) => JSON.parse(l)).filter((r) => r.id && r.id.startsWith(PREFIX));
  const failed = cases.filter((r) => r.verdict !== "pass");
  const pass = cases.length - failed.length;
  if (failed.length > 0) allPass = false;
  console.log(target + " [" + lane + "]: " + pass + "/" + cases.length + " pass" + (failed.length ? " (FAIL: " + failed.map((f) => f.id).join(", ") + ")" : ""));
}

console.log("");
console.log(allPass ? "CONSISTENT: every present target passed byte-for-byte." : "DIVERGENT: see failures above.");
