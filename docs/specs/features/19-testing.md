# Feature spec 19: In-source tests, per-target execution, cross-target consistency

## Scope

This specification rules the test workflow of the transpiled sources
end to end: how a consumer declares unit tests in Haxe source, how
each target language emits and runs them in its own native runner, how
every target writes its results to one standard file format, and how a
Haxe-side manager compares all targets against the Kotlin baseline. It
covers the `@:test` declaration metadata, the `std.Test` assertion
API, the canonical failure-message format, the results-file
contract, the test output location of each target, the
`ts-test-runner` define (`node`, `deno`, `bun`), and the consistency
manager.

The per-language suites under `tests/` stay: they pin runner wiring,
fixtures loaded from disk, and error-variant behavior the subset
cannot express yet (see Phasing).

## The two purposes

A consumer of this library writes tests for two purposes, and the
workflow has one stage per purpose:

1. **Logic correctness.** The consumer's Haxe functions must behave
   correctly. Tests are declared once in Haxe source; every target
   compiles them into that language's own test arrangement and runs
   them with that language's own runner. Each target then writes its
   results to the standard results file (below).
2. **Cross-language consistency.** The same tests must produce the
   same outcomes everywhere. A Haxe-side manager reads every target's
   results file and checks each against the Kotlin baseline; Kotlin
   is the behavior baseline (user requirement E1). The manager is the
   stage-2 gate: it exits nonzero on any divergence.

## Stage 1, declaration

A test case is a public static function without parameters carrying
the `@:test` metadata, with an optional description string argument:

```haxe
package tests;

import boring.VectorCodec;
import std.Test;

class VectorCodecTests {
	@:test("encode then decode returns the input records")
	public static function roundtrip():Void {
		final records = TestData.glyphSamples();
		final decoded = VectorCodec.decode(VectorCodec.encode(records));
		Test.equals(records, decoded, "decode(encode(records)) must equal the input");
	}
}
```

A test may declare the targets it does not apply to through the
`except` named argument of the metadata. The argument lists target
names; the excluded target does not run the test body and writes a
`not_applicable` record to its results file instead (below):

```haxe
@:test("a test that excludes swift", except = ["swift"])
public static function swiftOnly():Void {
	// runs on every target except swift
}
```

Rulings:

- Test modules live in the `tests.*` package under `samples/tests/`;
  they are intercepted like every other sample module and count as
  entry modules for generation.
- The metadata carries the declaration; a name prefix convention
  (`test*`) is rejected. Metadata is structural in the typed AST
  (`MetaAccess.extract` per feature spec 13); a name convention would
  reintroduce name-keyed selection, which this toolchain rejects
  everywhere else.
- The test identifier is `tests.VectorCodecTests.roundtrip` (module,
  class, function), derived from AST identity. The runner-visible
  name is the identifier plus the description:
  `tests.VectorCodecTests.roundtrip: encode then decode returns the
  input records` (colon-space separator; tests without a description
  use the identifier alone). Every target's `Test.run` registration
  carries the name beside the identifier, and every results file
  records it; runners that display titles (the TypeScript runners)
  show it as the test title.
- The `except` argument is structural metadata, never a name
  convention. The valid target names are the six results-file targets:
  `haxe`, `ts`, `kotlin`, `swift`, `dart`, `rust`. A test that names an
  unknown target or repeats a target stops the compilation with the
  function's identity and the offending name in the message. A test
  with no `except` argument applies to every target.
- An excluded target does not run the test body. It writes one
  `not_applicable` record to its results file in place of a verdict, so
  the id stays in the cross-target set and the consistency manager
  counts it as a declared exclusion (below). A target must not both run
  a test and declare it not applicable; a results file that carries a
  verdict and a `not_applicable` record for the same id is a divergence.
- A `@:test` function returns `Void` and takes no arguments; targets
  reject anything else at compile time with the function's identity
  in the message.
- Test inputs are constructed from literals inside the test sources,
  directly in the test function or through a helper module in `tests.*`
  without `@:test` statics (an ordinary module that emits to the main
  output tree). The binary fixture under `tests/vectors/` requires file
  input the subset does not declare; per-language suites keep loading
  it.

## Stage 1, assertion API: `std.Test`

