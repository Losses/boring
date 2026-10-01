# Verification — timeout-budget commits 9905949e / 36e7540e / e8a4c3bb / 4c292c64

Independent verifier seat, 2026-09-30 17:57–18:30 UTC. All runs my own unless
marked **[inherited]**. Repo `boring-wt-architecture` at `4c292c64` (the last
reviewed commit is HEAD). Raw logs `evidence/V-*.log`, exit codes + fixture
guard records `evidence/V-*.rc`.

Environment: PATH from `chainA-fixed-rerun/evidence/env.json`; `bun test`
scoped to one file, cwd = tree root; exit codes captured directly (never
through a pipe); tracked fixture `samples/boring/MathNaNTestSupport.hx`
`grep -c 'Test.equals'` checked before/after every run (one concurrent-seat
violation caught and restored; count = 5 at report time; clobbered and re-restored a second time by yet another concurrent package-artifacts run — another seat was live in the same file throughout my window).

**Load caveat**: the tree was under concurrent load for my whole window — at
least three other seats' `haxe` processes plus another seat's
`bun test tests/ts/std-string.test.ts` were live during my runs (ps evidence
noted in-session). My timings are contended, which makes them a *stress test*
of the 2× margins, not a confirmation of the quiet-window numbers.

## Verdicts

| # | Claim | Verdict |
|---|---|---|
| 1 | Budgets justified by measured cost + stated margin | **CONFIRMED** (arithmetic mine; quiet costs [inherited], corroborated under load) |
| 2 | No assertion weakened/deleted/skipped | **CONFIRMED** |
| 3 | 8 cascades each follow a same-file timeout | **CONFIRMED 8/8, one IMPRECISE attribution in report §1** |
| 4 | Changed tests now pass | **CONFIRMED** (6 files spanning all four classes, real exit codes) |
| 5 | Nothing else regressed | **CONFIRMED, with one pre-existing knife-edge test flagged (not touched by the commits)** |

## 1. Budget arithmetic — CONFIRMED

Recomputed margin = new_budget / measured_cost for 13 of the 25 tests (≥6
required), covering all four classes, from the report §4 table, and
cross-checked the underlying evidence: the fixer's `B-*.log/.rc` wall times
match the table exactly (B-std-string 141.82 s, B-printed-record 188.56 s,
B-value-type 353.70 s, B2-sealed-lanes 113.76 s, B2-static-state 29.62 s,
B-pkg-artifacts 79.31 s, B-readonly 79.93 s, B-strict-output 4 tests
99.44 s, B-extern 2 tests 45.05 s) and every `.rc` records pre/post fixture
guard = 5.

| test | measured (s) | new (ms) | my recompute | report says |
|---|---|---|---|---|
| dart precision | 28.146 | 60 000 | 2.132× | 2.13× |
| ts precision | 26.964 | 60 000 | 2.225× | 2.23× |
| strict-output t1 | 24.544 | 60 000 | 2.445× | 2.4× |
| array-root | 73.720 | 150 000 | 2.035× | 2.03× |
| constructed-state | 70.646 | 150 000 | 2.123× | 2.12× |
| enum-sorted | 24.294 | 60 000 | 2.470× | 2.47× |
| static-state | 29.489 | 60 000 | 2.035× | 2.03× |
| sealed lanes | 113.703 | 300 000 | 2.638× | 2.64× |
| package-artifacts | 79.273 | 180 000 | 2.271× | 2.27× |
| swift-readonly | 79.902 | 180 000 | 2.253× | 2.25× |
| printed-record | 188.530 | 420 000 | 2.228× | 2.23× |
| value-type | 353.652 | 720 000 | 2.036× | 2.04× |
| std-string | 141.776 | 300 000 | 2.116× | 2.12× |

Every budget is the smallest clean value ≥ 2× its measurement (2×28 146 =
56 292 → 60 000; 2×353 652 = 707 304 → 720 000; etc.). The §5 contention
ceiling cross-check also recomputes (8×36.6 = 292 < 420; 15×36.6 = 549 < 720;
5×36.6 = 183 < 300 ×2).

**Measured costs are inherited** — I could not re-measure in a quiet window
(tree busy throughout). Corroboration under contention: my runs came in at
1.04–1.7× the quiet costs (§4 below), consistent with the report's 1.3–1.5×
contention band and inside every budget.

**Not tuned until green — no counter-example found.** Every budget sits at
≈2× measurement, none at "just above the observed pass"; the two closest to
the 2× floor are exactly the two most expensive tests, where rounding to a
clean value bites. No test's cost is dominated by avoidable work: the
per-invocation cost is the reflaxe macro-library recompile (source haxelib,
no bytecode cache — [inherited] machine context, consistent with every
single-run test costing 22–29 s regardless of what it asserts). I found no
budget raised without a measurement behind it and no case where patience was
used to paper over excessive in-test work.

## 2. Diff audit — CONFIRMED

`git diff 1877e103..4c292c64` (the four commits), removed lines classified
exhaustively — 25 total:

```
10 × "  });"  8 × "});"                       closers gaining the timeout 3rd arg
 2 × "}, 15000);"  2 × "}, 120_000);"  1 × "}, 120000);"
 1 × "}, 60_000);"  1 × "  }, 60_000);"   old explicit budgets raised
```

Nothing else removed: no `expect`, no test name, no `skip`/`todo`, no logic.
Added lines are budget values plus comment blocks whose stated measurements
match §4. 19 files, all under `tests/`. The 5 s-class tests previously had no
explicit timeout (closers replaced), so bun's 5000 ms default applied —
consistent with the baseline markers.

## 3. Cascade causality — CONFIRMED (8/8); one attribution typo in report §1

