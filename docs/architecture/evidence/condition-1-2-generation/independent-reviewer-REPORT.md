# Claim-versus-commit check — `2aadcb69` (npm artifact determinism, restoring contract 3, conditions 1–2)

**Reviewer:** independent verification seat (not the implementer of `2aadcb69`).
**Reviewed object:** `2aadcb6978d81705379892d2b382671b3458e753`, branch `fix/npm-artifact-determinism`,
"fix(tests): stop mutating a tracked fixture during npm artifact generations" (1 file, +25/-38).
**Author's report:** `dc-warn/out/npm-determinism/REPORT.md` — read, **not** used as evidence.
**Repository state:** nothing in the repository, any worktree, the commit, the ledger or any test was
modified by this check. The live worktree `boring-wt-architecture` sat on
`ci/collected-suite-failure-attribution`, whose HEAD **moved three times while this check ran**
(`c365dbeb` → `0b723fdc` → `4f80322c` → `9274b7a7`, last sampled 2026-09-30T16:25-04:00) and is **not**
the commit under review. That worktree was clean at its own HEAD at every sample, but its HEAD is a
different, actively-rewritten branch. `2aadcb69` is an ancestor of that branch and of
`fix/npm-artifact-determinism` (`0b723fdc`), but **not** of `master` (`cc9957dd`) or `gitbutler/target`
(`378dfdbf`).

**Method.** `git archive 2aadcb69` → `/tmp/verify-2aadcb69/wt-prefix`(parent) / `/tmp/verify-2aadcb69/wt`
(commit); every extracted file re-hashed against its blob oid in the commit tree — **1455 checked,
0 mismatched, 0 missing**. `node_modules/` and `.haxelib/` copied read-only from the live worktree.
`haxe` always run with cwd = tree root. Every number below was produced in those export trees; entry
counts are `tar -tzf | wc -l`, hashes are sha256 of the `.tgz`. Toolchain: haxe 4.3.7, bun 1.3.13,
node v22.23.2, tsc 5.9.3, kotlinc 2.4.10, GNU tar 1.35, 16 cores. Fixture trap honoured: `grep -c
'Test.equals' samples/boring/MathNaNTestSupport.hx` = 5 before and after every run (never hit 0).

## 0. Bottom line

| Claim | Verdict |
|---|---|
| 1 root cause = harness fabricated two input states (405 vs 407) | **CONFIRMED** as state→artifact causality [EXEC]; the *CI occurrence itself* is **NOT witnessed** (see §8) |
| 2 fix removes stub machinery and the module-list filter | **CONFIRMED** [CODE] |
| 3 ≥5 generations, one unique hash, equal to honest pre-fix state | **CONFIRMED** [EXEC] |
| 4 no assertion weakened | **CONFIRMED** [CODE], with a citation-line correction |
| 5 fixture never written; corruption mechanism gone | **CONFIRMED** [CODE + EXEC] |
| Ledger entry satisfies the four-requirement entry gate | **NO** — R1 met, R3 producible but not carried, R2 **not met**, pre-transition three-way check **fails** (§6) |

Where my numbers differ from the author's they are listed in §7; no material difference was found.

## 1. Claim 1 — the two input states, reproduced independently

Driver: `evidence/repro-verify.mjs` (written for this check). It replicates the **post-fix**
`rewriteHxml` (no module-list filter), rewrites `reference/…` to a **fresh temp root per generation**,
appends `-D package-artifacts=emit` and `-D package-tsc=…/tsc`, and — in `stub` mode only — writes the
harness's exact stub bytes to the tracked fixture for the duration of the generation and restores the
pristine bytes afterwards. `FILTER=1` adds back the pre-fix `replaceAll("boring.MathNaNTestSupport\n","")`
so the pre-fix harness shape can be measured too. The only variable between the two states is the
content of `samples/boring/MathNaNTestSupport.hx`.