`std.Test` joins the standard library ruled by standard library
spec 06: declared in `samples/std/Test.hx` on the compile-input side, lowered
through the runtime package per target, never appearing in output as
the `std` namespace.

- `run(id:String, body:() -> Void):Void`: executes one test body,
  records the outcome line (below), rethrows the failure so the
  native runner reports it as well.
- `ok(condition:Bool, message:String = null):Void`
- `equals<T>(expected:T, actual:T, message:String = null):Void`
- `fail(message:String):Void`

`equals` accepts the value domain of the subset: `Bool`, `Int`,
`haxe.Int64`, `Float`, `String`, `Bytes`, `Array<T>`, structures (feature spec 03),
and enum values (feature spec 01). Equality is structural for
aggregates and IEEE equality for `Float` (so `NaN` fails `equals`
against everything, including itself; tests that need `NaN` use `ok`).

A failed assertion raises the runtime's test-failure error carrying
the canonical message below. The Haxe reference raises
`haxe.Exception`; each target's runtime raises its platform error
(`Error`, `AssertionError`, panic). The raised type is
target-specific; the message string is the contract.

## Stage 1, the assertion runtime

The assertion checks and the canonical formatting are one compiled
module, `runtime.TestCore` (`src/runtime/TestCore.hx`), the single
source for every target. Each target compiles it into its test entry beside the handwritten
host: appended to `runtime/test.ts` on TypeScript, emitted as
`test/TestCore.kt` beside the host object on Kotlin, emitted as
`runtime/test_core.rs` beside the host module on Rust, and imported by
the generated Haxe runner. Emission gates on `std.Test` usage, so the
host and the resident always appear together.

`runtime.TestCore` takes only non-null parameters: an absent message
arrives as the empty string, and the canonical builder omits the
message line for the empty string exactly as it did for null.

The per-target host keeps the three edges a compiled module cannot
own: the runner state (the id of the running test), the raise of the
host language, and the result-file write. `std.TestPlatform`
(`samples/std/TestPlatform.hx`) names these edges:

- `raise(canonical)`: raise the platform error with the canonical text.
- `currentTestId()`: the id of the running test, empty when none runs.
- `intToString(v)` / `floatToString(v)`: the host's plain number text.

Each target lowers these statics inline inside the compilation of
`runtime.TestCore` only; business code that calls them stops the
compilation with an error, because business code calls `std.Test`.
Stage one implements them in `tests/haxe/TestPlatform.hx`, copied
beside the generated runner and bound as `globalThis.std.TestPlatform`.

## Stage 1, canonical failure message

Assertions format their messages in `runtime.TestCore`, never in the
native assert helpers, so the string is identical across targets. The
native runner reports the string; it does not format it.

```
test failed: tests.VectorCodecTests.roundtrip
  message: decode(encode(records)) must equal the input
  expected: [{code_point: 65, advance_em: 0.5, bounds: {x_min: 0.0, y_min: 0.0, x_max: 0.5, y_max: 0.5}}]
  actual:   [{code_point: 65, advance_em: 0.5, bounds: {x_min: 0.0, y_min: 0.0, x_max: 0.5, y_max: 0.5}}]
```

Rules:

- `test failed:` line carries the identifier.
- The `message:` line appears only when the assertion received one;
  `ok` and `fail` carry `message` only (no expected/actual lines).
- `expected:` and `actual:` lines carry the value representation,
  aligned by two spaces after the colon.
