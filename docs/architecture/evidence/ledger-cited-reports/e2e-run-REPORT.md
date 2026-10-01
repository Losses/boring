# E2E collected-suite run — contract 3 evidence (2026-09-30)

First real end-to-end CI-shaped run of the collected suite at HEAD
`9388aa62a7f8678d6297c200ff0198cefcf55b95` (branch `ci/collected-suite-failure-attribution`),
carrying the unmerged repairs `2aadcb69` (npm artifact determinism) and `4f80322c` (CI failure
attribution). Everything below is measured from this run's own artifacts in `evidence/`.

## 1. Preconditions observed (before start, 16:40:34–04:00)

- No suite/compiler processes running: `ps` sweep for `bun|haxe|hl|node|tsc|haxelib|neko` showed
  only the desktop environment's own background apps (IDE language servers, Steam, browser
  helpers) — no test runner, no haxe compiler, no concurrent writer. Run was exclusive.
- Working tree clean: `git status --porcelain` empty (`evidence/git-status-before.txt`).
- Fixture intact: `grep -c 'Test.equals' samples/boring/MathNaNTestSupport.hx` = **5**
  (`evidence/fixture-before.txt`).
- HEAD and branch verified (`evidence/head.txt`).

## 2. Pipeline as run, with substitutions

Stage order and exit codes (raw per-stage logs in `evidence/`, codes in `stage-exits.txt`;
every exit code read directly from `$?` after a direct file redirect — never through a pipe):

| stage | rc | window (−04:00) |
|---|---|---|
| `bun install` | 0 | 16:41:36 → 16:41:36 |
| `bun run gen:ts` … `gen:dart` (all 8 `haxe` generation scripts; `gen:vector` is not in the CI prelude line) | 0 ×8 | 16:41:36 → 16:46:15 |
| `bun run test` (collected suite) | **0** | 16:46:15 → 17:25:20 (2344.66 s) |

Substitutions, named (no GitHub runner here):

- CI's `nix develop -c bash -c '...'` wrappers → run directly with the chainA `PATH` env
  (`dc-warn/out/chainA-fixed-rerun/evidence/env.json`), cwd = tree root for `haxe` (repo-local
  `.haxelib`). `nix` exists on this host; the PATH contract is the sanctioned toolchain here.
- CI's `sudo sysctl kernel.apparmor_restrict_unprivileged_userns=0` and
  `nix-store --import < nix-closure.nar` → **not performed** (no approval path for sudo in this
  session; no runner cache to restore). Swift tests passed anyway (rc 0).
- Report step: the committed step body was extracted verbatim from `.github/workflows/ci.yml`
  (only dedent + `LOG=` pointed at this run's log: `evidence/report-step-body-e2e.sh`), run with
  `GITHUB_STEP_SUMMARY` → `step-summary.md`, `tee` → `report-step-stdout.log`.
- **Recorded misstep (corrected, kept for audit):** the first report-step invocation used the
  script's hardcoded `LOG=out/collected-suite.log`, which is a *stale* file from an earlier run
  (Sep 30 15:44, 8155 bytes — a red run) and produced a bogus "7 fail, assertion 7" table.
  That invocation and its output are retained as
  `evidence/report-step-stdout.misdirected-at-stale-out-log.log`; every number below comes from
  the regenerated, clean run against `evidence/collected-suite.log` only.

## 3. The run's own numbers

```
 1035 pass
    0 fail
Ran 1035 tests across 304 files. [2344.66s]
```

Suite exit code: **0** (green). Collected domain per the report step: 249 reference/ts +
50 tests/ts + 5 single-file dirs = 304 files — the full domain, prelude included (not the
shrunken 54/55-file domain). Generated-tree warning line count: **0** (= baseline; the report
step emitted no `::warning::` and no `::error::`; `report-step-stdout.log`).

## 4. Failure attribution applied to the real log (committed rules, verbatim)

| class | count |
|---|---:|
| real assertion failure | 0 |
| environment / timeout | 0 |
| npm-artifact non-determinism | 0 |
| timeout cascade | 0 |
| unattributed error | 0 |

- Reported fail count: **0**. Attributed: 0. **Residual: 0.** Zero, not smoothed: there are
  literally zero `(fail)` lines, zero timeout markers, and zero `# Unhandled error between tests`
  blocks in the raw log (`evidence/collected-suite.log`), so the `::warning::` path (non-zero
  residual) correctly did not fire.
- The attribution rules were exercised against the log by the committed step itself
  (`rc=0`); the run is green, so no failure existed to classify.

## 5. Five ruling conditions, item by item

1. **Every failure in an attributed class or explicit `unattributed`** — **PASS** (vacuously):
   fail count 0; all five class counters are 0; nothing was left over.
2. **Class counts reconcile to fail count with zero residual** — **PASS**: 0 = 0, residual 0;
   no `::warning::` was needed and none was emitted (checked in `report-step-stdout.log`).
3. **npm-artifact flake: exercised or not** — **NOT-EXERCISED.** The target test
   `package artifact emission > two generations of the same inputs produce byte-identical
   artifacts` **passed** at `collected-suite.log:214` in 358384.89 ms (~358 s of its 420 s
   budget, consistent with the baseline's ~366 s). `ATTR_BUFFER_DIFF = 0` and
   `ATTR_FLAKE_SHAPE = 0`: no `expect(received).toEqual(expected)` over a `"type": "Buffer"`
   payload anywhere in the log, hence no Buffer-diff shape at
   `tests/ts/package-artifacts.test.ts`. **No flake was witnessed in this run; this report does
   not claim one.** The class was available (the test ran) but the independent signal was never
   triggered, so commit `2aadcb69`'s flake-catching behavior remains verified analytically only.
4. **Exit status, raw log, report artifacts, provenance independently checkable** — **PASS**:
   suite rc 0 recorded outside any pipe in `stage-exits.txt`; raw log `evidence/collected-suite.log`
   (sha256 `4953a63a…d0ed`); report output `step-summary.md` and `report-step-stdout.log`
   (sha256 `20d22def…9035`); HEAD `9388aa62a7f8678d6297c200ff0198cefcf55b95`
   (`evidence/head-after.txt`).
5. **Fixture and tree integrity after the run** — **PASS**: `grep -c 'Test.equals'` = **5**
   after (`evidence/fixture-after.txt`); fixture blob
   `f3849049fe96d32cfed77bce2cea0977822af3f4` = `HEAD:samples/boring/MathNaNTestSupport.hx`
   (`evidence/fixture-blob.txt`); `git status --porcelain` empty after
   (`evidence/git-status-after.txt`); HEAD unchanged. The run modified **no tracked file**;
   all outputs live under `dc-warn/out/e2e-run/`.

## 6. Verdict

A complete, exclusive, CI-shaped run (prelude + suite + committed report step) finished green:
1035/1035 pass, 304 files, 2344.66 s, exit 0, zero warnings, zero residual, fixture and tree
untouched. Contract 3's count evidence exists and is green. Condition 3 is explicitly
**NOT-EXERCISED**: this run did not witness the npm-artifact flake, and per the ruling that
fact is recorded as such — not upgraded into a pass and not into a failure.

### Toolchain
bun 1.3.13, haxe 4.3.7, Linux 7.1.4-cachyos, 16 cores (`evidence/toolchain.txt`).
