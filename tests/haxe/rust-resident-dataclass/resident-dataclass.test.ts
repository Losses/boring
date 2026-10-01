import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { resolve } from "node:path";

/**
 * Collects the minimal-consumer guard for the Rust resident emission bridge.
 *
 * The assertion lives in run.sh, which generates from a single @:dataClass
 * root and requires the resident the consumer imports to be declared, then
 * compiles the crate. This wrapper exists so `bun test tests/` picks the
 * guard up: `run.sh` beside a `.test.ts` is otherwise never collected.
 *
 * Why a single root is required is documented in run.sh and in PIT-390: over
 * the full corpus the emission gate is a global union, so the bridge's
 * absence is masked and a corpus-level test cannot see it.
 */

const REPO_ROOT = resolve(import.meta.dir, "../..");
const RUNNER = resolve(import.meta.dir, "run.sh");

describe("rust resident emission from a data class", () => {
  test("a single @:dataClass root emits the resident its comparator imports", () => {
    const result = spawnSync("bash", [RUNNER], {
      cwd: REPO_ROOT,
      encoding: "utf8",
      maxBuffer: 64 * 1024 * 1024,
    });
    const output = `${result.stdout ?? ""}${result.stderr ?? ""}`;

    // A missing toolchain is environment-not-reached and is never a failure
    // (house convention): report the stage rather than a bare green.
    if (output.includes("environment-not-reached")) {
      console.log(output.trim());
      return;
    }

    expect(result.status, output).toBe(0);
    expect(output).toContain("PASS");
  }, 600_000);
});
