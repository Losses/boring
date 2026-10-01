# Baseline failures — recorded, not waived

`docs/architecture-work-plan.md:417` requires: *"Record any baseline failure
separately, including its revision and reproduction; a baseline finding does
not waive the standard."* This is that record. The standard it does not waive is
`docs/specs/style/02-translator-implementation-standard.md:78/:80`.

**Why this record did not exist before:** the collection command could not run
at all. `bun test` scans the project root and treats positional arguments as path
suffix filters, so the generated `out/` tree (654 MB, 4,052 duplicated
`*.test.ts` files, 35 symlinks) was pulled into every scan; duplicates share a
suffix with the real files, and collection died with
`Cannot find module ... from ''` plus EMFILE. Gitignoring `out/` does not help —
bun's discovery does not read `.gitignore`. Established by bisection: the real
tree fails, a clean copy collects, and a clean copy with `out/` re-synced
reproduces the identical failure.

**Reproduction:** `bun run test` at `695940e8` (which adds
`bunfig.toml` with `[test] pathIgnorePatterns = ["out/**"]`). 303 test files
collected, zero `out/` references, 1001 pass / 32 fail / 8 errors (1033 tests,
8026 expect calls), wall time 1864 s, exit code **1**.

**Revision:** the run is against `695940e8`; its parent `05e375b2` carries the
same test corpus but could not collect at all.

**Warning count (measured; the original record omitted it):** the raw log of
this run (`dc-warn/out/ci-wire/evidence/recorded-baseline-proof-run.log`)
contains **0** warning lines naming files under the generated trees
(`reference/*/gen`, `reference/*/gen-tests`). This measured 0 is the gate
baseline for the CI collected-suite job's warning check; exceeding it is an
acceptance failure under `docs/specs/style/02-translator-implementation-standard.md:80`.
The number is measured from the retained log, not inferred or assumed.

**Domain drift since this run:** the baseline recorded 303 test files (249
generated `reference/ts/gen-tests/**` + 54 hand-written). The collected domain
is now **304 files / 55 non-generated**: `tests/swift-gap-boundary/gap-boundary.test.ts`
landed in `d14231a6`, after both the baseline run and the CI job commit
`9f26e1ef`. The pass/fail/errors numbers above remain tied to the 303-file
domain; the +1 file is a later corpus addition, not a re-measurement of the
baseline numbers.

---

# Discharge record — the six pre-existing reds (2026-09-30)