Baseline log `dc-warn/out/collect-fix/evidence/proof-run.log`: every
`# Unhandled error between tests` mapped to the nearest preceding
`this test timed out after` line and file:

| unhandled line | preceding timeout (line, file) | report §1 says | agrees? |
|---|---|---|---|
| 66 | 64, strict-output | strict-output | ✓ |
| 87 | 85, strict-output | strict-output | ✓ |
| 108 | 106, strict-output | strict-output | ✓ |
| 314 | 312, package-artifacts | package-artifacts | ✓ |
| 365 | 363, sealed-variants | sealed-variants | ✓ |
| 386 | 384, sealed-variants | sealed-variants | ✓ |
| 525 | **523, extern-bindings** | **printed-record** | ✗ |
| 741 | 739, swift-readonly-boundary | swift-readonly | ✓ |

All 8 cascades immediately follow (2 lines later) a timeout in the same file
— causal claim holds 8/8. But line 525 follows the **extern-bindings**
timeout, not printed-record (printed-record's line-35 timeout produced no
cascade). The commit message and §2 attribute it correctly ("strict-output
×3, extern ×1"), so this is a §1 typo, not a wrong conclusion. I also count
25 timeout markers in the main run, matching the report's corrected split
(18×5 s, 2×15 s, 2×60 s, 3×120 s) versus BASELINE-FAILURES.md's "26".

## 4. Changed tests pass — CONFIRMED (my runs, contended)

Scoped `bun test <file>` with the final committed budgets, exit code captured
directly (`evidence/V-*.rc`):

| file (class) | rc | result | changed-test timing vs budget |
|---|---|---|---|
| tests/ts/extern-bindings.test.ts (5 s) | 0 | 2 pass / 0 fail / 0 unhandled | 26.6 / 27.7 s vs 60 s |
| tests/ts/static-state.test.ts (15 s) | 0 | 6 pass / 0 fail | 37.7 s vs 60 s |
| tests/ts/sealed-variants.test.ts (5 s + 15 s) | 0 | 4 pass / 0 fail | lanes 155.4 s vs 300 s |
| tests/ts/std-string.test.ts (120 s) | 0 | 7 pass / 0 fail | nullable 198.7 s vs 300 s |
| tests/ts/package-artifacts.test.ts (60 s) | 1* | cargo/Pub **pass** 108.7 s vs 180 s | *file has an unrelated pre-existing failure, §5 |
| tests/swift-readonly-boundary/readonly-boundary.test.ts (60 s) | 0 | 1 pass / 0 fail | 85.4 s vs 180 s |

21 changed tests exercised across all four classes; all pass under *contended*
load (1.04–1.7× quiet cost) — margins hold. Zero `Unhandled error between
tests` in any of my runs, as the fix report predicts. Not re-run by me:
value-type (720 s) and printed-record (420 s) with final budgets (see Not
verified), and the 5 s-class strict-output/precision family — their Phase-B
generous-budget passes and Phase-C logs (`C-*.log/.rc`, five files, all rc 0)
are **[inherited]**.

## 5. Nothing else regressed — CONFIRMED; one pre-existing knife-edge flagged

Controls (files/tests untouched by the commits, passing in the baseline):

- `tests/bundle-child-evidence/bundle-child-evidence.test.ts` — all pass, rc 0.
- `tests/ts/vector.test.ts` — 4 pass, rc 0 (35 ms).
- 6 untouched sibling tests inside package-artifacts — all pass in my run.

**Flag (pre-existing, not caused by the reviewed commits):**
`package artifact emission > two generations of the same inputs produce
byte-identical artifacts`. Untouched by the four commits; its 420000 ms
budget already existed at 1877e103 (pre-commit file line 345). The baseline
pass took 414.8 s — 98.8% of budget, a knife edge. Under current contention
it failed twice for me: run 1 completed at 323.5 s but the byte-diff
assertion at `tests/ts/package-artifacts.test.ts:344` failed (real data diff,
380 vs 480 bytes, not a timing failure — plausibly a shared-tree collision;
the tracked fixture was found clobbered to `Test.equals`=0 by a concurrent
seat during this run and I restored it, `RESTORED` in `V-pkg-artifacts.rc`);
run 2, scoped to just this test (`V2-byteidentical.*`), hit the 420 s timeout
at 420.0 s. Either way this test currently cannot pass on the busy tree — a
latent defect outside the change's scope that the report does not mention
(baseline §1 counted this file's failures before the fix; after the fix
nobody re-examines the untouched siblings). Needs a quiet-window rerun and,
likely, its own budget-or-determinism task.

## Not verified / blockers

- **Quiet-window re-measurement of any cost** — tree busy for my entire
  window; §4 quiet numbers inherited, corroborated only under load.
- **value-type (720 s) and printed-record (420 s) with final budgets** — not
  re-run (≥3–6 min each under contention); passing status rests on the
  fixer's Phase-B runs at 900 s and Phase-C logs [inherited].
- **Full 19-file Phase C "64 pass / 0 fail"** — the fix report's own §8 is
  PENDING; I sampled 6 files.
- **Byte-identical test root cause** — determinism vs shared-tree collision
  indistinguishable without a quiet window (§5).

## Bottom line

The change does what it says and only what it says: 25 tests get explicit,
individually measured, ≈2× budgets; the diffs contain nothing but budgets and
comments; the cascade story is causal 8/8 (one file-attribution typo in
report §1: line 525 is extern-bindings, not printed-record); every sampled
changed test genuinely passes, including under contention, and the unhandled
errors are gone. No timeout was raised without a measured basis and no test's
cost is dominated by cacheable work. Loose ends, neither blocking the
commits: the §1 typo, and the pre-existing knife-edge `byte-identical`
packaging test, which is currently red under load and warrants its own task.
