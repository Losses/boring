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
 * Measured 2026-10-01. May move deliberately in either direction; must not
 * drift while nobody is looking.
 *
 * **34, corrected from 36.** The count dropped because the guard's criterion
 * was wrong, not because three fixtures were wired in during this session: it
 * looked for a `.test.ts` only *inside* the fixture directory, so a fixture
 * whose test lives under `tests/<target>/` was indistinguishable from an
 * unwatched one. Three were in that state all along --
 *
 *   dc-promoted-eval, swift-package-shell-emit, kotlin-smartcast-tfield
 *
 * -- each driven by a collected test elsewhere (swift-package-shell-emit by
 * tests/ts/package-shell.test.ts:388, kotlin-smartcast-tfield by
 * tests/kotlin/smartcast-tfield.test.ts:74). `hasCollectedTest` now also
 * accepts a collected test that names the fixture's path, and the constant
 * carries the corrected number.
 *
 * The two earlier bumps (35 -> 36, and 36 -> 37 when kotlin-smartcast-tfield
 * landed) were partly this blind spot rather than real drift: the 36->37 step
 * counted kotlin-smartcast-tfield as unwatched when its test was already
 * driving it.
 *
 * This is the same failure mode the guard exists to catch, one level up: an
 * observation domain narrower than the property it claims (L6 in
 * LAYERED-VERIFICATION.md).
 *
 * Still open and deliberately NOT absorbed by this correction: the
 * `kotlin-mutable-chain-probe` leftover that caused the 35 -> 36 step. It has
 * no test anywhere and remains genuinely unwatched -- see the tracking task.
 */
const RECORDED_UNCOLLECTED = 34;

interface Fixture {
  readonly name: string;
  readonly hasRunner: boolean;
  readonly hasCollectedTest: boolean;
}

/**
 * Every collected test file under tests/. Discovery mirrors the suite's own
 * collection (`bun test tests/`), and is asserted non-empty below so a broken
 * walk cannot silently make the second half of `hasCollectedTest` decide
 * nothing.
 */
function collectedTestFiles(): string[] {
  const out: string[] = [];
  const walk = (dir: string): void => {
    let entries: string[];
    try {
      entries = readdirSync(dir);
    } catch {
      return;
    }
    for (const e of entries) {
      const p = join(dir, e);
      if (e.endsWith(".test.ts")) out.push(p);
      else if (!e.includes(".")) walk(p);
    }
  };
  walk(join(REPO_ROOT, "tests"));
  return out;
}

const collectedTests = collectedTestFiles();

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
      // A fixture is collected if a test IN the directory exists, OR if any
      // collected test anywhere under tests/ names this directory's path. The
      // second half matters: `tests/haxe/kotlin-smartcast-tfield/` has its test
      // at `tests/kotlin/smartcast-tfield.test.ts`, which drives that
      // directory's `kotlin.hxml` -- so the old in-directory-only reading
      // counted it as unwatched when it is in fact wired in. That is this
      // guard's own failure mode one level up: an observation domain narrower
      // than the property it claims (the same shape as L6 in
      // LAYERED-VERIFICATION.md).
      hasCollectedTest:
        entries.some((f) => f.endsWith(".test.ts")) ||
        collectedTests.some((t) => readFileSync(t, "utf8").includes(`tests/haxe/${name}/`)),
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
