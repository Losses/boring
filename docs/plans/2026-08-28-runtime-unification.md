# Plan: runtime unification and entry-point split

Date: 2026-08-28. Status: approved for execution.

## Defects

Two defects motivate this plan.

1. The three generator lanes each carry hand-written runtime sources as
   string constants inside the compiler (`TsRuntime.hx` 1083 lines,
   `KotlinRuntime.hx` 884 lines, `RustRuntime.hx` 954 lines). The
   grapheme walk exists in five copies (three runtime strings, the
   stage-one oracle, the generator tool's reference walk); the sorted
   collection family exists in three copies of ten classes. Four-target
   equality is enforced by the jsonl consistency harness after the fact,
   not by construction.
2. The TypeScript runtime is one file whose first lines import
   `node:fs` and `node:path` (the test result writer). Any browser
   import of the runtime package fails at module resolution. Runtime
   code that needs the host file system and runtime code that a web
   page needs are not separated.

A third item is a directive: the Unicode data pipeline moves into a
compile-time macro. The current external script (`tools/gen-grapheme-tables.ts`)
duplicates the boundary walk a fourth time and commits a generated
intermediate file that must be kept in sync with the pinned data.

## Taxonomy

Every runtime member belongs to exactly one of three classes. The
classification is normative: adding a member means placing it in one
class and recording it in the table that `docs/specs/stdlib/06` holds.

- **Compiled runtime-resident modules.** Pure algorithms with no host
  dependency. They exist once as Haxe source and each lane compiles
  them into the runtime package. Members: `Graphemes` (walk, rules,
  table), `UString`, the sorted collection family, the assertion and
  formatting logic of the test helper.
- **Native primitives.** Members whose body is a host capability that
  Haxe cannot express portably. They stay hand-written per target and
  keep only a minimal set of members: byte buffer storage (`BytesBuffer`),
  IEEE-754 bit reinterpretation (`FPHelper`), standard output
  (`Console`), process exit (`Process`).
- **Extern primitives.** Operations lowered natively per lane but
  expressed as ordinary Haxe calls, so pure logic above them compiles.
  Current members: `charCodeAt`, `String.fromCharCode`, string
  concatenation, `.length`. This plan adds `String.substring`.

## Entry points

The runtime package exposes two entry points.

- **General entry** (`@boring/runtime` on TypeScript, package
  `boring.runtime` on Kotlin, the runtime crate root on Rust): holds
  compiled runtime-resident modules and native primitives that run in
  a browser. Contract: no import of a `node:` specifier and no
  reference to a host process API anywhere in the entry. A static
  scan enforces the contract in the ordinary test run.
- **Test entry** (`@boring/runtime/test`, package
  `boring.runtime.test`): holds the test helper's file-writing edge.
  Generated code references it only from generated test code. A web
  page never imports it.

`Process` is a host-capability module. A browser program must never
reference it; a reference would fail at call time through a missing
global, and import time stays clean because the general entry holds no
static host import for it. The
Kotlin and Rust lanes have no import-time execution and keep their
existing single-package layout with the test module as a separate
compilation unit.

## Phases

Each phase leaves `bun run verify` green and is one commit batch.

- **P1 Entry-point split.** Split the TypeScript runtime string into a
  general source with no `node:` imports and a test source that keeps
  `node:fs` and `node:path`; route `std.Test` references to the test
  entry in the TypeScript and Kotlin expression compilers; move the
  Kotlin test shim to package `boring.runtime.test`; amend
  `stdlib/06` with the entry-point contract; add the static
  browser-safety scan to `tests/ts/`.
- **P2 Macro data pipeline.** A `#if macro` module reads the pinned
  Unicode data files from `tools/unicode-data/` with `sys.io.File`,
  merges the ranges, runs the official conformance vectors against the
  shared Haxe walk in the macro interpreter, and defines the table
  module with `Context.defineType`. Nothing generated is committed.
  `-D fetch-unicode=<version>` downloads the four files of that
  release with `haxe.Http` before parsing. A content-hash cache under
  `out/` keeps ordinary rebuilds free of parsing. Delete the external
  generator tool, its shared library, the committed table file, and
  the table-revalidation bun test; the compile-time gate replaces it.
- **P3 `String.substring` lowering.** One rule per lane: TypeScript
  and Kotlin call the platform method; Rust converts UTF-16 unit
  bounds to byte bounds by walking `char_indices`, the conversion the
  `ustring` runtime already contains.
- **P4 Runtime-resident compiled modules; `Graphemes` single
  source.** Each lane's compiler gains a named list of runtime
  resident modules whose compiled output is emitted under the
  `runtime-emit` directory; with `runtime-emit=none` the lanes
  reference them without emitting them, which the import tables
  already do.
  `std.Graphemes` becomes a real Haxe class (walk, rules, table
  through the data-table mechanism that `ScriptEvidenceTable.RANGES`
  uses). Delete the three `GRAPHEMES_SOURCE` strings, the table
  renderer, and the stage-one oracle; the stage-one binding points at
  the compiled module.
- **P5 `UString` single source.** Same treatment. With `substring`
  lowered, the walk needs no runtime string outside the Haxe source.
- **P6 Test helper split.** Assertion logic and formatting become a
  compiled runtime-resident module; the file-writing edge stays in the
  test entry.
- **P7 Sorted collection family single source.** Ten classes per
  target become one Haxe source. The Rust member is already array
  based, so no native structure is lost.

## Invariants

1. `bun run verify` passes after every phase, including the jsonl
   four-target consistency run.
2. The general entry of each emitted runtime contains no `node:`
   specifier (static scan in the test run).
3. The Unicode conformance gate runs on the same walk that ships.
4. Generated business code never imports the test entry.