- Value representations:
  - `Bool`: `true` / `false`.
  - `Int`: decimal with `-` for negatives, no separators.
  - `haxe.Int64`: two lowercase eight-digit hexadecimal words, high word first, with no separator. This form compares every bit without decimal conversion differences.
  - `Float`: the shortest decimal string that parses back to the same
    IEEE-754 binary64 value. JavaScript's `Number.prototype.toString`
    and Rust's `Display for f64` implement this directly; JVM
    `Double.toString` matches on JDK 19+ (Ryukyu); toolchains older
    than that implement shortest-round-trip explicitly in the
    runtime. `Infinity`, `-Infinity`, `NaN` render as those words.
    Under `float-precision=f32` (feature spec 23) the same clause
    reads binary32: the shortest decimal string that parses back to
    the same IEEE-754 binary32 value, which Rust's `Display for f32`
    and JVM `Float.toString` implement directly.
  - `String`: double-quoted; `"` and `\` escaped; `\n`, `\r`, `\t`
    escaped; every other code point below 0x20 as `\uXXXX` with four
    lowercase hex digits.
  - `Bytes`: lowercase hex pairs, no separators.
  - `Array<T>`: `[` element `, ` element `]`.
  - Structure: `{` field `: ` value `, ` … `}` with fields in
    declaration order from the AST; the order is fixed by the source,
    so every target renders identically.
  - Enum value: `Kind` without payload, `Kind(payload)` with.

## Stage 1, the results-file contract

Every target writes its outcomes to one standard file; stage 2 reads
only these files.

- **Writer**: the test-entry host of the target (part of the `std.Test`
  lowering). `Test.run` appends one line per completed test;
  `runtime.TestCore.resultLine` builds the line, the host writes it.
- **Location**: the path in the environment variable
  `BORING_TEST_RESULTS` when set; otherwise
  `out/test-results/<target>.jsonl` relative to the working directory
  of the test run, with `<target>` one of `haxe`, `ts`, `kotlin`,
  `rust`.
- **Format**: JSON Lines, UTF-8, one object per completed test, keys
  in fixed order:
  - pass: `{"id":"tests.VectorCodecTests.roundtrip","name":"tests.VectorCodecTests.roundtrip: encode then decode returns the input records","verdict":"pass"}`
  - fail: `{"id":"…","name":"…","verdict":"fail","message":"<canonical message>"}`
  - not_applicable: `{"id":"…","name":"…","verdict":"not_applicable"}`
- The `name` value is the runner-visible name of the test
  (identifier plus description), JSON-escaped, byte-equal across
  targets; `Test.run` receives it beside the identifier.
- The `message` value is the canonical failure message string,
  JSON-escaped, byte-equal across targets.
- A target that excludes a test writes one `not_applicable` record in
  place of running the body. The record carries no `message`; the
  verdict names the declaration. A target that writes both a verdict
  and a `not_applicable` record for the same id is a divergence.
- A test that outruns the timeout budget of the run is recorded as a
  failure with the timeout message, on every target that carries the
  budget (see "Stage 1, the timeout verdict" below).
- The file opens in append mode; each line is written with a single
  append call, which keeps the file sound under the parallel test
  threads of `cargo test` and the runner pools of node and bun.
- No header, no footer, no summary line. A target that produced no
  file did not run; stage 2 reports that as an error (an absent file
  never counts as a passing empty run).

## Stage 1, per-target emission

### Haxe (reference tree)

The reference tree compiles `samples` and runs the same tests. A
compile-time macro collects the `@:test` statics and generates the
runner main that calls each through `Test.run` in declaration order,
catching each failure and printing the canonical message, exiting
nonzero when any test failed. The generated runner lives under
`out/haxe/` as build output. `tests/haxe/generate-main.hxml` runs the
collection macro and writes the runner; `tests/haxe/test-main.hxml`
then builds the generated `TestMain` entry, while
`tests/haxe/compile.hxml` stays on the typed entry `Main.hx`.
Generation is a separate haxe invocation that precedes the compile:
haxe caches classpath listings before macro callbacks fire, so one
invocation would fail to resolve `-main TestMain` on a fresh tree. The reference tree writes `out/test-results/haxe.jsonl` like
every other target.

### TypeScript

Test modules emit into a separate tree, never into the package source
tree; the `ts-test-output` define rules:

- `-D ts-test-output=<dir>`: the test tree root, required when any
  `tests.*` module is compiled. Absent define plus test modules stops
  the compilation with
  `ts-test-output define is required to emit tests`.
- File naming follows the selected runner's discovery convention
  (table below); one output file per test module.

A generated file contains exactly one registration import, for the
selected runner:

```ts
// <ts-test-output>/tests/VectorCodecTests.test.ts   (ts-test-runner=bun)
import { test, setDefaultTimeout } from "bun:test";
import { Test } from "@boring/runtime/test";
import { VectorCodec } from "../../reference/ts/gen/boring/VectorCodec.ts";
import { TestData } from "../../reference/ts/gen/tests/TestData.ts";
setDefaultTimeout(Test.runnerTimeoutBudgetMs());

