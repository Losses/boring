# Adjudication: `package-shell.test.ts:249` abort expectation vs. exit 0

**Ruling: the test side is wrong — a stale expectation, not a product defect.
The compiler and the spec agree; the test no longer constructs the scenario it
names.** Fixed in commit `eec707b9` (test + baseline-record supersession only;
no compiler or spec change).

- Repository: `/home/losses/Development/tq-workspace/boring-wt-architecture`
- Adjudicated at: `ee47913f` (branch `fix/test-collection-ignore-out`); fix commit `eec707b9`
- Date: 2026-09-30 (America/Toronto)

## 1. Reproduction — deterministic, not a timeout

Test expectation (pre-fix file, `tests/ts/package-shell.test.ts:249`, inside the
test starting at :242, "a by-name runtime import with an emitted manifest
aborts the compile"):

```ts
const result = await runHaxe("package-shell-byname.hxml", hxml);
expect(result.exitCode).not.toBe(0);
expect(result.stderr).toContain("package shell requires a relative runtime import");
```

[EXEC] `bun test tests/ts/package-shell.test.ts` (haxe 4.3.7, bun 1.3.13, cwd =
tree root, PATH from the chainA-fixed-rerun env file):

```
5 pass
1 fail
(fail) package shell emission > a by-name runtime import with an emitted manifest aborts the compile [31770.54ms]
error: expect(received).not.toBe(expected)
Expected: not 0        (tests/ts/package-shell.test.ts:249)
```

Actual exit code: **0**, no stderr. Determinism: the by-name scenario ran a
second time (full suite) and the scenario itself was re-run twice directly
[EXEC], `haxe out/repro-bynamescenario.hxml` → exit `0` both times, empty
stderr, and a valid `package.json` written (evidence
`repro-relative-emit-package.json`). Wall time ~31 s per scenario, far under
the 120 s harness timeout — no timeout marker anywhere; the mis-classification
as an environment timeout is confirmed wrong, as the corrected baseline record
says.

[EXEC] What that scenario actually is: the test's `rewriteHxml` rewrites only
the two output-tree defines when `runtimeImport` is undefined, and (with
`packageShell` undefined) drops `-D package-shell=none`. The runtime-import line
is left as whatever `examples/ts.hxml` carries — today
`-D runtime-import=./runtime`, a **relative** specifier. The test therefore
compiles **relative import + emitted manifest** while asserting the abort the
spec reserves for **by-name** import + emitted manifest. Evidence:
`repro-bynamescenario.hxml` (the exact hxml the test built; `runtime-import`
line and the absent `package-shell` line are visible in it).

## 2. Spec 24 reading — the abort is conditional, not unconditional

The task framing and the baseline record both say "spec 24 requires an
unconditional abort." Read from the documents, that is a misread.
`docs/specs/features/24-package-shell.md`, Ruling 5 (TypeScript) is the only
place the abort is required, and it is scoped:

> "The validity condition is a relative runtime import: generated files
> reference the runtime through the `runtime-import` define, and a by-name
> import such as `@boring/runtime` names a package coordinate that does not
> exist, so **a compilation combining a by-name runtime import with an emitted
> manifest stops** with `package shell requires a relative runtime import: a
> by-name runtime import names a package the manifest cannot declare; pass
> runtime-import a relative specifier or package-shell none`. **When
> `runtime-import` carries a relative specifier, the compiler computes the
> per-file relative path to the runtime entry**, the same computation the test
> imports already use."

So the spec requires:

1. by-name (non-relative) runtime import + emitted manifest → **stop**, with
   the sanctioned message verbatim;
2. relative specifier + emitted manifest → **accept**, with per-file relative
   paths;
3. nothing is required of the combination by-name + `package-shell=none` (no
   emitted manifest to invalidate — Ruling 1: `none` "writes source only").

The spec's test hook lists "the by-name runtime-import rejection" as one of the
assertions `tests/ts/package-shell.test.ts` must carry — the rejection is
required *as a test of the by-name case*, not unconditionally.

## 3. The guard — exactly the spec's scope

[CODE] `packages/compiler/reflaxe/ts/tscompiler/Compiler.hx` (unchanged since
the test was written; identical conditions and message at
`src/reflaxe/ts/tscompiler/Compiler.hx:266` of `52044ed1`):

```
560:        if (PackageShell.enabled()) {
561:            emitPackageShell();
...
579:    function emitPackageShell():Void {
580:        final runtimeImport = RuntimeConfig.importName();
581:        if (anyRuntimeUsed() && runtimeImport != null && !TsImports.isRelativeSpecifier(runtimeImport)) {
582:            Context.error("package shell requires a relative runtime import: ...",
583:                Context.currentPos());
584:        }
```

The effective conditions are four, not three: the guard sits inside
`if (PackageShell.enabled())`, so it fires only while an emitted manifest is
being written, and only when (a) the compilation uses the runtime
(`anyRuntimeUsed()`, :717), (b) a runtime import is set, and (c) the
specifier is not relative. Each condition maps to the spec's wording: the
abort is for the *combination* with an *emitted* manifest; "generated files
reference the runtime" is what `anyRuntimeUsed()` captures (the manifest only
carries a `./runtime` entry "when the compilation used the runtime", Ruling 5);
"by-name" is the negation of "relative specifier" (for TS,
`TsImports.isRelativeSpecifier` — `./runtime` is relative, `@boring/runtime`
is a package coordinate). A missing import is already a hard error before this
point (`RuntimeConfig.requireImportName`, `packages/compiler/RuntimeConfig.hx`).