**The six are no longer red.** Four commits on `fix/test-collection-ignore-out`
discharged them (base for the seat's work: `ec4c5c2d`):

| Baseline red (§4) | Discharged by | Ruling |
|---|---|---|
| #1 arithmetic helpers, Rust inlining | `a80690f1` | expectation stale — pin refreshed to the signed-domain statements (strictly stronger) |
| #2 RustExpr.hx carries no banned identifier | `28820ff5` | generator defect — `boring_fold_debug` renamed to `rust_fold_debug` (output-neutral) |
| #3 loop structure, reference/ts/gen | `ac4099ea` | generator defect — dataClass comparator bound hoisted into the for-head init |
| #4 loop structure, reference/rust/gen | `50a95377` | generator defect — four post-guard `.map(` callback pipelines lowered without callbacks |
| #5 sorted dataClass keys, pins resident comparators | `a80690f1` | expectation stale — pin refreshed to the exact current declared-faithful form |
| #6 sorted key domains, int capacity bound | `a80690f1` | expectation stale — pin refreshed to the exact current statement |

The enumeration above is kept as written: the six existed, this is where they
came from, and `:417`'s purpose is the record, not the waiver. The three
`a80690f1` refreshes each compare the fresh generated form against what the
Haxe source declares and date the pin against the generator behavior it
describes; the three generator fixes each carry a negative control (revert +
regenerate makes the same scoped test fail again). Per-failure detail: commit
messages and `dc-warn/out/baseline-red-fix/REPORT.md`.

## Fresh-tree reproduction (supersedes the §4 mechanism limit)

The §4 limit said "pre-existing" rested on a mechanism argument, not a clean
re-run, because `reference/*/gen` is gitignored and absent from the clean
pre-fix copy. That limit is no longer operative: the six reproduce on
freshly generated output at the pre-fix revision and pass on freshly
generated output at the post-fix revision.

Seat run (inherited, corroborated by its logs): at `ec4c5c2d` the five scoped
files ran red (exit 1, 88 pass / 6 fail / 670 expect); all five trees were
then regenerated with `haxe examples/<target>.hxml` (all exit 0) and the same
six failed on the fresh output —
`dc-warn/out/baseline-red-fix/evidence/baseline-six-fails.log`. After the four
commits the same command passes (exit 0, 94 pass / 0 fail / 705 expect) —
`dc-warn/out/baseline-red-fix/evidence/final-five-files-pass.log`.

Independent re-measurement (this update, 2026-09-30, measured at
`4c292c64`; raw logs in `dc-warn/out/baseline-record-update/evidence/`):

- **Pre-fix:** a clean worktree at `ec4c5c2d` regenerated the five trees
  (ts, rust, kotlin, swift, dart — each `haxe examples/<t>.hxml`, all exit 0)
  and the scoped five-file run fails, exit 1, 88 pass / 6 fail / 670 expect —
  the six failures are exactly the six §4 reds, by name
  (`prefix-five-files.log`).
- **Post-fix:** the same five trees regenerated at `4c292c64` (all exit 0),
  and the scoped five-file run passes, exit 0, 94 pass / 0 fail / 705 expect —
  twice, before and after the regeneration (`scoped-five-files.log`,
  `scoped-five-files-after-regen.log`).
- **Tree currency:** each regenerated tree is byte-identical to the on-disk
  tree the scoped tests read live (`diff -rq` empty, all five targets,
  `diff-<t>-regen.txt`). The only uncommitted generator-source change in the
  shared tree during this update was another seat's in-flight `SwiftExpr.hx`
  patch; it is compiled only under the swift hxml (per-target `-cp` roots),
  so the ts/rust/kotlin/dart regenerations reflect the committed compiler
  state. For swift, a regeneration from a pure-HEAD worktree — the committed
  state, no in-flight working-tree patch — is byte-identical to both the
  shared-worktree regeneration and the on-disk tree, so the scoped pass holds
  against committed-compiler output either way
  (`diff-swift-purehead-vs-worktree.txt`, `diff-swift-purehead-vs-snapshot.txt`).
- **Consistency check:** the pre-fix and post-fix rust-f32 trees differ in
  exactly the nine files the `50a95377` emitter changes touch
  (`diff-rustf32-prefix-vs-purehead.txt`); the on-disk rust-f32 tree matches
  the pure-HEAD regeneration byte-for-byte (`diff-rustf32-snapshot-vs-purehead.txt`).

Inherited, not re-measured here: the seat's per-failure rulings (pin dating,
L5 negative controls), its L3/L4 results (`cargo check`/`cargo test` on the
rust trees, `tsc -p .`, `bun test reference/ts/gen-tests/`), and the
byte-identity of the `28820ff5` rename. Each is documented in the commit
messages and `dc-warn/out/baseline-red-fix/REPORT.md`; none is load-bearing
for the scoped verdict, which this update re-measured directly.

## Current baseline (inherited — the full suite was not re-run)

The full-suite count stands as inherited from the `695940e8` proof run
(1001 pass / 32 fail / 8 errors, 1033 tests, 8026 expect calls, 1864 s). This
update did not re-run the 31-minute suite (shared tree, and
`tests/ts/package-artifacts.test.ts` rewrites the tracked
`samples/boring/MathNaNTestSupport.hx` fixture). Of the 32 fails, the six
deterministic reds are discharged (scoped: exit 0 at `4c292c64`, measured);
the 26 environment timeouts and 8 cascade errors stand as recorded. The
expected shape of a future full run at comparable contention is therefore
1007 pass / 26 fail / 8 errors — **arithmetic from the inherited run plus the
scoped discharge, not a measurement**; no full run has been performed since
the baseline. Two inherited-run caveats: the four measured-budget commits
(`9905949e`, `36e7540e`, `e8a4c3bb`, `4c292c64`, 2026-09-30 13:52) replaced
the inherited 5 s default on 16 haxe-pipeline tests after that run, so the
timeout class may shift; and the timeout class is
machine-contention-dependent by its own classification.

The branch tip moved to `1eeaa4ad` during this update (three commits,
`d14231a6`, `fc89d5d8`, `1eeaa4ad` — docs and one test file; none touches the
five scoped test files or generator sources, verified by
`git diff --stat 4c292c64..1eeaa4ad`).

## The standard is not waived

`docs/architecture-work-plan.md:417` requires the record, not the waiver. The
standard it does not waive is unchanged:
`docs/specs/style/02-translator-implementation-standard.md:80` still requires
the warning count in generated trees to be zero. No test, pin, or guard was
deleted, skipped, or weakened by the discharge: the three refreshed pins are
strictly stronger or exact-current-form pins, and the guard file
`samples/boring/MathNaNTestSupport.hx` kept its `Test.equals` count of 5
through every run in this update.

---

# Fix report: `bun run test` test collection (boring-wt-architecture)

Branch: `fix/test-collection-ignore-out` (commit `695940e8`, on top of `05e375b2`).
Diff: `COLLECT.diff`. Raw logs: `evidence/proof-run.log`, `evidence/proof-exit.txt`.

## 1. Cause (bisection, not argument)