test("tests.VectorCodecTests.roundtrip: encode then decode returns the input records", () =>
    Test.run("tests.VectorCodecTests.roundtrip", "tests.VectorCodecTests.roundtrip: encode then decode returns the input records", () => {
        const records = TestData.glyphSamples();
        const decoded = VectorCodec.decode(VectorCodec.encode(records));
        Test.equals(records, decoded, "decode(encode(records)) must equal the input");
    }));
```

The body lowers mechanically like any function. Assertions come from
the runtime package the `runtime-import` define names; only the
registration import varies by environment.

### Kotlin

Kotlin test code emits into a separate test source root, mirroring the
source-set split of the Kotlin ecosystem:

- `-D kotlin-test-output=<dir>`: the test source root, required when
  any `tests.*` module is compiled, same error contract as above.
- Files are written in package `tests.*`, named `<Module>Tests.kt`; a
  Gradle consumer maps the main output to `commonMain` and this root
  to `commonTest`.
- Registration uses an emitted annotation: each test function becomes a
  `@boring.test.Test fun` (fully qualified, because the assertion facade
  occupies the simple name `Test` through the runtime import; the
  generated file imports the runtime's `Test` unqualified and the
  annotation qualified). The annotation itself is emitted into the test
  root as `tests/TestAnnotations.kt`; Kotlin reserves the `kotlin`
  package for its own standard library, so the shim cannot declare
  `kotlin.test.Test` even though the classpath entry would name it.
- The per-repository runner compiles main output plus test root with
  `kotlinc`, adds `kotlin-test` to the compile classpath, and invokes
  a generated `TestMain` that runs the collection through
  `kotlin.test`; the `test:kotlin` script encodes this.

```kotlin
package tests

import boring.VectorCodec
import boring.runtime.test.Test
import tests.TestHelper

class VectorCodecTests {
    @boring.test.Test
    fun roundtrip() {
        Test.run("tests.VectorCodecTests.roundtrip", "tests.VectorCodecTests.roundtrip: encode then decode returns the input records") {
            val records = TestData.glyphSamples()
            val decoded = VectorCodec.decode(VectorCodec.encode(records))
            TestHelper.assertEquals(records, decoded, "decode(encode(records)) must equal the input")
        }
    }
}
```

Scalar assertions call the host `Test` object, whose members delegate to
`TestCore` in the same package with the null edges resolved; aggregate
assertions call the emitted `TestHelper`, whose failures route through
`Test.reportFailure`.

#### The Kotlin class test entry

A consumer tree sometimes drives its tests from its own Haxe runner and
calls ordinary static test functions from a list in that runner. Those
functions carry no `@:test` marker, so the `@:test` collection the Kotlin
runner is generated from never reaches them, and the classes they belong
to never run on Kotlin at all. Their work (a trace recorded for a
comparison of values, a table built for a later assertion) is then
absent from the Kotlin result file.

The conventional class test entry closes that gap without the target
naming any consumer package or class
(`packages/compiler/TestClassEntries.hx`). The entry is a public static
function named `runTestEntries` that takes no arguments and returns
Void, and it carries no `@:test` marker. The class declares it beside
the test functions and calls its own entry points in the body:

```haxe
class EnglishHyphenationTest {
    public static function hyphenatesCommonWordsAtSyllablePoints():Void { ... }