| input state (fixture content) | generations | entries | tgz sha256 | tgz bytes | `MathNaNTestSupport.*` in tgz | `runtime/test` in tgz |
|---|---|---|---|---|---|---|
| **stub** (`4f910e40…`, 285 B, `Test.equals`=0), pre-fix filter | 3 ([EXEC] `A-prefix-stub.log`) | 407, 407, 407 | `4bb614bc2a3214133ff1cf85a710fbcc494d89557318610ed41f1059227f580c` ×3 | 96427 | present (`.d.ts` 242 B, `.js` 249 B) | absent |
| **real** (committed `1c2acf93…`, 583 B, `Test.equals`=5), any filter | **9** ([EXEC] B/C/E + wt-prefix) | 405 every time | `5b85d7564e03abe9b3fa40976377abb850d6b0bf78c33d690a84f46dd0abc373` every time | 96311 | absent | absent |

Both states are **stably deterministic** (one unique hash per state across every generation), and the
difference between them is **exactly two archive entries** — witnessed as a real entry-list diff
(`evidence/entry-diff-real-vs-stub.txt`):

```
142a143,144
> package/dist/boring/MathNaNTestSupport.d.ts
> package/dist/boring/MathNaNTestSupport.js
```

So the entry set is a pure function of that one input file's content; `407 − 405 = 2` entries and
`96427 − 96311 = 116` compressed bytes. Everything else in the archive is identical, entry order is
sorted in both, and every member date is pinned (`1969-12-31 19:00`, i.e. epoch 0 UTC) — metadata is
not the variable.

**The harness really did fabricate the stub state** ([EXEC]): running the **shipped pre-fix** test file
(parent export) with a 50 ms sampler on the fixture produced, in one run, 557 consecutive samples of
the stub (`4f910e40…`, 285 B, `Test.equals`=0, ≈28 s) and 29 samples of the real fixture, restoring the
real bytes afterwards; that run **passed** (`1 pass, 432 expect() calls, 35.2 s`) while asserting on an
artifact built from the stubbed input. Logs: `evidence/prefix-fixture-sampler.log`,
`evidence/prefix-npm-test.log`.

**Mechanism, checked in the code and in the emitted output** ([CODE] + [EXEC]):
`tscompiler/Compiler.emitNpmArtifact` puts `runtime/test.ts` in `excluded` when `anyRuntimeTestUsed()`,
and `PackageArtifacts.npmCompileSet` then removes every recorded module that imports an excluded path,
iterated to a fixed point. The emitted TypeScript of the module is what differs
(`evidence/mechanism-emitted-module.txt`):

- real fixture → `ts/gen/boring/MathNaNTestSupport.ts` contains `import { Test } from "../runtime/test.ts";` → matched by the closure → dropped → 405;
- stub → the same emitted file imports nothing → not matched → ships → 407.

`runtime/test.ts` is emitted in both states and is excluded from the tgz in both, which also shows
`anyRuntimeTestUsed()` was true in the stub state (other test modules use it) — the flip is entirely
about the importer.

## 2. Claim 2 — the fix removes the stub machinery [CODE]

`git show 2aadcb69` = exactly **2 hunks**, both in `tests/ts/package-artifacts.test.ts`:

- `rewriteHxml`: the line `out = out.replaceAll("boring.MathNaNTestSupport\n", "");` and its comment are
  **deleted**; the module stays in the compile set.
- `runHaxe`: the whole `probe` / `isTs` / `backup` / `hidden` / `stub` / `try…finally` block is
  **deleted** and replaced by a plain `Bun.spawn` (hunk 1: +7/−6; hunk 2: +18/−32; total +25/−38).

Grep of the post-fix file: no `stub`, `backup`, `hidden`, `probe` or restore path anywhere; the string
`MathNaNTestSupport` appears only in comments (lines 45, 66, 69, 70). The remaining `writeFileSync`
calls target `out/<hxml>`, `consumer/package.json` and `consumer/consumer.mjs` — never `samples/`.
**Confirmed: no fixture rewrite, no restore path, no shared-state mutation, no module-list filter.**
The emitter was not touched by the commit (the commit is test-only), which is consistent with claim 3.

## 3. Claim 3 — N-generation determinism after the fix [EXEC]

`evidence/B-postfix-real-5gen.log`, 5 generations, fresh temp root each, same tree/toolchain:

| gen | entries | tgz sha256 | bytes | MathNaNTestSupport | sorted | member dates |
|---|---|---|---|---|---|---|
| 0 | 405 | `5b85d7564e03abe9b3fa40976377abb850d6b0bf78c33d690a84f46dd0abc373` | 96311 | absent | yes | epoch 0 |
| 1 | 405 | `5b85d756…abc373` | 96311 | absent | yes | epoch 0 |
| 2 | 405 | `5b85d756…abc373` | 96311 | absent | yes | epoch 0 |
| 3 | 405 | `5b85d756…abc373` | 96311 | absent | yes | epoch 0 |
| 4 | 405 | `5b85d756…abc373` | 96311 | absent | yes | epoch 0 |

**unique hashes = 1.** The hash is byte-identical to the honest-input pre-fix state: with the pre-fix
`rewriteHxml` shape (filter present) and the real fixture I measured the same
`5b85d756…abc373` twice (`evidence/C-prefix-real-filter.log`), and in the parent export the real-fixture
state produced the same hash (`evidence/E-real-keep.log`). **Emitter behaviour is unchanged; only the
input mutation was removed.**

Clean-input support: after every generation above **and** the full-file run, all **1455 tracked files**
of the export still hash to their blob oids in `2aadcb69` (0 mismatch); the runs create only untracked
scratch, 26 files, all under `out/` (`evidence/post-run-tracked-input-integrity.txt`).

**The file runs 11 pass / 0 fail** in one full run of `tests/ts/package-artifacts.test.ts`
(`evidence/D2-fullfile-postfix.log`): 11 pass, 0 fail, 1532 `expect()` calls, 727.16 s — matching the
author's count; the byte-identity test itself passed in 366.16 s.

## 4. Claim 4 — no assertion weakened [CODE]

- The full diff of the commit is 2 hunks, both inside `rewriteHxml`/`runHaxe`; no test was deleted,
  renamed, skipped or marked `only`/`todo` (`git diff … | grep -E '^[+-].*(test\.skip|test\.todo|\.only|describe\.skip)'` → none).
- The entire body of `test("two generations of the same inputs produce byte-identical artifacts", …)`
  is **byte-identical** between the parent and the commit (`diff` over the extracted block → IDENTICAL),
  including `expect(fs.readFileSync(path.join(second, pkg.file))).toEqual(fs.readFileSync(path.join(first, pkg.file)));`.
- **Citation correction.** The claim and the ledger row both cite `package-artifacts.test.ts:333`. At
  the commit under review the byte-identity comparison is at **:338** (the test declaration is at :320;
  :333 is `expect(a.stderr).toBe("")` inside that test). At the parent revision `d2d444c0` the test
  declaration *is* at :333 and the comparison at :351. So `:333` names the *test* as it stood when the
  ruling was written, not the comparison in the reviewed revision. Documentation drift only — the
  compared bytes are unchanged.

## 5. Claim 5 — the tracked fixture is no longer written [CODE + EXEC]

- [CODE] The post-fix test file contains **no** reference to `samples/boring/MathNaNTestSupport.hx`
  outside comments and no write to any `samples/` path. Repo-wide, `git grep 'MathNaNTestSupport.hx'`
  over the branch tip finds only docs and comments; no other tracked file writes it.
- [EXEC] During the whole 727 s full-file run a 250 ms sampler saw **2780 samples of exactly one
  state**: sha `1c2acf93…`, `Test.equals`=5, **constant mtime** — the file was never opened for writing
  (`evidence/fullfile-fixture-states.txt`). Guard sha was identical before and after.
- The corruption vector was the stub write; with the write gone, **this test cannot corrupt the file**.
  Residual honesty: the test still drives `haxe` over the repository's sources, so it inherits whatever
  the compiler does; I did not audit every macro for writes into `samples/`. Empirically, across all
  ~20 generations run here, no tracked file changed at all (§3).

## 6. Four-requirement verdict on the ledger entry

Ledger: `docs/architecture/GATE-LEDGER.md`, "Restoring contract 3", rows 1 and 2 — both currently
**`in-flight`** ("no hash yet"), i.e. the entry makes **no main-line claim**, which is the correct
conservative wording. Assessed as if promoted to "on the line":