- Real tree, `bun test tests/ts/array-root.test.ts`: exit 1 before any test runs —
  `Cannot find module '.../tests/ts/array-root.test.ts' from ''`, plus
  `Cannot read file ".../out/architecture-alias-targets/e3b8-source": EMFILE`.
- Clean rsync copy (`/tmp/btest-wt`, excluding `out/`, `.git`, `node_modules`):
  same command collects 1 file and runs (2 tests, 1 pass / 1 timeout).
- Same clean copy **with `out/` rsynced back in**: identical `from ''` / EMFILE
  collection failure reproduces.

Conclusion: the hypothesis is CONFIRMED. `bun test` scans the project root for test
files and treats positional args as path-suffix filters. The generated `out/` tree
(654 MB, 4,052 duplicated `*.test.ts` under `out/**/tests/`, 35 symlinks) is swept
into every scan; duplicates such as
`out/architecture-alias-targets/e3b8-source/tests/ts/array-root.test.ts` match the
same suffix as the real file, and collection dies on the duplicate/EMFILE tree
(`from ''` = bun's resolution base is empty for these scan artifacts). `out/` being
gitignored does not help — bun's discovery does not respect .gitignore. The
`package.json` trailing-comma repair was necessary but not sufficient, as observed.

## 2. Fix

New `bunfig.toml` at repo root:

```toml
[test]
pathIgnorePatterns = ["out/**"]
```

Why this option: `[test] root = "tests"` also fixed collection in experiment, but
it would exclude `packages/registry/tests/` from discovery; the script runs both
roots. `pathIgnorePatterns` excludes only the generated tree, works both on the CLI
(`--path-ignore-patterns`) and in bunfig, and changes nothing about which real
tests are collected or how they run. No test was deleted, skipped, renamed, or
weakened. `git status` after the proof run shows no test-file modifications; guard
file `samples/boring/MathNaNTestSupport.hx` intact (`Test.equals` count = 5
before and after).

## 3. Proof run

Command: `bun run test` (= `bun test tests/ packages/registry/tests/`), cwd =
tree root, output redirected to `evidence/proof-run.log`, exit code captured
directly (no pipe) into `evidence/proof-exit.txt`:

- Collection: 303 test files, **all** from `tests/` and `packages/registry/tests/`;
  zero `out/` references in the log.
- Result: **1001 pass / 32 fail / 8 errors, 1033 tests, 8026 expect() calls**,
  wall time 1864 s (~31 min).
- **Exit code: 1** (due to the baseline failures enumerated below — collection
  itself succeeds; the pre-fix run executed 0 tests).

## 4. Baseline failure enumeration (the `architecture-work-plan.md:417` record)

### Pre-existing red (deterministic assertion failures, complete in ms) — 6

1. `arithmetic helpers generated tree > Rust inlines arithmetic helpers into native comparison operators and if-blocks` [1 ms] — `expect().toBe` mismatch on generated Rust tree content.
2. `compiler boundary > packages/compiler/reflaxe/rust/rustcompiler/RustExpr.hx carries no banned identifier` [2 ms] — banned identifier present in tracked source.
3. `loop structure > reference/ts/gen carries no functional iteration...` [50 ms] — generated reference tree contains banned iteration constructs.
4. `loop structure > reference/rust/gen carries no functional iteration...` [125 ms] — same class, Rust gen tree.
5. `sorted dataClass key generated trees > pins resident comparators` [1 ms] — generated-tree content mismatch.
6. `sorted key domains generated tree > Rust generated tree widens an int capacity bound without an error enum` [1 ms] — generated-tree content mismatch.

Reason they are pre-existing rather than caused by the fix: the fix only changes
which files bun *discovers*; these are ms-fast `expect()` mismatches on
generated/reference tree content, unrelated to discovery. (Cross-check in the
clean pre-fix copy was not possible for these — `reference/*/gen` is gitignored
and absent there — so "pre-existing" rests on the mechanism argument above, not a
clean-tree rerun. Everything else about the fix is directly verified.)
**Superseded 2026-09-30** — the Discharge record above settles this point:
the six reproduce on fresh output at `ec4c5c2d` and pass on fresh output at
`4c292c64`, independently re-measured. The paragraph stands as the historical
state of the record at its writing.

### Two things the old count of 26 hid

**1. A deterministic assertion failure that is NOT a timeout.**
`tests/ts/package-shell.test.ts:249` expects an abort; the compiler exits 0. It
carries no timeout marker and is stable, so it is a **product/spec gap**: spec 24
requires an unconditional abort while the guard at `Compiler.hx:578-583` fires
only when `anyRuntimeUsed()` holds, a runtime import is set, and the specifier is
not relative. Either the test or the spec must change. Named here, unfixed.
**Superseded 2026-09-30** — adjudicated from the documents: the "unconditional"
reading was a misread. Spec 24 (Ruling 5) stops only a compilation that combines
a by-name runtime import with an *emitted* manifest, and a relative specifier
with an emitted manifest must be accepted. The guard enforces exactly that scope
(and it runs only when `package-shell` is enabled), so the compiler was right
and this is a stale test expectation, not a product defect: `examples/ts.hxml`
moved from `-D runtime-import=@boring/runtime` to `./runtime` (2bd609b9) without
updating the by-name test, which inherited the now-relative specifier and
asserted an abort the spec does not require for it. The test now pins
`runtime-import=@boring/runtime` itself; suite passes, no compiler or spec change.

**2. npm artifact generation is non-deterministic, and that reaches the CI gate.**
The `package/dist/boring/MathNaNTestSupport.{js,d.ts}` entries flip in and out of
the generated tgz between runs - 407 entries versus 405, and the \u00b1116-118
compressed bytes they account for are the *entire* difference the byte-identity
test at `package-artifacts.test.ts:333` reports. Timestamps are fixed and entry
names are ordered, so it is the entry set, not metadata. Consequence: that test
flakes, and because the `collected-suite` job runs the suite, **contract 3's gate
will intermittently go red for a reason unrelated to any change under review.**
Established as pre-existing by a failure at 13:17 in a run made before the
timeout-budget commits. It needs its own determinism task.

### Environment timeout under machine contention — 25 (corrected 2026-09-30; see below)

All 25 remaining fails carry a literal `this test timed out after Nms` marker:

- 5000 ms (bun default; the tests set no own timeout): 18 fails, incl. `tests/ts/array-root.test.ts` (which reproduces its timeout in the clean pre-fix copy too — this class pre-dates the fix), `strict TypeScript emitter output` ×4, `float precision` ×2, extern-bindings ×2, StringTools, Kotlin deferred assignment, Rust module layers, Rust Bytes borrows, payload enums, array/static-mutation rules, `@:sealed`, self-construction.
- 15000 ms own budget exceeded: 2 (`static initializer mutation`, `sanctioned self-construction static target lanes`).
- 60000 ms own budget exceeded: 3 (`package artifact emission` cargo/Pub, `Swift read-only array boundary`, + one unhandled-error trigger).
- 120000 ms own budget exceeded: 2 (`record printed-member mutations`, `Std.string lowering nullable operands`), plus `value wrapper generated trees > rejects each invalid marker shape` (360 s wall, 120 s budget — multiple target lanes each hitting the budget).

Measured cost vs own budget: every one exceeded its configured budget by ~0.1%–3×
while doing real `haxe`/`swiftc`/`cargo` compile work on a contended machine;
these are environment results, not product defects. Corroboration: the identical
default-budget timeout reproduces in the clean uncontaminated copy.

### Infrastructure — 8 (counted in "8 errors", orthogonal to the 32)

Eight `# Unhandled error between tests` entries, each immediately following a
timeout in the same file (log lines 66, 87, 108, 314, 365, 386, 525, 741): bun's
per-file abort after a timed-out test leaves dangling state (`killed 1 dangling
process` also appears). They are cascade damage from the timeouts above, not
independent failures.

### Toolchain absent from PATH — 59 (added 2026-10-01)

A class distinct from the timeouts above, and previously unrecorded. When the
suite is run with only the default `PATH`, every test that shells out to a
compiler fails — not because a budget was exceeded, but because the executable
does not exist at that name:

```
Executable not found in $PATH: "haxe"     58
Executable not found in $PATH: "swiftc"    1
```

They are **environment results, not product defects**, by the same test the
timeout section uses: the literal marker names the missing executable, and the
same tests pass once the toolchain is on `PATH`. Corroboration run for this
record — with haxe, cargo and kotlinc on `PATH`, three of the guards implicated
in that session's work passed `12 pass, 0 fail`.

**Why it is worth its own entry.** The timeout class is a *budget* result on a
contended box; this class is a *resolution* result with a quiet box. Recording
them together would obscure both, and this class is the one that makes
`bun test tests/` look far redder than the product is. Reading it as regression
would send someone to investigate missing toolchains as if they were defects —
the mirror of the earlier error where environmental failures were recorded as
real ones.

Counts read from a single run at `602e9222` (1000 pass, 61 fail, 1 error, 1061
tests across 312 files); 59 of the 61 fails carry the marker above.

## 5. Notes / not verified

- The working tree carries pre-existing modifications I did not make: the
  `package.json` JSON repair, and exec-bit loss (mode-only diffs) on ~20
  `tests/haxe/**/run*.sh` + `tools/` scripts from the fuse mount. I committed
  only `bunfig.toml`.
- Per-test worst-case timings under a quiet machine were not measured (contended
  box); the timeout classification relies on in-log budget markers, which are
  direct evidence.