    /**
     * The conventional class test entry. It registers no test id; the
     * Kotlin runner calls it once on the class.
     */
    public static function runTestEntries():Void {
        hyphenatesCommonWordsAtSyllablePoints();
    }
}
```

Rules of the entry:

1. **The entry belongs to a class with no `@:test` function.** A class
   that carries `@:test` functions reaches the runner through that
   collection and holds a class instance there, so it uses the per-class
   flush entry of `features/27` for the work that follows its tests. A
   class that declares both stops the Kotlin compilation with `class test
   entry C.runTestEntries belongs to a class with no @:test function`;
   TS, Rust, Swift, and Dart stop the same declaration with the non-test
   member error of `features/27` ruling 6.
2. **The entry registers no test id.** The Kotlin runner emits one call
   per entry and no `Test.run` registration, so the cross-target test id
   set is unchanged. This is the property that lets a class run on Kotlin
   while its entries stay outside the comparison by id.
3. **The entry is a static member of its class.** The runner calls it as
   `Package.Class.runTestEntries()`, which resolves for an all-static
   class (a Kotlin `object`) and for a class with instance state (a
   companion member). The runner takes no instance for an entry class.
4. **The module of an entry class writes into the test root**, exactly
   like the module of a `@:test` class, so entry code stays out of the
   shipping tree.
5. **A throw from the entry fails the run like a throw from a test.** The
   runner catches it, continues with the remaining classes, and exits
   nonzero at the end.
6. **Only the Kotlin target validates the entry and calls it.** The
   Kotlin compiler checks the shape of rule 3 and stops a declaration
   that does not match (`class test entry C.runTestEntries must be
   public`, `must be static`, and `must take no arguments and return
   Void`). TS, Rust, Swift, and Dart type the declaration like any other
   static function, call it from no runner, and register nothing, so a
   malformed entry fails the Kotlin build only.

The probe is `samples/tests/KotlinEntryProbeTests.hx`: no `@:test`
function, one `runTestEntries` entry, entered in the entry lists of all
eight generation hxml files. The entry writes
`<BORING_KOTLIN_ENTRY_PROBE_DIR>/KotlinEntryProbeTests.txt` when that
variable is set and returns immediately otherwise, so a host observes
the Kotlin call by exporting the variable before the generated runner,
and the production loops stay free of writes. The class contributes no
test id on any target, so the probe also stands as the evidence that the
entry leaves the cross-target id set unchanged.

### Rust

Rust keeps unit tests inside the crate; no output-tree split exists:

- Test module `tests.VectorCodecTests` emits to
  `<rust-output>/tests/vector_codec_tests.rs` as a `#[cfg(test)]`
  module; the generated `lib.rs` declares each test module under
  `#[cfg(test)]`, derived from the module list the compiler processed.
- Each test function becomes a `#[test] fn` whose body wraps in
  `testlib::run`; scalar assertions call the resident directly
  (`crate::runtime::test_core::TestCore::…`, messages as `&str` with
  the empty string for an absent message), aggregate assertions call
  the emitted `test_helper`, failing through `panic!` with the
  canonical message.
- `cargo test` discovers and runs them natively.

```rust
use crate::runtime::test as testlib;
use crate::runtime::test_core;

#[test]
fn vector_codec_tests_roundtrip() {
    testlib::run("tests.VectorCodecTests.roundtrip", "tests.VectorCodecTests.roundtrip: encode then decode returns the input records", || {
        let records = TestData::glyph_samples();
        let decoded = VectorCodec::decode(&VectorCodec::encode(&records).unwrap()).unwrap();
        assert_equals_vec_glyph_metrics(&records, &decoded, &("decode(encode(records)) must equal the input"));
    });
}
```

## Stage 1, the timeout verdict

A native runner may stop a test that outruns its own timeout, and that
verdict has to reach the results file like every other failure.

One value rules the budget: the environment variable
`BORING_TEST_TIMEOUT_MS` in milliseconds, 5000 when unset or not a
positive integer. `std.Test.run` measures the wall-clock time of the
body, and a body that returns at or past the budget raises the timeout
error `this test timed out after <budget>ms`. The raise travels the
path of a failed assertion: the host records the failure line with that
message and rethrows, so the native runner reports the test as failed
too.

Every target that runs `std.Test.run` carries the check: TypeScript and
Kotlin first, then Rust, Dart, and Swift with the same name, the same
default, and the same message.

Rulings:

- The entry holds the verdict. A synchronous body cannot be preempted,
  so a runner that keeps its own timer learns about an overrun only
  after the body returned, which is after the entry has written its
  line. The TypeScript `bun` entry raises the runner timer with
  `setDefaultTimeout(Test.runnerTimeoutBudgetMs())`, which is the
  budget plus one second: a body inside the budget leaves the runner
  timer untouched, and a body past the budget raises before that timer
  can fire. The two verdicts agree in both directions.
- Rust, Dart, Swift, and Kotlin carry no runner timer, so the entry
  check is the only timeout there. Before the check existed, a body
  that overran the budget was recorded as a pass on every one of them:
  the record line was written from the return of the body alone.
