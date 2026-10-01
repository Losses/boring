import { describe, expect, test } from "bun:test";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";

/**
 * Fixture reachability audit.
 *
 * A fixture that carries a runner but has no collected test is invisible to CI:
 * it runs only when a human remembers to run it, and nothing goes red when it
 * starts failing. `bun test tests/` collects `*.test.ts`; a directory holding
 * only `run.sh` / `*.hxml` is collected by nothing.
 *
 * Measured 2026-10-01: 35 fixtures under tests/haxe/ are in exactly that state,
 * each with a runner, and several with probes and expected outputs. They are not
 * debris — they are unwatched.
 *
 * This guard does NOT fix them; it makes the count a FACT rather than something
 * rediscovered. The count may go DOWN deliberately (wire a fixture in, lower the
 * constant) or UP deliberately (add a fixture, raise it). It must not drift
 * while nobody is looking — which is the same contract the baseline's failure
 * counts use.
 *
 * What it deliberately does not judge: whether each fixture SHOULD be collected.
 * Some may be superseded by a collected test elsewhere; deciding that is a
 * review question, not a scan's.
 */

const REPO_ROOT = resolve(import.meta.dir, "..");
const HAXE_FIXTURES = join(REPO_ROOT, "tests", "haxe");

/**
 * Measured 2026-10-01. Lower it deliberately when a fixture is wired in.
 *
 * Raised 35 -> 36 the same day, and the raise is the interesting direction:
 * `tests/haxe/kotlin-mutable-chain-probe` was added as a development probe by
 * the Kotlin mutable-chain fix and carries a `kotlin-gen.hxml` with no
 * `*.test.ts`. Its shape was wired in as a collected fixture in the SAME commit
 * series (`tests/haxe/kotlin-var-field-smartcast`, which does have a test), so
 * the probe is most likely a leftover rather than a new coverable fixture.
 * It is recorded here rather than deleted because deleting another seat's probe
 * is their call, and rather than silently raised because a rising count is
 * exactly what this guard exists to surface. Whoever settles it should either
 * wire it in (count falls) or remove it (count falls) -- the count should not
 * stay at 36.
 */
const RECORDED_UNCOLLECTED = 36;

interface Fixture {
  readonly name: string;
  readonly hasRunner: boolean;
  readonly hasCollectedTest: boolean;
}

function fixtures(): Fixture[] {
  if (!existsSync(HAXE_FIXTURES)) return [];
  const out: Fixture[] = [];
  for (const name of readdirSync(HAXE_FIXTURES)) {
    const dir = join(HAXE_FIXTURES, name);
    let entries: string[];
    try {
      entries = readdirSync(dir);
    } catch {
      continue; // not a directory
    }
    out.push({
      name,
      hasRunner: entries.some((f) => f === "run.sh" || f.endsWith(".hxml")),
      hasCollectedTest: entries.some((f) => f.endsWith(".test.ts")),
    });
  }
  return out;
}

describe("fixture reachability", () => {
  test("the fixtures directory is present and discovery works", () => {
    const found = fixtures();
    expect(found.length, `no fixture directories found under ${HAXE_FIXTURES}`).toBeGreaterThan(10);
    expect(
      found.filter((f) => f.hasCollectedTest).length,
      "no fixture has a collected test; either discovery is broken or the suite changed shape",
    ).toBeGreaterThan(0);
  });

  test("the number of runner-bearing uncollected fixtures matches the record", () => {
    const uncollected = fixtures().filter((f) => f.hasRunner && !f.hasCollectedTest);
    const names = uncollected.map((f) => f.name).sort();

    expect(
      names.length,
      `runner-bearing fixtures with no collected test: ${names.length}, recorded ${RECORDED_UNCOLLECTED}.\n` +
        `If this went DOWN, you wired one in — lower RECORDED_UNCOLLECTED deliberately.\n` +
        `If it went UP, a fixture was added unwatched — either wire it in or raise the record.\n` +
        (names.length <= 12 ? `Currently: ${names.join(", ")}` : `First 12: ${names.slice(0, 12).join(", ")}`),
    ).toBe(RECORDED_UNCOLLECTED);
  });
});