| # | Requirement (ruling 005 §③) | Met? | Evidence / reason |
|---|---|---|---|
| 1 | traceable commit hash | **YES** | `2aadcb6978d81705379892d2b382671b3458e753`. But the ledger row still says "no hash yet" — stale. Note it is an ancestor of `ci/collected-suite-failure-attribution` (HEAD `9274b7a7` at 16:25) and of `fix/npm-artifact-determinism` (`0b723fdc`), but **not of `master` (`cc9957dd`)** or `gitbutler/target` (`378dfdbf`), so "on the line" depends on which branch the ledger calls the line |
| 2 | clean working-tree proof **for that hash** | **NO** | The live worktree's HEAD is a different, actively-rewritten branch (`c365dbeb` → `0b723fdc` → `4f80322c` → `9274b7a7` inside this check). It was clean *at its own HEAD* at sample times, but no clean-tree proof can be tied to `2aadcb69` from that checkout, and producing one (new worktree / checkout) would modify the repository, which this brief forbids. Same failure mode as `eec707b9` |
| 3 | candidate content/checksums exported independently from the commit or a freeze archive | **NOT CARRIED** (but now producible and produced) | No freeze archive for this work exists. I exported the commit with `git archive` and proved the export byte-identical to the commit tree (1455/1455 blob oids); every hash in this report was measured from that export, not from a live worktree. The entry itself carries none of it |
| 4 | claim-versus-commit check, executor **and** reviewer | **reviewer half done here** | This report is the non-implementer check; five claims re-measured, two details corrected. Whether the executor's half is recorded is not visible in the entry |
| — | pre-transition three-way `HEAD` / commit-hash / freeze-archive check by a non-implementer | **FAILS as specified** | `HEAD` ≠ `2aadcb69` and there is no freeze archive; the ruling says a failed three-way check sends the entry back |

**Verdict.** All five technical claims survive independent re-measurement, with two corrections of
detail (the `:333` citation; the CI-occurrence attribution in §8 below). But the entry does **not**
satisfy the four-requirement gate: **R1 present, R4 now present, R3 producible but absent from the
entry, R2 absent**, and the three-way pre-transition check fails. As with `eec707b9`, the honest move is
to record the absence — and to keep the rows `in-flight`, updating them with the hash `2aadcb69` while
they no longer say "no hash yet". `in-flight` is explicitly permitted to carry a hash; a main-line
status is not.

## 7. Author's numbers vs mine

| Item | Author (`dc-warn/out/npm-determinism/REPORT.md`) | Mine |
|---|---|---|
| stub state, entries / sha256 | 407 / `4bb614bc…580c` (5 gens) | 407 / `4bb614bc…580c` (3 + 2 gens, stable) |
| real state, entries / sha256 | 405 / `5b85d756…c373` (3 gens) | 405 / `5b85d756…c373` (9 gens, stable) |
| post-fix, 5 gens | 405, 1 unique hash `5b85d756…c373` | identical |
| compressed-byte difference | "+116–118" | exactly **+116** |
| full test file | 11 pass / 0 fail | 11 pass / 0 fail (1532 expect calls, 727.16 s) |
| stub entries in tgz | `.js` + `.d.ts` | same two entries; the only two entries that differ |
| byte-identity comparison line | `package-artifacts.test.ts:333` (as in the ledger) | the comparison is `:338` at the commit, `:351` at the parent; `:333` is the test declaration in the parent revision |
| "the byte-identity test re-run repeatedly (see evidence/)" | cited | **no repeated-run log exists** in `dc-warn/out/npm-determinism/evidence/` (only `repro*.mjs`, `repro-base.log`, `repro-real-fixture.log`, `postfix-5gen.log`). I ran it again myself (below) |

