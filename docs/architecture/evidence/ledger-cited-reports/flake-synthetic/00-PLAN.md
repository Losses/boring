# PLAN - recorded BEFORE the run - SYNTHETIC VERIFICATION, NOT A REAL FLAKE
Recorded (UTC): 2026-09-30T21:49:11Z
Repo state pinned at: boring-wt-architecture ed55d736 (git log --oneline -1)
Status: this entire exercise is a **controlled, auditable injection/fixture run**
(supplement required by the management ruling). It demonstrates the classifier's
behaviour on a flake-shaped input. It is **not** evidence that a flake occurred.

## 1. Injection point, input, expected classification, isolation/undo

Injection point: the file the committed report step reads, `LOG=out/collected-suite.log`,
i.e. `<repo>/out/collected-suite.log`. `out/` is gitignored (.gitignore:2), so the
tracked tree is never modified. Before each run any prior file there is deleted
(the stale-log trap: a leftover `out/collected-suite.log` must never be readable
by the step), the synthetic variant is installed, its sha256 recorded, and the
step is run immediately against exactly that file.

Input: five log variants derived from the REAL green end-to-end log
`dc-warn/out/e2e-run/evidence/collected-suite.log`
(sha256 4953a63a48e263f7b88e35e2a00b4c13664eb4c768f07d3da6f15fec36d2d0ed,
1035 pass / 0 fail, 304 files). Each variant injects exactly one failure block
whose text is genuine bun 1.3.13 rendering captured from real runs (not
hand-written):
- Buffer toEqual diff shape: retained real capture `dc-warn/out/ci-attribution/scratch/bufshape.log`
  (sha256 c00ecd42...), byte difference between two real Buffers rendered by bun 1.3.13.
- exit-code assertion block for the same test: retained real capture
  `dc-warn/out/ci-attribution/scratch/control-A-artifact-test-fails-without-byte-diff.log`
  (sha256 1e8d2ebb...), re-framed to HEAD line numbers.
Cross-check: the same shape re-rendered locally with bun 1.4.2 matches
(`evidence/bun142-buffer-diff.raw.txt`), so the shape is bun-stable.
Stack lines are retargeted to the real assertion sites in
`tests/ts/package-artifacts.test.ts` (byte-identity assertion at :338 at HEAD
ed55d736; exit-code assertion at :334) or to an unrelated gen-test file. The
classifier matches test names/paths, never line numbers, so retargeting only
restores fidelity; it is disclosed here.

Variants and EXPECTED classification (expected values fixed BEFORE the run):
| id | log | expect flake | expect assertion | expect timeout | expect cascades | summary fail | residual | expect ::warning:: |
|----|-----|---|---|---|---|---|---|---|
| V0 baseline | unmodified green log | 0 | 0 | 0 | 0 | 0 | 0 | no |
| V1 flake | flake id + Buffer diff at tests/ts/package-artifacts.test.ts | 1 | 0 | 0 | 0 | 1 | 0 | no |
| V2 same-id-other-cause | flake id, exit-code assertion, no Buffer payload | 0 | 1 | 0 | 0 | 1 | 0 | no |
| V3 other-file-buffer-diff | Buffer diff in reference/ts/gen-tests CloneDeriveGapTests | 0 | 1 | 0 | 0 | 1 | 0 | no (ATTR_BUFFER_DIFF=1 reported as not-the-flake) |
| V4 residual | V1 with summary `2 fail` vs 1 recap entry | 1 | 0 | 0 | 0 | 2 | 1 | YES |

Report step: extracted VERBATIM via `Bun.YAML.parse` from the committed blob
(`git show HEAD:.github/workflows/ci.yml`), run with `bash -e`, cwd = repo root,
`GITHUB_STEP_SUMMARY` set to a per-run file, exit code captured directly from
the same shell (never through a pipe).

Isolation / undo:
- nothing under version control is touched: only `<repo>/out/collected-suite.log`
  (gitignored) is written by this exercise; `git status --porcelain` diffed
  before/after must show no new entries from me.
- after all runs, `<repo>/out/collected-suite.log` is deleted; sha256 of the
  installed log is recorded before each run so the step provably read only the
  log this run installed (stale-log trap closed).
- guard checked after runs: `grep -c 'Test.equals' samples/boring/MathNaNTestSupport.hx` must stay 5.

## 2. Route chosen and why
Splice-of-genuine-parts, not hand-writing and not a mutated tracked fixture:
- a genuine byte difference between two real Buffers, rendered by the real bun
  1.3.13 (CI's version), is captured text from a retained isolated-copy run - so
  every classifier-relevant line (`error: expect(received).toEqual(expected)`,
  the `"type": "Buffer"` payload, the diff header) is real bun output, not prose;
- a true end-to-end byte difference cannot be produced here without running the
  39-minute suite and without changing compiler behaviour mid-test (an
  implementation change, which the ruling forbids), so the isolated-capture
  splice is the most defensible scoped route;
- the artifact naming carries SYNTHETIC in every filename.

## 3. Non-goals
No merge, no implementation change, no test change, no workflow change, no
ledger edit, no touching other seats' in-flight files
(docs/architecture/GATE-LEDGER.md, package.json, tools/gate-proof/ are others'
uncommitted work - excluded from any commit).

## ADDENDUM (still BEFORE any run; recorded UTC 2026-09-30T21:56Z)
A coordinator notice reported the shared worktree was briefly switched and
restored. Re-confirmed after the notice: branch `ci/collected-suite-failure-attribution`,
HEAD `6322af89` (ed55d736 is its ancestor), fixture grep -c 'Test.equals' = 5,
and `git diff --stat ed55d736 HEAD -- .github/workflows/ci.yml
tests/ts/package-artifacts.test.ts` is empty (byte-identity assertion still
:338). All reads used the correct line; the report step is extracted from
`git show HEAD:.github/workflows/ci.yml` (= 6322af89).
