import { describe, expect, test } from "bun:test";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";

/**
 * The Rust reference tree is a workspace member, so `cargo test` compiles and
 * tests it -- but nothing regenerates it before that happens.
 *
 * That combination already cost us once: commit 304ed70c changed
 * tests/rust/vector_gen.rs to use the UString API and the data-class
 * comparator, while reference/rust/gen on disk was still the older output.
 * `cargo test` then failed with four errors that look like compiler breakage
 * and are really staleness:
 *
 *   error[E0432]: unresolved imports `boring_codec_gen::BufferHolder`,
 *                 `boring_codec_gen::BytesFrame`
 *   error[E0432]: unresolved import `boring_codec_gen::boring::data_class_string_compare`
 *
 * The tree is git-ignored build output (0 tracked files), so no `git status`
 * ever shows it as dirty, and `bun test tests/` never touches it. The drift is
 * invisible until someone happens to run `cargo test` and misreads the result
 * as a compiler defect.
 *
 * What this file asserts is deliberately narrow: that the on-disk reference
 * tree is CONSISTENT WITH ITS SOURCE for the symbols the Rust test suite
 * imports. It does not regenerate anything (that needs haxe and takes minutes);
 * it fails loudly so the fix is a known command, `haxe examples/rust.hxml`,
 * rather than a debugging session.
 *
 * This is a consistency check, not a substitute for `cargo test`: it reads the
 * tree the same way the consumer does, and it is cheap enough to run in the
 * collected suite.
 */

// This file sits directly in tests/, so the repository root is one level up.
// (Files under tests/<fixture>/ need "../.."; getting this wrong is silent --
// an earlier version of this check returned early on a nonexistent path and
// passed on a tree that was in fact stale. Hence the assertion below.)
const REPO_ROOT = resolve(import.meta.dir, "..");
const GEN = join(REPO_ROOT, "reference", "rust", "gen");
const SAMPLE = join(REPO_ROOT, "samples", "boring", "DataClassStringCompare.hx");

/**
 * The root must actually be the repository, or every check below degenerates
 * into "path does not exist, return quietly" -- which is exactly how an
 * earlier version of this file passed on a stale tree. Asserting this first
 * means a wrong relative depth fails loudly instead of silently.
 */
function assertRepoRootLooksRight(): void {
  expect(
    existsSync(join(REPO_ROOT, "package.json")),
    `REPO_ROOT resolved to ${REPO_ROOT}, which has no package.json: the relative ` +
      "depth in this file is wrong, so every path check below would pass vacuously",
  ).toBe(true);
  expect(
    existsSync(join(REPO_ROOT, "examples", "rust.hxml")),
    `REPO_ROOT ${REPO_ROOT} has no examples/rust.hxml`,
  ).toBe(true);
}

/**
 * Whether the reference tree has been generated at all. Absence is a setup
 * state, not a regression -- but it must still be asserted against, never
 * returned from silently, because a silent return is indistinguishable from a
 * pass (see assertRepoRootLooksRight).
 */
function assertReferenceTreePresent(): boolean {
  if (!existsSync(GEN)) {
    console.log(
      "reference/rust/gen is absent: run `haxe examples/rust.hxml` before cargo test",
    );
    return false;
  }
  expect(existsSync(join(GEN, "boring", "mod.rs"))).toBe(true);
  return true;
}

/**
 * Modules `tests/rust/vector_gen.rs` imports and the module file each one must
 * resolve to inside the generated tree.
 *
 * These are spelled out rather than derived from the symbol names, because the
 * names do not follow a rule: `BufferHolder`/`BytesFrame` are modules
 * (boring/buffer_holder.rs, boring/bytes_frame.rs) reached through
 * `pub use boring::*` in lib.rs, while `BoundsEm`/`VectorError` are TYPES
 * declared inside other modules (boring/glyph_metrics.rs,
 * boring/vector_exception.rs). A snake_case guess over the imported symbols
 * reports the types as missing modules and fails on a perfectly fresh tree --
 * which an earlier version of this file did.
 *
 * So the check keys on what the consumer actually needs to resolve, and the
 * list is updated when the consumer's imports change.
 */
const REQUIRED_MODULE_FILES: ReadonlyArray<readonly [string, string]> = [
  ["boring::data_class_string_compare", join("boring", "data_class_string_compare.rs")],
  ["BufferHolder", join("boring", "buffer_holder.rs")],
  ["BytesFrame", join("boring", "bytes_frame.rs")],
];

/** Modules that must be declared in boring/mod.rs for the above to resolve. */
const REQUIRED_DECLARATIONS: ReadonlyArray<readonly [string, string]> = [
  ["boring::data_class_string_compare", "data_class_string_compare"],
  ["BufferHolder", "buffer_holder"],
  ["BytesFrame", "bytes_frame"],
];

describe("rust reference tree consistency", () => {
  test("the resolved repository root is the repository", () => {
    assertRepoRootLooksRight();
  });

  test("the reference tree exists and is populated", () => {
    assertRepoRootLooksRight();
    if (!assertReferenceTreePresent()) return;
    expect(readdirSync(join(GEN, "runtime")).length).toBeGreaterThan(0);
  });

  test("every module the Rust test suite imports resolves in the generated tree", () => {
    assertRepoRootLooksRight();
    if (!assertReferenceTreePresent()) return;

    // The consumer must still import these; if its imports change, this list
    // (not a guess) is what gets updated, so assert the consumer still says so.
    const consumer = readFileSync(join(REPO_ROOT, "tests", "rust", "vector_gen.rs"), "utf8");

    const boringMod = readFileSync(join(GEN, "boring", "mod.rs"), "utf8");
    const declared = new Set(
      [...boringMod.matchAll(/^pub mod\s+([\w]+)\s*;/gm)].map((m) => m[1]),
    );

    const problems: string[] = [];
    for (const [symbol, rel] of REQUIRED_MODULE_FILES) {
      const simple = symbol.includes("::") ? symbol.split("::").pop()! : symbol;
      if (!consumer.includes(simple)) continue; // consumer dropped it; nothing to check

      if (!existsSync(join(GEN, rel))) {
        problems.push(`${symbol}: missing generated file ${rel}`);
      }
    }
    for (const [symbol, moduleName] of REQUIRED_DECLARATIONS) {
      const simple = symbol.includes("::") ? symbol.split("::").pop()! : symbol;
      if (!consumer.includes(simple)) continue;

      if (!declared.has(moduleName)) {
        problems.push(`${symbol}: boring/mod.rs does not declare "pub mod ${moduleName};"`);
      }
    }

    expect(
      problems,
      `reference/rust/gen is stale relative to tests/rust/vector_gen.rs: ${problems.join("; ")}. ` +
        "Regenerate with `haxe examples/rust.hxml` (the tree is git-ignored, so nothing else will do it).",
    ).toEqual([]);
  });

  test("the data-class comparator module the Rust suite imports is present", () => {
    assertRepoRootLooksRight();
    if (!assertReferenceTreePresent()) return;

    // The specific regression above: 304ed70c made vector_gen.rs import this
    // module, and the generated tree must therefore have it. Its source is
    // samples/boring/DataClassStringCompare.hx.
    expect(
      existsSync(SAMPLE),
      "samples/boring/DataClassStringCompare.hx is the source this check keys on",
    ).toBe(true);

    const generated = join(GEN, "boring", "data_class_string_compare.rs");
    expect(
      existsSync(generated),
      "reference/rust/gen/boring/data_class_string_compare.rs must exist because " +
        "tests/rust/vector_gen.rs imports it; regenerate with `haxe examples/rust.hxml`",
    ).toBe(true);
  });
});