Repeat runs of the byte-identity test in the export (author's claim, re-measured):

| run | result | duration | fixture guard (before → after) |
|---|---|---|---|
| full file (includes it) | 11 pass / 0 fail | 727.16 s (identity test 366.16 s) | `1c2acf93…`, count 5 → same |
| identity test, repeat 1 | 1 pass / 0 fail, 25 expect() calls | 350.03 s | count 5, `1c2acf93…` → same |
| identity test, repeat 2 | 1 pass / 0 fail, 25 expect() calls | 358.47 s | count 5, `1c2acf93…` → same |

The criterion "runs repeatedly and passes" is therefore satisfied by my own runs (3 runs of the
byte-identity test / 10-generation pass, 5+ independent generations in §3), not by the author's
missing log. Logs: `evidence/F-identity-repeat-1.log`, `evidence/F-identity-repeat-2.log`,
`evidence/F-identity-repeat-guards.txt`.

## 8. Honest limits / not verified

1. **`[UNVERIFIED]` the CI occurrence of the 405/407 flip.** I confirmed the *causality* — one input
   file's content deterministically selects 405 or 407 — but **no retained log of the actual flake
   event exists in this workspace** (searched; `dc-warn/out/ci-attribution/evidence/pre-existing-collected-suite.log`
   does not mention the artifact test, and that seat's own report states no retained log exists).
   The occurrence is therefore not witnessed by me either.
2. **`[UNVERIFIED]` the within-run flip path.** Reading the pre-fix harness, *both* generations of the
   byte-identity test go through the stubbing `runHaxe`, so a 405-vs-407 difference between the two
   compared artifacts requires the tracked file to change **during** the run (a concurrent suite
   mutating it, or a stub leaked by a killed run pre-`4cf3165d`). I did **not** stage that race. Claim 1
   is confirmed as "the states differ and the harness creates one of them", not as "this is the exact
   sequence CI saw".
3. **`[UNVERIFIED]` collected-suite / CI-runner behaviour.** Full-suite repetition needs the runner:
   `bun run test` (contract-3 condition 3) was not run. My evidence is one full file run plus two
   further runs of the byte-identity test, on this machine only.
4. **Single full-file run.** The 11/0 result rests on **one** full run; the byte-identity test was then
   run twice more alone (3 passes total). In the full run it took 366 s of its 420 s budget (87 %) —
   it passed, but the margin is thin under CI load.
5. **Tree scratch.** The export accumulates untracked `out/` scratch between generations (26 files).
   Tracked inputs are proven unmutated, but "clean inputs" here means unmodified tracked sources in one
   fixed tree, not a pristine filesystem.
6. **Toolchain-scoped.** All numbers are for haxe 4.3.7 / bun 1.3.13 / tsc 5.9.3 / kotlinc 2.4.10 on
   16 cores. Different emitters/toolchains were not tried.
7. **No emitter audit.** I verified the npm exclusion path (`emitNpmArtifact` → `npmCompileSet`) but did
   not audit the whole compiler for writes into `samples/`.

## 9. Evidence index (`evidence/`)

| file | what it shows |
|---|---|
| `repro-verify.mjs` | the independent driver used for every generation |
| `A-prefix-stub.log` | stub state, pre-fix filter, 3 generations → 407 / `4bb614bc…580c` |
| `B-postfix-real-5gen.log` | post-fix, real fixture, 5 generations → 405, 1 unique hash |
| `C-prefix-real-filter.log` | pre-fix rewrite shape + real fixture → same `5b85d756…c373` |
| `E-real-keep.log`, `E-stub-keep.log` | the two states on the parent export, roots kept |
| `entries-real-state.txt`, `entries-stub-state.txt`, `entry-diff-real-vs-stub.txt` | witnessed entry-list diff: exactly +2 entries |
| `mechanism-emitted-module.txt` | emitted `.ts` of the module in both states (the import that drives the closure) |
| `prefix-fixture-sampler.log`, `prefix-npm-test.log` | the shipped pre-fix harness stubbing the fixture live (557 samples) and still passing |
| `D2-fullfile-postfix.log` | full test file post-fix: 11 pass / 0 fail / 1532 expects / 727.16 s |
| `fullfile-fixture-sampler.log`, `fullfile-fixture-states.txt` | 2780 samples, one fixture state, constant mtime |
| `export-verify.txt`, `post-run-tracked-input-integrity.txt` | 1455/1455 files hash to the commit tree, before and after all runs |
| `F-identity-repeat-1.log`, `F-identity-repeat-2.log`, `F-identity-repeat-guards.txt` | byte-identity test re-run twice alone: 1 pass / 0 fail each, fixture guard intact |
| `toolchain.txt` | versions |
| `batch-main.sh`, `prefix-live.sh`, `two-state-diff2.sh`, `identity-repeat.sh` | exactly what was executed |
