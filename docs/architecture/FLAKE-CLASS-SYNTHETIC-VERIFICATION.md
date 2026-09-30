# Flake attribution class - controlled synthetic verification

**SYNTHETIC VERIFICATION.** This demonstrates the classifier's behaviour on a
flake-shaped input and is **not** evidence that a flake occurred in the wild; the
first real end-to-end run was green (1035 pass / 0 fail) and the flake class was
NOT-EXERCISED in it. This file is the supplement the management ruling requires
(a controlled, auditable injection/fixture run) and nothing else: no merge, no
implementation change, no test change.

## What was fixed before the run
Injection point, input, expected classification and the isolation/undo method are
recorded in `dc-warn/out/flake-synthetic/00-PLAN.md`, timestamped before the run.

## What ran
The `collected-suite` report step, extracted verbatim from the committed workflow
blob (`Bun.YAML.parse` over `git show HEAD:.github/workflows/ci.yml`, 17274
chars), was run five times with `bash -e`, cwd = repo root, `GITHUB_STEP_SUMMARY`
set, exit codes read directly (never through a pipe), each time against a
synthetic log installed at exactly `out/collected-suite.log` (gitignored) that
was deleted before each install and hash-verified unchanged during the run - so
the report provably read only the log of that run, never a stale one.

## Results (all four discriminations, expected values pre-recorded, all matched)

| run | injected input | flake class | assertion | other classes | residual | `::warning::` |
|---|---|---|---|---|---|---|
| V0 | none (green baseline copy) | 0 | 0 | all 0 | 0 | none |
| V1 | byte-identity test + real bun-rendered Buffer diff | **1** | 0 | all 0 | 0 | none |
| V2 | same test id, its own exit-code assertion failure | **0** | 1 | all 0 | 0 | none |
| V3 | Buffer diff in an unrelated gen-test file | **0** | 1 | all 0 (diff surfaced as *not the flake*) | 0 | none |
| V4 | V1 with summary `2 fail` vs 1 classified | 1 | 0 | all 0 | **1** | **raised** |

This shows the classification in both directions: the flake shape at the artifact
byte-identity assertion is attributed to flake and nothing else rises; the same
test failing for a different reason, and a Buffer diff elsewhere, are NOT
attributed to flake; counts reconcile with residual 0; a non-zero residual raises
the warning. Attribution is not waiver: every classified failure is still a
failing test.

## Route and isolation
Failure-block text is genuine bun 1.3.13 output captured from earlier isolated
runs (Buffer diff from `dc-warn/out/ci-attribution/scratch/bufshape.log`; the
exit-code block from that seat's control A), spliced onto a copy of the real
green log with stack paths retargeted to the real assertion sites
(`tests/ts/package-artifacts.test.ts:338` at the pinned revisions, verified). A
genuine end-to-end byte difference would require the 39-minute suite plus a
mid-test implementation change, which the ruling forbids. The only repo path
written was the gitignored `out/collected-suite.log`, deleted after the runs; the
tracked tree was never modified (`git status` clean, fixture guard
`grep -c 'Test.equals' samples/boring/MathNaNTestSupport.hx` = 5).

## Raw evidence
`dc-warn/out/flake-synthetic/` (REPORT.md, 00-PLAN.md, evidence/ with per-run
logs, step extraction, summaries, exit codes and sha256s, all SYNTHETIC-labelled).
