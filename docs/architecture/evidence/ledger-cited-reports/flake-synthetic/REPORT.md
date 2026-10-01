# REPORT - Controlled synthetic verification of the flake attribution class

**SYNTHETIC VERIFICATION - in one plain sentence: this demonstrates the
classifier's behaviour on a flake-shaped input and is NOT evidence that a flake
occurred in the wild.** The underlying real end-to-end suite run was green
(1035 pass / 0 fail, 304 files, 2344 s); the flake class was NOT-EXERCISED in
it, and this supplement exists only because the ruling requires the class to be
demonstrated before either unmerged repair may land.

- Plan recorded before any run: `00-PLAN.md` (recorded UTC 2026-09-30T21:49:11Z;
  addendum 21:56Z after the coordinator's worktree-restore notice, still pre-run).
- Repo pinned: `boring-wt-architecture`, branch `ci/collected-suite-failure-attribution`,
  plan pinned `ed55d736`; after the notice re-confirmed at `6322af89`
  (`git diff ed55d736..6322af89` touches neither `.github/workflows/ci.yml` nor
  `tests/ts/package-artifacts.test.ts`; byte-identity assertion verified at :338,
  and `:351` in `2aadcb69^` was verified from the committed blob). A later doc-only
  commit `4c838e2f` was also diff-checked against the same two paths: unchanged.

## 1. Route chosen, and why
Splice of genuine parts, in an isolated copy - not hand-written, not a mutated
tracked fixture:
- The Buffer-diff shape is real bun 1.3.13 (the CI's bun) output captured from an
  earlier isolated-copy run (`dc-warn/out/ci-attribution/scratch/bufshape.log`,
  sha256 c00ecd42...): two real Buffers differing by 40 real bytes, rendered by
  bun itself. Shape stability cross-checked by re-rendering with bun 1.4.2
  (`evidence/bun142-buffer-diff.raw.txt`).
- The exit-code assertion block for V2 is real captured 1.3.13 output for exactly
  this test (`.../scratch/control-A-...log`, sha256 1e8d2ebb...), code frame
  re-anchored to HEAD line numbers.
- A true end-to-end byte difference would require running the 39-minute suite and
  changing compiler behaviour mid-test (an implementation change, which the ruling
  forbids), so this is the most defensible scoped route.
- Stack paths retargeted to the real assertion sites
  (`tests/ts/package-artifacts.test.ts:338` / `:334`, or the unrelated gen-test
  file); the classifier matches test names/paths, never line numbers.
- Every filename in the tree carries `SYNTHETIC`.

## 2. The report step ran verbatim from the committed workflow
Extracted with `Bun.YAML.parse` from the committed blob
(`git show HEAD:.github/workflows/ci.yml`, script `evidence/extract-step.ts`) into
`evidence/step-report-from-yaml.sh` (17274 chars, sha256 ec51a791...). Each run:
cwd = repo root, `GITHUB_STEP_SUMMARY` set to a per-run file, `bash -e` on the
extracted step, exit code read directly from the same shell (never through a
pipe). The stale-log trap is closed structurally: `out/collected-suite.log` is
deleted before each install (`test ! -e` enforced), the variant installed, its
sha256 taken before and after the step, and the file deleted afterwards. Every
run's `log-unchanged-during-run.txt` records the identical sha256, so the report
provably read only the log that this run installed - no stale `out/` log was
reachable.

## 3. The four discriminations (counts and residual, item by item)
Expected values were fixed in `00-PLAN.md` before the run; all matched.

| run | log installed at `out/collected-suite.log` | assertion | timeout | flake | t-cascade | unattr. | summary fail | residual | exit | ::warning:: |
|-----|---|---|---|---|---|---|---|---|---|---|
| V0 baseline | unmodified green log copy | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | none |
| V1 flake | byte-identity test + Buffer diff at `tests/ts/package-artifacts.test.ts` | 0 | 0 | **1** | 0 | 0 | 1 | **0** | 0 | none |
| V2 same test, other cause | byte-identity test, its own exit-code assertion (`expect(a.exitCode).toBe(0)`), no Buffer payload | **1** | 0 | **0** | 0 | 0 | 1 | **0** | 0 | none |
| V3 Buffer diff elsewhere | Buffer diff in `reference/ts/gen-tests/tests/CloneDeriveGapTests.test.ts` | **1** | 0 | **0** | 0 | 0 | 1 | **0** | 0 | none (ATTR_BUFFER_DIFF=1 surfaced as *not the flake*) |
| V4 residual | V1 with summary `2 fail` vs 1 recap entry | 0 | 0 | 1 | 0 | 0 | 2 | **1** | 0 | **YES** |

Reading, in both directions:
1. The synthetic byte-identity failure IS attributed to flake: V1's summary reports
   `npm-artifact non-determinism | 1`, "Matched on test identity ... **and** the
   binary-diff shape", `Rendered diff lines: - Expected  - 40 + Received  + 40`,
   and no other class rises (all 0). Exit 0 with residual 0.
2. The same test failing for another reason is NOT attributed to flake: V2 (exit-code
   assertion on the identical test id) lands in `real assertion failure | 1`, flake 0.
   The deliberate "id alone is not enough" design holds.
3. A Buffer diff in an unrelated file is NOT the flake: V3 counts it as an assertion
   failure; the report explicitly says the binary diff "is present in this log, but
   not at the artifact byte-identity assertion, so it is **not** counted as the known
   artifact flake."
4. Counts reconcile with residual 0 on V0-V3, and V4's deliberately non-zero
   residual (1 of 2) raises exactly:
   `::warning::1 of 2 failing test(s) were classified; residual 1 is unattributed - ...`

No unexpected class increased in any run; no `::error::` appeared; the warning and
domain gates stayed at baseline. Per-run raw data: `evidence/run-*/`
(`log-installed-at-LOG-path-SYNTHETIC.log`, `step-stdout-SYNTHETIC.log`,
`step-summary-SYNTHETIC.md`, `step-exit-code.txt`, before/after sha256).

## 4. Isolation / undo evidence
- The only repo path written was `out/collected-suite.log`, which is gitignored
  (`.gitignore:2`); it was deleted after the runs (`test ! -e` confirmed).
- `git status --porcelain` after the runs shows no entry from this exercise;
  the tracked tree was never modified.
- Fixture guard: `grep -c 'Test.equals' samples/boring/MathNaNTestSupport.hx` = 5 (unchanged).
- No test was weakened, deleted or skipped; no `continue-on-error`; the workflow,
  tests, the two unmerged repairs and the ledger were not touched.

## 5. SYNTHETIC labelling
Plan, this report, the evidence README (`evidence/00-SYNTHETIC-README.txt`), every
variant filename, and the committed record doc are labelled SYNTHETIC. Repeated
plainly: this demonstrates the classifier's behaviour on a flake-shaped input and
is not evidence a flake occurred. Attribution is not waiver: a flake-class red is
still a red.

## 6. Anything unverified
- bun 1.3.13 could not be re-invoked here (`nix develop` hit a read-only
  `~/.cache/nix` fetcher-cache SQLite, a shared-machine state issue); the Buffer
  shape therefore comes from the retained genuine 1.3.13 capture, cross-checked
  on bun 1.4.2 (same shape). The classifier's rules are shape-based, and both
  renderings satisfy them identically.
- The `8237 expect() calls` line in the synthetic logs was left unadjusted when
  pass/fail counts were edited; the classifier does not parse that line (and no
  gate reads it), noted for completeness.
- V3's code-frame lines reproduce the unrelated file's real source lines but were
  re-anchored like the stack lines; only the classifier-relevant lines (error
  header, Buffer JSON, diff header, stack path) are load-bearing.
