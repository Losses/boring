import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { resolve } from "node:path";

/**
 * Collects the per-character units-hoisting guard of the Rust target.
 *
 * The assertions live in run.sh, which generates the fixture and checks the
 * emitted `u_string::units(` counts per root function, then checks that the
 * interval walk reads through the hoisted vector instead of rescanning the
 * source. This wrapper exists so `bun test tests/` picks the guard up: a
 * directory holding only run.sh and an .hxml is collected by nothing
 * (tests/fixture-reachability.test.ts counts exactly that class of fixture).
 *
 * ORDERING MATTERS HERE, for the reason recorded in the sibling wrapper
 * tests/haxe/rust-resident-dataclass/resident-dataclass.test.ts: check the exit
 * status FIRST. A missing toolchain exits 0 by construction in run.sh, so a
 * non-zero status can never legitimately mean "skipped", and consulting the
 * skip phrase before the status would let a real failure that merely mentions
 * it read as a pass.
 */

const REPO_ROOT = resolve(import.meta.dir, "../../..");
const RUNNER = resolve(import.meta.dir, "run.sh");

describe("rust per-character units hoisting", () => {
  test("a per-char walk materializes its receiver's UTF-16 vector once", () => {
    const result = spawnSync("bash", [RUNNER], {
      cwd: REPO_ROOT,
      encoding: "utf8",
      maxBuffer: 64 * 1024 * 1024,
    });
    const output = `${result.stdout ?? ""}${result.stderr ?? ""}`;

    // 1. Status first: the environment-not-reached path exits 0 by construction.
    expect(
      result.status,
      `run.sh exited ${result.status}; a non-zero status is always a failure\n${output}`,
    ).toBe(0);

    // 2. On success, report a missing toolchain as a stage rather than as green.
    if (output.includes("environment-not-reached")) {
      console.log(output.trim());
      return;
    }

    expect(output).toContain("PASS");
  }, 600_000);
});