## 4. Cross-target comparison — the difference is the spec's design, not an inconsistency

[CODE] `runtime-import` is shared by every reflaxe target (`RuntimeConfig.hx`:
"`@scope/runtime` verbatim for TypeScript, a dotted package for Kotlin, a crate
name for Rust"), and the current example hxmls show each target's by-name
choice:

| hxml | runtime-import | relative? | package-shell | manifest embeds a runtime import? |
| --- | --- | --- | --- | --- |
| `examples/rust.hxml` | `crate::runtime` | no (internal crate path) | default (emit) | no — zero deps, `[lib]` only |
| `examples/kotlin.hxml` | `boring.runtime` | no (internal package) | default (emit) | no — `srcDir "."` |
| `examples/dart.hxml` | `@boring/runtime` | no | default (emit) | no — name/version/SDK only |
| `examples/swift.hxml` | `@boring/runtime` | no | **none** (opt-out) | n/a |
| `examples/ts.hxml` | `./runtime` | **yes** | **none** (opt-out) | yes — `./runtime` export |

Rust and Kotlin *accept* the same by-name source because their by-name
specifiers name paths **inside the emitted tree** (runtime-emit writes the
runtime into the same crate/package), and their manifests carry no runtime
entry (spec 24, Emitted-artifacts table). TypeScript is the only target whose
manifest must declare how the runtime is reached (the `exports` map), and its
by-name form is an *external* npm coordinate no generated `package.json` can
declare. Spec 24 scopes the abort to TypeScript (Ruling 5) for exactly this
reason, and the TS compiler is the only one carrying the guard (grep: the
error string and `isRelativeSpecifier` appear only under `reflaxe/ts/`).
Swift's example opts out of emission entirely, matching the test file's own
comment that "the Swift target opts out of the emitted manifest". There is no
cross-target inconsistency to resolve; the acceptance/rejection difference
follows from which manifest embeds an import path.

## 5. Ruling and grounds

The three candidates:

- **Spec overreaches, guard right?** No. The spec does not overreach: it never
  demands an unconditional abort; it demands the abort only for the by-name +
  emitted-manifest combination and explicitly requires accepting the relative
  case. The "unconditional" claim is a misreading, present in both the task
  framing and the (now superseded) baseline record.
- **Guard under-enforces (product defect)?** No. The guard fires precisely when
  the spec says to stop and not when it says to accept; it has not changed
  since the test was written, and the discriminating runs (§7) confirm each
  branch matches the spec.
- **Test mis-states the spec?** **Yes.** [CODE + EXEC + git history] The
  by-name test was written at `52044ed1` ("test(ts): cover package shell
  emission and pin the manifests"), when `examples/ts.hxml` carried
  `-D runtime-import=@boring/runtime` (line 14 of that commit's file) plus
  `package-shell=none`; the test dropped the opt-out and inherited the by-name
  import, correctly exercising the spec's rejection. At `2bd609b9`
  ("feat(bundle): add the spec 59 bundle driver"), the hxml line moved to
  `-D runtime-import=./runtime` (the commit's own comment: "The runtime import
  is relative, so the tree is self-contained and the package shell accepts it
  (feature spec 24)"), and the test file's only change in that commit was an
  unrelated Rust manifest path. The test's `rewriteHxml` matched only the
  historical value `-D runtime-import=@boring/runtime`, so it silently stopped
  constructing the by-name scenario and started compiling relative + emit —
  a configuration spec 24 requires to be **accepted**. The failing expectation
  is therefore stale: it asserts an abort the spec does not require for the
  configuration the test actually builds. This is a stale expectation, not a
  product defect; the compiler exiting 0 is the spec-mandated behavior.

## 6. The fix — commit `eec707b9` (two files)

- `tests/ts/package-shell.test.ts`:
  - the by-name test now **pins its own scenario**: passes
    `runtimeImport: "@boring/runtime"` (the spec's own example coordinate), so
    the rejection is exercised regardless of `examples/ts.hxml`'s state;
  - `rewriteHxml` rewrites the `runtime-import` line to whatever the scenario
    supplies (`/^-D runtime-import=[^\s]+$/m`) instead of matching only the
    historical value — the same fragility that caused the stale expectation;
  - **assertions unchanged** (`exitCode).not.toBe(0)` + the sanctioned message
    substring). No test deleted, skipped, or weakened; the test is strictly
    stronger — it now constructs the scenario it names instead of inheriting
    ambient repo state, which also matches how the file's other four tests
    already pin `runtimeImport: "./runtime"`.
- `docs/architecture/BASELINE-FAILURES.md`: the entry 1
  "product/spec gap … spec 24 requires an unconditional abort" paragraph is
  superseded in place (house style: appended note, original text preserved)
  with the adjudication. The record's "Either the test or the spec must
  change" is answered: the test changed.

Full diff: `evidence/commit-eec707b9.diff`.

## 7. Discriminating readings (all [EXEC], haxe from tree root)

The three configurations the spec distinguishes, measured directly
(exit codes recorded without a pipe; `evidence/direct-exitcodes.txt`):

| Configuration | Spec 24 Ruling 5 | Measured | Evidence |
| --- | --- | --- | --- |
| relative import (`./runtime`) + emitted manifest | accept, per-file relative paths | **exit 0**, empty stderr, valid `package.json` (run twice, identical) | `repro-run1.log` (test), `direct-run1/2.*`, `repro-relative-emit-package.json` |
| by-name import (`@boring/runtime`) + emitted manifest | stop with the sanctioned message | **exit 1**, stderr exactly the sanctioned message | `discrim-A.stderr`, `repro-bynA.hxml` |
| by-name import + `package-shell=none` | no requirement (no manifest to invalidate) | **exit 0**, empty stderr, no `package.json` written | `discrim-B.stderr`, `repro-bynB.hxml` |

Sanctioned message verbatim (`discrim-A.stderr`):

```
package shell requires a relative runtime import: a by-name runtime import names a package the manifest cannot declare; pass runtime-import a relative specifier or package-shell none
```

Post-fix suite [EXEC] (same environment):

- `bun test tests/ts/package-shell.test.ts` → **6 pass, 0 fail**, exit 0
  (`evidence/verify-run.log`); the acceptance side (default emission test:
  `stderr` empty, `exit 0`, consumer program runs under bun) still passes, so
  the fix did not break any accepted program.
- The by-name test alone (`bun test -t "by-name runtime import"`) → 1 pass,
  0 fail, exit 0 (`evidence/verify-bynamesolo.log`) — passes independently of
  suite order.

## 8. Unverified / caveats

- **Not re-run at `52044ed1`**: I did not check out the historical tree to
  prove the test passed at its creation; the conclusion rests on the hxml and
  compiler state at that commit (both inspected via `git show`: by-name import
  present, guard logic identical) plus the drift at `2bd609b9`. High confidence,
  one unexecuted step.
- **Tracked file rewrite during full-suite runs** [EXEC]: running the full
  `package-shell` file rewrites tracked `samples/boring/MathNaNTestSupport.hx`
  (its five `Test.equals` calls stubbed to empty bodies), hitting 0 twice
  during this adjudication. Restored both times with
  `git checkout HEAD -- samples/boring/MathNaNTestSupport.hx`; final count is
  5 and the working tree is clean apart from another worker's uncommitted
  `tests/ts/package-artifacts.test.ts` edit, which I did not touch and did not
  commit. The mechanism (which pipeline step rewrites it) is not investigated
  here; it affects any worker running the ts generation suite.
- The `anyRuntimeUsed()` condition was not probed for the by-name + unused-
  runtime corner case (no such scenario in the repo; the spec's "generated
  files reference the runtime" framing supports the guard's reading). It does
  not affect this ruling: the failing scenario uses the runtime, so the
  condition is satisfied there.
- Branch state: commits landed on the shared branch
  `fix/test-collection-ignore-out`; a parallel worker committed
  `c89e93fe` during this session (my commit `eec707b9` sits above it).