- The timeout message is target-neutral and byte-equal between all five
  hosts, and its wording matches the phrase the bun runner prints, so
  one text reads in both places.
- The budget is read from the environment on every run, never at
  generation time, so one generated tree serves every budget.
- The raise wears the failure type of its target, so it enters the same
  catch clause as a failed assertion and no second result path exists:
  `Error` (TypeScript), `AssertionError` (Kotlin), `panic!` with a
  `String` payload (Rust), `TestFailure` (Dart), `TestFailure` (Swift).
  The record is written before the raise travels on, so the results file
  and the runner report the same verdict.
- The environment read and the clock use the facility each target
  already carries, and none of them adds a dependency: `process.env`
  and `Date.now` (TypeScript), `System.getenv` and `System.nanoTime`
  (Kotlin), `std::env::var` and `std::time::Instant` (Rust),
  `Platform.environment` and `Stopwatch` (Dart), and `getenv` through
  the conditional `Glibc`/`Darwin`/`CRT` import plus the standard
  library's monotonic `ContinuousClock` (Swift).
- The Swift test host is written without the header the generated
  modules carry, so `Test.swift` opens with its own conditional C
  imports; that is the one host whose imports are part of the emitted
  test source.
- The probe entries `tests/timeout-probe/ts.hxml`,
  `tests/timeout-probe/kotlin.hxml`, `tests/timeout-probe/rust.hxml`,
  `tests/timeout-probe/dart.hxml`, and `tests/timeout-probe/swift.hxml`
  compile `probe.TimeoutProbeTests`, one test that outruns the budget
  on purpose, into `out/timeout-probe/`:

      haxe tests/timeout-probe/ts.hxml
      bun test out/timeout-probe/ts/gen-checks/

      haxe tests/timeout-probe/kotlin.hxml
      kotlinc $(find out/timeout-probe/kotlin/gen out/timeout-probe/kotlin/gen-checks -name '*.kt') -include-runtime -d out/timeout-probe/probe.jar
      java -cp out/timeout-probe/probe.jar TestMainKt

      haxe tests/timeout-probe/rust.hxml
      BORING_TEST_RESULTS=$(pwd)/out/timeout-probe/rust/results.jsonl \
        cargo test --manifest-path out/timeout-probe/rust/gen/Cargo.toml

      haxe tests/timeout-probe/dart.hxml
      dart run out/timeout-probe/dart/gen-checks/main.dart

      haxe tests/timeout-probe/swift.hxml

  The probe stays out of the eight generation entries under `examples/`
  and out of the repository test run: it is slow and red by construction,
  and an ordinary run stays fast and green. Its test tree is named
  `gen-checks`, because the repository test command searches with the
  pattern `tests/` and a tree named `gen-tests` under `out/` would join
  every repository test run.
- The Rust probe entry lists `runtime.TestCore`, exactly as
  `examples/rust.hxml` does: the Rust target compiles a resident module
  only when the entry names it, and the generated entry calls
  `crate::runtime::test_core`. The root `Cargo.toml` excludes `out`,
  which lets the probe crate stand as a crate of its own: a package under
  the workspace root that the member list does not name stops the build.

## The TypeScript test environment define

The three native TypeScript runners have disjoint, unportable
registration APIs. The selection happens at compile time:

| `ts-test-runner` | registration import in each generated file | file suffix | native runner |
| --- | --- | --- | --- |
| `node` | `import { test } from "node:test";` | `.test.ts` | `node --test` |
| `bun` | `import { test, setDefaultTimeout } from "bun:test";` plus the `setDefaultTimeout(Test.runnerTimeoutBudgetMs())` call | `.test.ts` | `bun test` |
| `deno` | none (global `Deno.test(name, fn)`) | `_test.ts` | `deno test` |

Rulings:

- The define is required whenever test modules are compiled. There is
  no default: the compilation cannot derive the consumer's runtime,
  and a wrong guess produces output referencing globals or modules
  the environment does not provide. The missing-define error is
  `ts-test-runner define is required to emit tests (node | deno | bun)`.
- Runtime probing is rejected: generated code must not branch on
  `process.versions`, `Deno` presence, or any environment sniffing.
  One compilation targets one environment.
- The assertion layer and the results writer are the runtime package
  for all three values; the define selects the registration import
  and the file naming only.
