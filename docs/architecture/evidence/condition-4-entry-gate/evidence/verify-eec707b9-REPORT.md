# Claim-versus-commit verification: ledger condition 4, commit `eec707b9`

- Verifier: independent check seat (not the implementer).
- Repo: `boring-wt-architecture`, HEAD at check time: `3ab7542b` ("docs(architecture): record condition 4 resolved and progress on contract 3's restoration").
- All exit codes and re-runs below are my own measurements (`[EXEC]`); the implementing seat's report was not used as evidence.
- Raw logs: `evidence/` (commit dump, spec excerpt source, three hxml variants, per-run stdout/stderr, bun test log).

## Per-claim verdicts

| # | Claim | Verdict | Evidence (mine) |
|---|---|---|---|
| 1 | Verdict is "stale expectation, not a product defect", resting on spec 24 Ruling 5 stopping only by-name+emitted and requiring relative to be accepted | **CONFIRMED** `[EXEC]`/`[CODE]` | Read `docs/specs/features/24-package-shell.md`, Ruling item 5 (lines ~138-163). It says: "a compilation combining a by-name runtime import with an emitted manifest stops with `package shell requires a relative runtime import: a by-name runtime import names a package the manifest cannot declare; pass runtime-import a relative specifier or package-shell none`. When `runtime-import` carries a relative specifier, the compiler computes the per-file relative path to the runtime entry" — i.e. by-name+emit must stop, relative must be accepted. The guard at `packages/compiler/reflaxe/ts/tscompiler/Compiler.hx:580-584` enforces exactly that (fires only when `PackageShell.enabled()`, `anyRuntimeUsed()`, import non-null and non-relative). The ledger's characterization matches the spec text. |
| 2 | `git show eec707b9` touches only `tests/ts/package-shell.test.ts` + supersession note in `BASELINE-FAILURES.md`; no assertion weakened | **CONFIRMED** `[EXEC]` | Stat: exactly those 2 files, +20/-3. Test-file deletions are only the old comment (2 lines) and the literal `out.replace("-D runtime-import=@boring/runtime", ...)` replaced by an equivalent regex rewrite; the by-name test additionally gained `runtimeImport: "@boring/runtime"` (a pin, strengthening the scenario). Assertions (`exitCode).not.toBe(0)`, `stderr).toContain("package shell requires a relative runtime import")`) unchanged; no test skipped/deleted; no matcher loosened. BASELINE-FAILURES.md change is prose-only. |
| 3 | Mechanism: test written at `52044ed1` while hxml carried `-D runtime-import=@boring/runtime`; `2bd609b9` changed it to `./runtime` without updating the test; helper matched only the historical value | **CONFIRMED** `[EXEC]` | `git show 52044ed1:examples/ts.hxml` line 14: `-D runtime-import=@boring/runtime`. `git log -S "runtime-import=@boring/runtime" -- examples/ts.hxml`: only `19d6dbf3` (introduced) and `2bd609b9` (removed), and `2bd609b9`'s diff shows `--D runtime-import=@boring/runtime` → `+-D runtime-import=./runtime`. `git merge-base --is-ancestor 52044ed1 2bd609b9`: yes. At `2bd609b9` the test still had no `runtimeImport` option in the by-name scenario and the helper `out.replace("-D runtime-import=@boring/runtime", ...)` was a no-op against `./runtime` — the scenario silently became relative+emit, which my own measurement (claim 4) shows exits 0, so the `not.toBe(0)` assertion fails deterministically. **The mechanism accounts for the failure.** Limitation: neither the author nor I re-executed the test at `52044ed1`/`2bd609b9` (inspection via `git show` only). This leaves "the test passed before `2bd609b9`" as inference, not measurement; it does not weaken the causal account of the failure, which I re-measured directly (rel+emit → exit 0 fails the assertion). |
| 4 | Discriminating readings: rel+emit → 0; by-name+emit → 1 with sanctioned message; by-name+none → 0 | **CONFIRMED** `[EXEC]` (my own runs) | I built three hxml variants from `examples/ts.hxml` myself (evidence/hxml-*.hxml), ran `haxe` with cwd = tree root, exit codes captured directly (no pipe): rel-emit **exit 0** with `package.json` emitted in the ts-output tree; byname-emit **exit 1**, stderr: `package shell requires a relative runtime import: a by-name runtime import names a package the manifest cannot declare; pass runtime-import a relative specifier or package-shell none` (exact match to the spec's sanctioned message); byname-none **exit 0**, no manifest. One anomaly in my first attempt (a run wrote the manifest after I first listed the tree) resolved on a clean deterministic rerun: all three readings reproduce as claimed. |
| 5 | Full file passes 6 pass / 0 fail after the fix | **CONFIRMED** `[EXEC]` | `bun test tests/ts/package-shell.test.ts`: **6 pass, 0 fail**, 30 expect() calls, bun exit 0 (176s). Flake counter `grep -c 'Test.equals' samples/boring/MathNaNTestSupport.hx` = **5 before and 5 after** every run. |

## Claim's own limits (the flagged gap)

The author flagged not re-executing at `52044ed1`. In my judgment this does **not** materially weaken claim 3: the failure mechanism (rel+emit → exit 0 → `not.toBe(0)` fails) is the load-bearing part and I re-measured it directly on the current tree; the historical states were verified by `git show`/`git log -S`/`merge-base` and are unambiguous. What is *not* proven by anyone is the negative history ("the test was green until `2bd609b9`"); that is well-supported inference, not a measurement.

## Four-requirement verdict (the ruling)

| Requirement | Status |
|---|---|
| 1. Traceable commit hash | **Met.** Entry names `eec707b9`; full hash `eec707b9b09ccabdc7541b74174c6d8cf1e9ef0e` exists and matches the described content. |
| 2. Clean working-tree proof | **NOT evidenced.** The entry carries no clean-tree snapshot, and at verification time the tree is not clean (pre-existing/unrelated modifications to `tests/ts/package-artifacts.test.ts` — another seat's, untouched — and `.github/workflows/ci.yml`, which appeared during my session, also not mine). I cannot attest the tree state at commit time; no proof exists in the entry. |
| 3. Independently exported content | **NOT evidenced.** The entry points at repo files only; no independently exported artifact (archive/checksum) is referenced or produced. |
| 4. Claim-versus-commit check by someone other than the implementer | **Met by this report.** I re-derived claims 1-5 from the spec, git history, and my own executions; all five confirmed. |

**Overall verdict: condition 4's technical claims are all verified, but the entry does NOT satisfy the ruling's four requirements — requirements 2 (clean working-tree proof) and 3 (independently exported content) are missing. The entry should not carry a "RESOLVED / on the line" status until a clean-tree proof and an independent export are attached (or the ledger records their absence explicitly).**

## Not verified

- Test execution at `52044ed1` and at `2bd609b9` (not performed by anyone; inspection was via `git show`). Blocker: would require checking out historical states, which the task's do-not-modify rules and shared-worktree conditions rule out.
- Clean-tree state at the moment `eec707b9` was committed (no snapshot exists; current tree has unrelated foreign modifications).
- Independence of the exported content requirement — nothing to verify; it does not exist.
- Conditions 1-3 of contract 3 — explicitly out of scope per instruction.
- Provenance of the `.github/workflows/ci.yml` modification I observed mid-session (not mine; I did not touch or investigate it further).
