import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

/**
 * Collected regression guard for the four-target whole-set resident typing
 * (t-muotn6ov-g9mo; the mechanism merged into the base as 756c0c8a / 8756188a).
 *
 * The property under test is the one the fixture's `run.sh` gate measures
 * natively: a consumer whose entry lists NO `runtime.*` root must still pull
 * every resident runtime module into the generated tree. Each target's
 * compiler enforces that by force-typing the whole `RuntimeResidents` set
 * inside `use()`; if that loop is removed, the extern-usage-driven emission
 * gate never types the residents and the tree silently loses them.
 *
 * `run.sh` is the heavy native gate (five toolchains, ~15 min). This test locks
 * the same property at the generation level, where it is cheap, toolchain-light
 * and directly attributable to the compiler:
 *
 *   1. closure — generate variant (a) (no `runtime.*` root) with the real
 *      compiler; every resident the consumer reaches through the std extern
 *      face must be emitted;
 *   2. reverse — generate the same input with the four whole-set loops removed,
 *      via a classpath shadow (`-cp` AFTER the hxml, which wins the module
 *      lookup) that never touches the real sources; the resident must vanish.
 *
 * Step 2 is the reverse-discrimination half: it proves the loop is
 * load-bearing, not merely present. Pre-fix baselines and the native readings
 * are in REPORT.md §2 and §7; the mutation negative control stays in run.sh.
 */

const REPO_ROOT = resolve(import.meta.dir, "../../..");
const FIXTURE_REL = "tests/haxe/resident-consumer-closure";

const TARGETS = ["rust", "swift", "kotlin", "dart"] as const;
type Target = (typeof TARGETS)[number];

/**
 * Resident leaves a no-`runtime.*`-root consumer must still pull in. Rust and
 * Kotlin drop the module file entirely when it is never typed; Swift and Dart
 * keep their single resident file but lose the module body inside it, so both
 * the file set and the `Graphemes` symbol are asserted.
 */
const RESIDENT_CLOSURE: Record<Target, readonly string[]> = {
  rust: [
    "runtime/graphemes.rs",
    "runtime/grapheme_walk.rs",
    "runtime/sorted_table.rs",
    "runtime/string_tools.rs",
    "runtime/u_string.rs",
  ],
  swift: ["Runtime.swift"],
  kotlin: [
    "runtime/Graphemes.kt",
    "runtime/GraphemeWalk.kt",
    "runtime/SortedTable.kt",
    "runtime/UString.kt",
    "runtime/StringTools.kt",
  ],
  dart: ["lib/runtime.dart"],
};

/** The type the whole-set loop is the only thing forcing on every target. */
const CLOSURE_SYMBOL = "Graphemes";

function runHaxe(args: readonly string[]): { status: number | null; output: string } {
  const r = spawnSync("haxe", [...args], { cwd: REPO_ROOT, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  return { status: r.status, output: `${r.stdout ?? ""}${r.stderr ?? ""}` };
}

/**
 * The whole-set force-typing block, exactly as each target's `use()` writes it.
 * A missing block is itself a failure: this is the only collected guard that
 * reads it, so a refactor that drops the loop must fail here rather than
 * silently stop testing anything.
 */
function withoutWholeSetLoops(target: Target): string {
  const source = readFileSync(
    join(REPO_ROOT, "packages", "compiler", "reflaxe", target, `${target}compiler`, "Compiler.hx"),
    "utf8",
  );
  const block = [
    "            for (resident in RuntimeResidents.MODULES)",
    "                if (Context.getType(resident) == null)",
    `                    throw '${target} resident module not typed: ' + resident;`,
    "            for (resident in RuntimeResidents.TEST_MODULES)",
    "                if (Context.getType(resident) == null)",
    `                    throw '${target} resident module not typed: ' + resident;`,
  ].join("\n");
  if (!source.includes(block)) {
    throw new Error(
      `${target}: whole-set force-typing block not found in ${target}compiler/Compiler.hx — the reverse-discrimination half of this guard no longer tests the mechanism`,
    );
  }
  return source.replace(block, "            // [resident-closure reverse probe] whole-set forced typing removed");
}

function residentText(root: string, rel: string): string {
  const p = join(root, rel);
  return existsSync(p) ? readFileSync(p, "utf8") : "";
}

describe("resident closure with no runtime.* root", () => {
  test("every target emits its residents from a root-only consumer, and removing the whole-set typing re-breaks it", () => {
    if (spawnSync("haxe", ["--version"], { encoding: "utf8" }).status !== 0) {
      console.log("environment-not-reached: haxe is not on PATH; resident-closure guard skipped");
      return;
    }

    const scratch = mkdtempSync(join(tmpdir(), "resident-closure-"));
    try {
      // A shadow class path holding only the four stripped Compiler.hx. Passing
      // it AFTER the hxml wins Haxe's module lookup, so the real sources are
      // never edited.
      const shadow = join(scratch, "shadow");
      for (const target of TARGETS) {
        const dir = join(shadow, `${target}compiler`);
        mkdirSync(dir, { recursive: true });
        writeFileSync(join(dir, "Compiler.hx"), withoutWholeSetLoops(target));
      }
      const closureRoot = join(scratch, "closure");
      const revertRoot = join(scratch, "revert");
      const hxml = (target: Target): string => join(REPO_ROOT, FIXTURE_REL, "gen", `${target}-a.hxml`);

      // 1. Closure: variant (a) (no runtime.* root) with the real compiler.
      for (const target of TARGETS) {
        const r = runHaxe([hxml(target), "-D", `${target}-output=${join(closureRoot, `${target}-a`)}`]);
        expect(r.status, `closure generation (a) for ${target} exited ${r.status}\n${r.output}`).toBe(0);
      }
      // 2. Reverse: the same input with the whole-set loops shadowed out.
      for (const target of TARGETS) {
        const r = runHaxe([hxml(target), "-cp", shadow, "-D", `${target}-output=${join(revertRoot, `${target}-a`)}`]);
        expect(r.status, `reverse generation (a) for ${target} exited ${r.status}\n${r.output}`).toBe(0);
      }

      for (const target of TARGETS) {
        const closureTree = join(closureRoot, `${target}-a`);
        const revertTree = join(revertRoot, `${target}-a`);

        for (const rel of RESIDENT_CLOSURE[target]) {
          expect(
            existsSync(join(closureTree, rel)),
            `${target}: resident ${rel} missing from the (a) tree — a root-only consumer did not pull the whole resident set (REPORT.md §7)`,
          ).toBe(true);
        }
        const closureText = RESIDENT_CLOSURE[target].map((rel) => residentText(closureTree, rel)).join("\n");
        expect(closureText, `${target}: no emitted resident carries ${CLOSURE_SYMBOL}`).toContain(CLOSURE_SYMBOL);

        const revertText = RESIDENT_CLOSURE[target].map((rel) => residentText(revertTree, rel)).join("\n");
        expect(
          revertText,
          `${target}: ${CLOSURE_SYMBOL} survived removing the whole-set forced typing — the loop is not load-bearing`,
        ).not.toContain(CLOSURE_SYMBOL);
      }
    } finally {
      rmSync(scratch, { recursive: true, force: true });
    }
  }, 900_000);
});