- The repository's own verification runs the runner its hxml selects
  (`bun` today). A matrix script additionally runs the suite under `node`,
  which the flake provides; the `deno` build is generated and kept
  compiling by the same matrix when the toolchain enters the flake.

## Stage 2, the Haxe consistency manager

Cross-language consistency is managed from the Haxe side.

- The manager is a Haxe program under `tools/test-consistency/`,
  compiled and run like the reference tree (`hxml` entry, run through
  the interpreter or a js output). It ships with the package, so a
  consumer can run the same stage-2 gate over their own targets.
- Inputs: the results directory (default `out/test-results`, or the
  directory holding the `BORING_TEST_RESULTS` files of the targets) and
  the target list; the baseline target is `kotlin`.
- Comparison rules, per target against the baseline:
  1. The id set equals the baseline's set; a missing id or an extra
     id is a divergence. An undeclared absence stays a divergence: a
     target that drops a test without declaring it not applicable
     fails the check.
  2. For every shared id, the verdict equals the baseline's verdict.
  3. For every shared id, the `name` string equals the baseline's
     byte for byte.
  4. For every shared failing id, the `message` string equals the
     baseline's byte for byte.
  5. A target that declares a shared id not applicable (its record
     carries `verdict: "not_applicable"`) is counted as a declared
     exclusion and never a divergence. The baseline's own
     `not_applicable` record accepts a target that runs the test with
     a real verdict.
  6. A target that writes both a verdict and a `not_applicable`
     record for the same id is a divergence; a declared exclusion
     must not run the test.
- Output: a matrix (rows are test ids, columns are targets, cells show
  pass, fail, not_applicable, or the divergence kind), followed by the
  divergence list. Exit status is nonzero when any divergence exists;
  the manager's success is the stage-2 acceptance.
- The verify chain runs the manager after every target's test script;
  a target whose results file is absent fails the chain.

## Behavior consistency and acceptance

- Same source state, all four targets: identical test count, identical
  identifiers, identical verdicts, byte-identical failure messages;
  the manager exits zero.
- Mutation sensitivity applies to tests as source: renaming a test,
  changing a description, changing an assertion literal, or changing
  the `except` argument changes the emitted test files of every
  target; a name-keyed emission table is a fabrication defect under
  the same rule as any other output. A target that reads the
  declaration by test name, bypassing the structural metadata, is a
  fabrication defect.
- Test modules are part of the structure test scanner and the
  generation coverage checks; a test module absent from any target's
  output fails the build.
- Acceptance for any target touching test emission runs the four mutations over the sample sources, the full verify chain, and
  greps the compiler sources for test names (expect zero).

## Phasing

Phase 1 (this document): declaration metadata, `std.Test`
`run`/`ok`/`equals`/`fail`, canonical messages, the results-file
contract, all four emission targets, the `ts-test-runner` define with
all three values, the consistency manager.

Phase 2: `std.Test.throws(f:() -> Void, …)` for error-identity
assertions (the count-domain and bad-magic checks currently pinned in
the per-language suites). Function values are not in the translatable
subset today; `throws` arrives with them, and the per-language suites
keep error-variant coverage until then.

Fixture-driven tests (reading `tests/vectors/roundtrip.bin`)
wait on file input in the standard library; per-language suites keep
that coverage.

### Swift target rulings

#### Testing (`features/19`)

`@:test` statics collect into a test `main.swift` that runs each test in
order, catching thrown values, recording the pass or fail line to the
jsonl results file the consistency run reads, and exiting nonzero on any
failure. `std.TestPlatform` lowers inline: `raise` is `throw`,
`currentTestId` reads a file-scope variable the harness sets around each
test, and number-to-text rendering uses string interpolation. The binary
runs under `LD_LIBRARY_PATH=$BORING_SWIFT_LIBDISPATCH`.

### Dart target rulings

#### Testing (`features/19`)

`@:test` statics collect into a test entry `main()` that runs each test
in order, catches thrown values, records the pass or fail line to the
jsonl results file the consistency run reads, and exits nonzero on any
failure. `std.TestPlatform` lowers inline: `raise` is `throw`,
`currentTestId` reads a top-level variable the harness sets around each
test, and number-to-text rendering uses interpolation. The entry runs
under `dart run`.
