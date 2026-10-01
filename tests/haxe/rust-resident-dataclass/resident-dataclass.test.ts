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
 *
 * ORDERING MATTERS HERE. An earlier version of this wrapper tested the output
 * for "environment-not-reached" BEFORE looking at the exit status, and matched
 * the whole combined stdout+stderr. A real failure whose message merely
 * contained that phrase -- e.g. run.sh echoing its generation log on failure --
 * was then reported as 1 pass / rc=0. Reproduced. So:
 *
 *   1. A non-zero exit is a failure, full stop. Environment-not-reached is a
 *      SUCCESS exit by construction (run.sh exits 0 on a missing toolchain),
 *      so a non-zero status can never legitimately mean "skipped".
 *   2. Only then is the skip phrase consulted, and only on a zero exit.
 */

const REPO_ROOT = resolve(import.meta.dir, "../../..");
const RUNNER = resolve(import.meta.dir, "run.sh");

describe("rust resident emission from a data class", () => {
  test("a single @:dataClass root emits the resident its comparator imports", () => {
    const result = spawnSync("bash", [RUNNER], {
      cwd: REPO_ROOT,
      encoding: "utf8",
      maxBuffer: 64 * 1024 * 1024,
    });
    const output = `${result.stdout ?? ""}${result.stderr ?? ""}`;

    // 1. Status first. A missing toolchain exits 0 (see run.sh), so a non-zero
    //    status is always a real failure and must never be treated as a skip.
    expect(
      result.status,
      `run.sh exited ${result.status}; a non-zero status is always a failure ` +
        `(the environment-not-reached path exits 0 by construction)\n${output}`,
    ).toBe(0);

    // 2. On success, a missing toolchain is reported as a stage rather than a
    //    silent green, so the reader knows what was actually proven.
    if (output.includes("environment-not-reached")) {
      console.log(output.trim());
      return;
    }

    expect(output).toContain("PASS");
  }, 600_000);
});
