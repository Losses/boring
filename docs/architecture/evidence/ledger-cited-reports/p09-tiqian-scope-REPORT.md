# P09 gate evidence — scoping audit (Tiqian half)

Date: 2026-09-30 (America/Toronto). Read-only audit; nothing outside
`dc-warn/out/p09-tiqian-scope/` was written.

**Headline correction.** The working premise handed to this audit — *"the pinned Tiqian
revision `8504d230…` is believed absent locally"* — is **false**. The revision is present as a
loose git object in `tiqian/.git`, is reachable from `main` and `origin/main`, and there is a
locked consumer checkout whose detached HEAD is **exactly** that revision. The Tiqian-half
blocker is therefore **not** "input missing". See §3.2.

---

## 1. The gate, verbatim

From `boring-wt-architecture/docs/architecture-work-plan.md`, lines 218–219
(file md5 `65c3abafcae9796f19f5c45d439edaef`; tracked and clean; last commit touching it
`f2aa3633 docs(plan): record focused outcomes and open gates`):

```
- [ ] P09: Run the candidate's required Boring checks and Tiqian checks on fixed
  revisions, preserving logs, generated-output identity, and warning results.
```

It is unchecked. Two other plan passages define what "Tiqian checks" means and neither
enumerates them:

- line 26 (goal criterion 4): *"The accepted candidate has fresh Boring checks and the
  required Tiqian platform regression evidence from a recorded pair of revisions."*
- line 395 (verification acceptance): *"Follow with the required Tiqian platform matrix.
  **Document the actual scope of that matrix before launch.**"*

So the plan requires the Tiqian platform matrix but **delegates its definition to a document
that must be written before launch** (see §3.4 and §4).

**Finding A.** The gate itself does not specify the Tiqian checks. Any claim that "the
required Tiqian checks are X" must cite a document other than the work plan.

---

## 2. Boring half — quantified inventory

### 2.1 Full-chain runs (the chain that actually exercises the compiler)

The Boring half is executed as **chain A**: a 17-stage exclusive run of
`option-c.plan` (`env-guard, identity, driver-build, driver-verify, then 12 repo scripts,
then a vector-hash compare`). Retained in `dc-warn/out/`:

| Run dir | Date (local) | Revision / input identity | Exact command | What it establishes |
| --- | --- | --- | --- | --- |
| `p09-chainA-full/` | 2026-09-29 18:52→19:14 | `cp -a` of `publication-staging/execution-option-c-coord`; 1433-entry manifest `610099bb…` | `bash p09-chainA-work/run-chainA.sh` → `run-exclusive.sh … option-c.plan` | Stages 0–2 **pass**; Stage 3 `driver-verify` **FAIL rc=1**: one real Swift compile error `VectorCodec.swift:49` cannot convert `TiqianArray<GlyphMetrics>` to `[TiqianArray<GlyphMetrics>]` (root cause `SwiftArrayBoundary.hx:259`). 20 child records, 0001–0019 all exit 0. Stages 4–16 skipped. |
| `p09-chainA-rerun/` | 2026-09-29 19:23→19:38 | same + exactly 1 file changed: `SwiftArrayBoundary.hx f191cdd1→b522865c`; manifest `22d165ca…`, still 1433 entries | `bash run-rerun.sh` | Stages 0–2 **pass**; Stage 3 **FAIL rc=1** but advanced past Swift: all three Swift child records 0020/0021/0022 exit 0, 33/33 child records clean, then `compare` fails with `166 divergence(s)` confined to the f32 legs; non-f32 columns `736 pass / 0 fail`. Stages 4–16 skipped. |
| `chainA-fixed-rerun/` | 2026-09-30 00:33→01:12 UTC | `execution-option-c-chainA-fixed3`; manifest `manifest-fixed2.json`; flake gave cargo 1.98.0 / jdk 21.0.12 | `nix develop -c bash -c 'bash preflight3.sh; bash command3.sh'` | Stages 0,1,2 **pass**; **Stage 3 `driver-verify` PASSES**; Stage 4 `authored-tests` (`bun run test`) **FAIL rc=1**; 12 further stages skipped. `RUNNER_RC=1`, `OUTER_RC=0`. |

Exact commands are recorded on disk: `p09-chainA-rerun/run-rerun.sh`,
`chainA-fixed-rerun/run-all3.sh` + `command3.sh` + `preflight3.sh`, and per-stage
`.command` files inside each attempt directory.

### 2.2 The two numbers the parent asked about — both verified, both need care

**"Ten-target consistency" — VERIFIED, and it passes.**
`dc-warn/out/chainA-fixed-rerun/evidence/run2-stage3-manager-tail.txt` ends:

```
All 10 targets (haxe, ts, kotlin, dart, rust, swift, haxe-f32, kotlin-f32, rust-f32, swift-f32)
are 100% consistent across 736 tests.
bundle driver: ok
```

The check is the `compare` action of the Boring driver, running the manager over
`--targets=kotlin,haxe,ts,dart,rust,swift,haxe-f32,kotlin-f32,rust-f32,swift-f32 --baseline=kotlin`
(the same 10-target invocation the repo's own `.github/workflows/ci.yml` uses via
`bun run test:consistency`).

**"~736 tests" — VERIFIED**, same file; 736 = 730 shared + 6 f32-only oracle ids.

**Per-failure attribution — VERIFIED.** The intermediate run
`p09-chainA-rerun/REPORT.md` §4 records `166 divergence(s)`, decomposed as
`[haxe-f32] Extra 6` + `[kotlin-f32]/[rust-f32]/[swift-f32] Missing 160` (60 distinct ids),
with `非 f32 列：736 pass / 0 fail`. `f32-roots-fix/REPORT.md` §2 then records the repair
(`166 → 3`, then `0`).

### 2.3 Freshest state — and why it is not yet acceptable evidence

The freshest full-chain run (`chainA-fixed-rerun`, ~39 min wall) shows the consistency stage
**passing** but the chain **failing at the next stage**:

```
984 pass
 49 fail
  7 errors
Ran 1033 tests across 303 files. [1705.26s]
error: script "test" exited with code 1
```

Many failures are `timed out after 5000ms/15000ms/120000ms` — i.e. resource contention, not
necessarily semantics. This is the concrete content of the plan's own statement (line 108):
*"Full Boring verification attempts have run without producing an accepted full result."*
It is now precisely located: the consistency stage is green; the **authored-test stage is red**.

### 2.4 Staleness — the Boring half's retained evidence is NOT fresh

This is the most important Boring-side finding.

1. **The coordinator tree cannot reproduce its own consistency reading.**
   `boring-wt-architecture/out/test-results/` today holds only **4 of the 10** required files
   (`haxe.jsonl`, `kotlin.jsonl`, `kotlin-f32.jsonl`, `ts.jsonl`). Running the manager against
   the tree's own results dies with `Missing test results file for target 'dart'|'rust'|'swift'|
   'haxe-f32'|'rust-f32'|'swift-f32'` (6 errors). And `ts.jsonl` there is 486,508 bytes dated
   **2026-09-29 01:47**, whereas the fresh set from `execution-option-c-chainA-fixed2/out/test-results/`
   has ten uniformly-sized files (121,627/122,877/121,637 B) dated 09-29 20:26–20:30.
   Mixed vintage, mixed provenance, incomplete.

2. **The best "0 divergence / 736 tests" reading does not come from the candidate tree.**
   `dc-warn/out/f32-e2e-reverify/REPORT.md` §2.2–2.4 states it plainly: the result set used came
   from `p09-chainA-work/execution-option-c-chainA-fixed2/out/test-results/`, whose HEAD is
   `613b6b40…` and *"该对象在协调树仓库中不存在"* (`git cat-file` fatal — re-verified here:
   `fatal: Not a valid object name 613b6b40`). Attribution rests on a source-semantics
   comparison, not on a shared commit identity.

3. **The `0` is produced by an in-flight test edit, not by a committed state.**
   The three residual `finiteClassification` divergences disappeared because
   `samples/tests/NumberClassifyTests.hx` was edited `1.0e308 → 3.0e38` (working-tree only).
   `f32-e2e-reverify/REPORT.md` §2.3 labels this *"测试输入可移植性修改，不是码生成修复"* and notes
   it narrows binary64 coverage. Reverting that literal brings the 3 divergences back.

4. **The candidate is a dirty working tree, not a commit.** `boring-wt-architecture` HEAD is
   `e1c6597514634fd347d392709793cc19bd96c9a2` with **15 tracked files modified
   (+507/−14) and 10 untracked entries** (25 porcelain lines). The work plan itself warns
   (lines ~368–372) that git blob identities cannot establish the identity of unstaged working
   files, so the consumed bytes must be hashed. No run in `dc-warn/out/` certifies *this* byte set.

5. **The declared fixed Boring revision is already superseded.**
   `p09-fixed-matrix-preparation-runbook.md` declares the fixed Boring revision to be
   `2159c657dcca870950b7bd43aa6e09a21d7cee30` and its own B1 says the two in-flight Rust fixes
   are *frozen out* of it. Verified here: `2159c657` **is** an ancestor of HEAD but is **8
   commits behind**, and HEAD **contains both** Rust fixes (`741a2acd`, `0701762d` are
   ancestors of `e1c65975`). The runbook's declared coordinator HEAD `c9e2cff9` is likewise an
   ancestor, 6 commits behind. So the runbook's B1 premise no longer holds, and the runbook's
   static preparation (`tiqian-fixed-2159c657-prep`) is prepared against a superseded revision.

**Verdict on the Boring half:** substantial and genuinely useful diagnostic evidence exists, and
the ten-target consistency check demonstrably passes on a retained result set. But **no retained
Boring run is an accepted, fresh, full-chain result on the current candidate byte set.** The
evidence is *stale-by-input-change* at the tree level and *attribution-limited* at the result-set
level. It is not yet P09-grade evidence.

### 2.5 Repair work that is real but only half-landed

`dc-warn/out/f32-roots-fix/REPORT.md` delivered: 111 inserted roots lines across the three f32
HXMLs, a `tools/roots-guard/` guard, and a `tools/test-consistency/extra-id-allowlist.json`.
`dc-warn/out/f32-e2e-reverify/REPORT.md` §1 and §4-#3 verify the guard's discriminating power
(prefix `FAIL: 111 + EXEMPT: 3`, rc=1; postfix `PASS`, rc=0) **and** that `tools/roots-guard/*`
and `extra-id-allowlist.json` are **UNTRACKED** in the coordinator tree, and that `PATCH.diff`
omits them (4 files / 16 hunks, `roots-guard` mentioned 0 times). Applying the patch alone
reproduces `9 = 3 verdict + 6 extra` divergences **silently** (no "allowlist missing" warning;
`Main.hx:100-104` returns an empty map when the file is absent). The allowlist is load-bearing:
removing it turns `0 → 6` and `3 → 9`.

---

## 3. Tiqian half — findings

### 3.1 Is there any Tiqian evidence in `dc-warn/out/`? — **No execution evidence. None.**

*Method.* `grep` tool (ripgrep) with three patterns over
`/home/losses/Development/tq-workspace/dc-warn/out`. A recursive `grep -ril` over the FUSE mount
did not finish in 60 s and was abandoned; the tool pass returned complete match sets, so text-file
coverage is full. Full classification: `evidence/tiqian-hits-in-dcwarn-out.txt`.

- Pattern `8504d230` → **13 matches**, every one inside a planning/patch/consult document
  (`p09-verify-plan/PLAN.md`, `plan-docs-fix/PLAN.md`, `p09-runbook/PATCH.diff`,
  `runbook-fix/*`, `sol-architecture-consult/*`).
- Pattern `(?i)tiqian` → **2,463 matches**, but this number is a **false friend**:
  `TiqianArray` is the *generated Swift runtime container type name* emitted by the Boring Swift
  backend (e.g. `switch-try-gap-verify/gen-probe3/Runtime.swift:276`
  `public final class TiqianArray<Element>: Sequence, Collection`). It has nothing to do with the
  Tiqian consumer. **No count of raw `tiqian` hits measures Tiqian evidence.**
- Pattern `tiqian-validation-round2|tiqian-fixed-2159c657|tiqian-prep|architecture-t2|consumer
  checkout|Tiqian candidate gate|Tiqian platform|Tiqian gate` → **80 matches**, all of which are
  planning text, runbook text, consultation answers, readiness notes, or **file-inventory
  entries** that merely list the path string
  `docs/investigations/architecture-round-2/tiqian-preparation-review.md` inside an identity
  manifest (30 of the 80 are `bytefix-verify/scratch/ctrl/*/identity.stdout`).

**Finding B.** Zero files in `dc-warn/out/` are the output of a run that consumed the Tiqian
revision and produced generated output, test results, or warnings. The parent's belief that the
Tiqian half is zero *in `dc-warn/out/`* is **confirmed**. (Note this is a statement about that
directory only — see §3.2: Tiqian preparation artifacts live elsewhere.)

### 3.2 Is the pinned revision `8504d230…` present locally? — **YES. It is present.**

This corrects the premise. Method and raw output: `evidence/revision-presence-sweep.txt`,
`evidence/revision-object-and-refs.txt`.

*Method.* Enumerated every `.git` directory **and** `.git` file (worktrees use a `.git` *file*)
under the workspace to depth 4 by `find . -maxdepth 4 \( -name .git -type d -o -name .git -type f \)`
→ **95 git locations**, then ran `git -C <repo> cat-file -t 8504d230…` against each
(git resolves worktree `.git` files to the shared object store itself).

*Result.* `rc=0` in **11** locations — but they are **not** 11 independent copies. All 11 resolve
`--git-common-dir` to `/home/losses/Development/tq-workspace/tiqian/.git`, so this is **one**
object store:

```
HEAD == 8504d230... : architecture-workspaces/tiqian-validation-round2
(other worktrees of the same store, at different HEADs)
  tiqian, tiqian-pin-advance, tiqian-wt-core-alpha6, tiqian-wt-demo-boring,
  tiqian-wt-warn-dart3, tiqian-wt-warn-legacyguard, tiqian-wt-warnstd,
  tiqian-wt-wcred, wt-ci-native-precompute, wt-publish-ci
rc=128 (absent) in the remaining 84, including boring-wt-architecture itself
```

*Form.* Loose object, not packed:
`tiqian/.git/objects/85/04d230228e8206689a2049bbb84b671c1f079a`, 268 bytes,
mtime `2026-09-27 20:57`. A scan of every `tiqian/.git/objects/pack/*.idx` via
`git verify-pack -v` finds **no** pack containing it.

*Reachability.* `git for-each-ref --contains` lists 10 refs including
`refs/heads/main`, `refs/remotes/origin/main`, `refs/remotes/origin/HEAD`.
Commit `8504d230228e8206689a2049bbb84b671c1f079a`, author LOSSES Don,
`2026-09-27 20:52:25 -0400`, subject
`fix(ffi-js): pass the rubySpans argument the LayoutInput call omits`.
It is reachable from `main` but is **not** an ancestor of the main repo's current HEAD
`80445d91` (`merge-base --is-ancestor` rc=1) — i.e. `main` has moved past it.

*Locked checkout.* `architecture-workspaces/tiqian-validation-round2` is a real, populated
worktree: `HEAD` = `8504d230228e8206689a2049bbb84b671c1f079a`, tree
`a314ba3b38a9cac6bee61ff60ec69d06cca34cdf`, 2,637 tracked files, 94 MB, `git status --short`
shows **zero tracked modifications** and exactly **6 untracked files** (the three
`boring-architecture-*-candidate.json` and the three `boring-fixed-2159c657-*.json`) — precisely
as the runbook describes. Golden data is present
(`engine-haxe/baseline-goldens/shaping-evidence.json`, etc.).
Raw: `evidence/round2-checkout-state.txt`.

**Finding C (decisive).** The pinned Tiqian revision is **present, reachable, and checked out**.
The consultation premise *"If Tiqian is unavailable locally, P09 is blocked as a gate"*
(`sol-architecture-consult/SOL-ANSWER.md:166`) is **not satisfied** — its antecedent is false.

*Coverage caveat (stated honestly).* I searched: all 95 workspace git locations via
`cat-file -t`; the `tiqian` loose-object path; all `tiqian` pack indexes via `verify-pack`;
`for-each-ref --contains`; and the checkout state. I did **not** exhaustively sweep
`--batch-all-objects` over all 95 repositories (too expensive), nor did I search `/nix/store`
or archive files for the revision — but because a live checkout at that exact revision already
exists, absence elsewhere could not change the conclusion.

### 3.3 Checkout, CI, scheduled workflow?

- **Checkout:** yes — §3.2.
- **CI configuration that would produce the consumer evidence: none found.**
  The Tiqian consumer has 8 workflows
  (`ci-native-precompute`, `publish-precompute`, `publish-snapshots`, `publish-ffi`,
  `publish-prose`, `snapshot-precompute`, `build-neon-precompute`, `publish.yml`). All are about
  Tiqian's own product (Neon addon, npm/Maven publishing, prose). **None** checks out Boring or
  runs the Boring driver matrix.
  Boring's own `.github/workflows/ci.yml` *does* run the 10-target generation and
  `bun run test:consistency`, but only against **Boring itself** on `push: master` / `pull_request`;
  it never references Tiqian (`grep -rni tiqian .github/` → 0 hits).
- **Scheduled workflow: none.** `grep -rn '^  schedule:'` over both repos' `.github/` → 0 hits.
  Every trigger is `push` / `pull_request` / `workflow_dispatch` / tag.
- **No `p09` / `fixed-matrix` reference in any workflow** (0 hits in both repos).

**Finding D.** Nothing in either repository's CI reproduces the P09 Tiqian matrix. It is a
manual, documented procedure.

### 3.4 Is there a documented way the consumer evidence is supposed to be produced? — **Yes, two, and the executable one is untracked.**

1. **`boring-wt-architecture/docs/investigations/architecture-round-2/tiqian-preparation-review.md`**
   — **TRACKED**, 97 lines, mtime 2026-09-28 18:27. It accepts the static preparation at
   `8504d230` *"This accepts static preparation only. Generation, native execution, test-ID
   agreement and regression remain unverified."* It states the obligations (12 generation +
   11 target-test, engine 8 / protocol 3, baselines `kotlin-f32` and `protocol-ts`, the 8 common
   protocol test roots) and the environment discipline. It is **not** a step-by-step recipe.

2. **`boring-wt-architecture/docs/investigations/architecture-round-2/p09-fixed-matrix-preparation-runbook.md`**
   — **UNTRACKED** (`?? ` in `git status`), ~330 lines, mtime 2026-09-29 17:57. This *is* the
   cold-start-executable recipe: revision pair, the 30 hash-pinned files, blockers B1–B4, pinned
   nix store paths, shell discipline, the four stage commands, the attempt-directory layout, and
   the post-run invariant list. A copy also exists at
   `dc-warn/out/runbook-fix/FINAL-p09-fixed-matrix-preparation-runbook.md`.
   Verified: **no tracked file references it** (loop over `git ls-files '*.md'` → no hits).

3. Supporting planning: `dc-warn/out/p09-verify-plan/PLAN.md` (and its twin
   `plan-docs-fix/PLAN.md`) defines **chain B** = the P09 Tiqian matrix, and states in its own
   header *"本轮未执行任何验证"* — no verification was executed. Its §7-D1 records that the
   **Boring-side revision of the pair is still an open decision** (`2159c657` vs `e1c65975`).

**Finding E.** The procedure exists and is executable, but the authoritative recipe is an
**uncommitted orphan**: not referenced by the tracked plan or the tracked preparation review.
That is a real durability risk for a gate whose whole point is retained evidence.

### 3.5 Tiqian preparation state — prepared twice, executed zero times

Both preparation trees are `preparation-only-not-executed` with `outputs/` and `results/`
**absent** (`evidence/tiqian-prep-execution-state.txt`):

| Prep tree | manifest identity | status |
| --- | --- | --- |
| `architecture-workspaces/tiqian-validation-round2/out/tiqian-fixed-2159c657-prep/` | `manifest.json` | `status: preparation-only-not-executed`, `generationStarted: false`, `driverSourceRevisionVerified: false`, `protocolCException.status: requires-execution-authorization`, `genStartAbsenceRecorded: false` |
| `tiqian/out/p09-e1c65975-round2-prep/` | `manifest/manifest-30.json`, `candidate_commit e1c65975`, `candidate_tree 8000836c…`, 1398-file snapshot, content-list sha256 `4a50f224…` | `status: preparation-only-not-executed`, `generationStarted: false`; `verification-summary.json` records 5 static preflight PASS and `unresolved: ["B2 driver provenance", "B3 Swift SystemPackage/toolchain", "B4 protocol-C authorization and fresh-start evidence"]` |

Obligations confirmed independently from the project files (engine baseline `kotlin-f32`, 8
bundles; protocol baseline `protocol-ts`, 4 bundles, `protocol-c` `test:false` + `afterGen`) —
matching the preparation review's 12-generation / 11-test split.

---

## 4. The exact minimum that would make the Tiqian half executable

An operator with write access and the toolchain needs exactly this. Everything below is
**specified in existing documents** — with the two gaps called out.

**Revision pair.** Tiqian side is fixed: `8504d230228e8206689a2049bbb84b671c1f079a` (runbook
head table; Tiqian preparation review; PLAN.md §1.2-6). Boring side is **undecided**:
`p09-fixed-matrix-preparation-runbook.md` says `2159c657dcca870950b7bd43aa6e09a21d7cee30`;
`dc-warn/out/p09-verify-plan/PLAN.md` §0/§7-D1 defaults to `e1c65975` (which is the current
worktree HEAD and contains the two Rust fixes the runbook froze out). **The pair is therefore
not yet fixed, and the gate requires a fixed pair.** This must be decided first (checklist C1).

**Commands** (runbook §Stage commands, cwd
`/home/losses/Development/tq-workspace/architecture-workspaces/tiqian-validation-round2`):

```
# 1. generate, in two project groups (never use the 12-bundle *-all.json)
boring gen  <8 engine ids...>   --project boring-fixed-<rev>-engine.json
boring gen  <4 protocol ids...> --project boring-fixed-<rev>-protocol.json
# 2. test, engine group then protocol group (protocol-c is test:false)
boring test <8 engine ids...>   --project boring-fixed-<rev>-engine.json
boring test protocol-ts protocol-rust protocol-kotlin --project boring-fixed-<rev>-protocol.json
# 3. compare, one per group
boring compare --project boring-fixed-<rev>-engine.json      # baseline kotlin-f32
boring compare --project boring-fixed-<rev>-protocol.json    # baseline protocol-ts
```

with `HAXELIB_PATH` overridden to the prep haxelib dir **after** the flake `shellHook`, in the
**same** shell (runbook §Shell discipline).

**Expected artifacts**, per stage, in an exclusive attempt directory (runbook §Stage commands
last paragraph): `before.json`/`after.json`, `argv.json`, `env.json`, byte-streamed `stdout`/
`stderr`, numeric `status`, `parsed-modules.json`, `outputs.json`, `integrity.json`; plus the
per-bundle test-ID sets `<resultsDir>/<bundle-id>.jsonl`; plus the post-run invariant
re-verification (30-manifest hash recomputation, 1366/1398-entry inventory digest, `git status
--short` clean, both `git rev-parse HEAD`, driver hash asserts).

**Where numbers would be recorded.**
- Attempt directories: `architecture-workspaces/tiqian-validation-round2/out/` (runbook default)
  — or `tiqian/out/p09-e1c65975-round2-prep/` side; **PLAN.md §7-D6 records this as an open
  decision** (two different worktrees, write permission needs coordinating).
- Conclusion may cite only: the fixed revision pair, the per-bundle test-ID sets from the results
  JSONL, and the invariant re-verification (runbook §Review scope).
- Agent-side report: a new `dc-warn/out/<name>/REPORT.md`, mirroring the chain-A convention.

**Cited specification.** Revision identities, commands, artifacts and recording conventions are
specified by `p09-fixed-matrix-preparation-runbook.md` (untracked) and, at obligation level, by
`tiqian-preparation-review.md` (tracked). **Neither is referenced by the work plan**, and the
work plan itself (line 395) only says the scope must be documented before launch.

**Two documented gaps that must be closed before the run can be complete** (both are in the
runbook, not invented here):
- **B3** — `libSystemPackage` shared library: the runbook records `SystemPackage.swiftmodule`
  exists but *no* `libSystemPackage.so` was ever produced; two Swift test obligations are blocked
  until it is built with the fallback toolchain. (Note: a `BORING_SWIFT_SYSTEM_PACKAGE` store path
  `0svbxvd…-boring-swift-system-1.6.6` containing `libSystemPackage.so` **was** used
  successfully by the later chain-A run — `chainA-fixed-rerun/evidence/console.log` — so this
  blocker may already be closed and the runbook is stale on it. This needs confirming.)
- **B4** — `protocol-c` `afterGen` (`bun engine-haxe/out/protocol-c/gen/c-header.js`) requires
  explicit execution authorization; `genStartAbsenceRecorded` is still false.

---

## 5. Gap classification

**(a) missing input — NO.** Disproved. The pinned Tiqian revision is present as a loose object
reachable from `main`, and a locked, populated checkout sits at exactly that revision (§3.2).
This was the premise most likely to justify "blocked"; it does not hold.

**(b) missing procedure — NO, but the procedure is fragile.** A cold-start-executable recipe
exists and has been independently reviewed and patched
(`p09-fixed-matrix-preparation-runbook.md`; `dc-warn/out/p09-runbook/`,
`dc-warn/out/runbook-fix/`, `p09-driver-xcheck/REVIEW.md`). Obligations are stated in the tracked
`tiqian-preparation-review.md`. However the authoritative recipe is **untracked and cited by no
tracked document** (Finding E). Procedure exists; its retention does not.

**(c) missing capability — PARTIALLY, and narrowly.** The environment was verified present
(§Execution environment: haxe 4.3.7, bun 1.3.13, kotlinc 2.4.10, cargo, java, swift dist + FHS,
reflaxe, haxe, kotlin, java, and the rebuilt driver). Two named capability gaps remain in the runbook —
B3 (`libSystemPackage.so`) and B4 (protocol-C authorization) — and the fresh chain-A evidence
suggests B3 is in fact closed and the runbook stale. Neither is a hard "cannot execute"
blocker: everything else needed has been demonstrated working.

**(d) already satisfied but unrecorded — NO for execution; YES for the Boring consistency stage.**
The 736-test/10-target consistency check genuinely passes on a retained result set, but that
result set is not attributable to the current candidate byte set (§2.4), so it cannot be
*recorded* as P09 evidence without a fresh run. For Tiqian: nothing was executed, so nothing is
merely unrecorded.

**Classification: the gap is a missing executable run, on a not-yet-frozen revision pair, whose
procedure exists but is untracked.** It is not blocked by absence of any input. It is blocked by
(a) an unmade decision about the Boring-side revision, (b) an unfrozen working tree, and (c) two
narrow, probably-stale capability caveats. The single largest obstacle is **decision, not
capability** — which is exactly the pattern the consultations diagnosed.

---

## 6. What a decider must obtain — checklist

No recommendations, only what must be in hand.

**C1. The revision pair, decided and written down.**
- [ ] Choose Boring side: `2159c657…` (runbook; excludes the two Rust fixes) **or** `e1c65975`
      (current HEAD; includes them). Recorded in `p09-verify-plan/PLAN.md` §7-D1 as open.
- [ ] Confirm Tiqian side stays `8504d230228e8206689a2049bbb84b671c1f079a`.
- [ ] If `e1c65975`: confirm use of `publication-staging/fixed-compiler-e1c65975` (1398 entries)
      and `tiqian/out/p09-e1c65975-round2-prep/`, not the `2159c657`/1366 pairing.

**C2. A frozen Boring candidate.**
- [ ] A decision on whether P09 must be run on the current **dirty** tree (15 modified + 10
      untracked) or on a commit. If dirty: the exact working-file hashes to be consumed,
      recorded before and re-verified after (work plan lines ~368–372).

**C3. Confirmation of the two runbook caveats.**
- [ ] Observed statement of whether `libSystemPackage.so` exists for the Swift test stage
      (runbook B3 says it never did; `chainA-fixed-rerun` used
      `0svbxvd…-boring-swift-system-1.6.6/libSystemPackage.so` successfully). One or the other is wrong.
- [ ] An explicit authorization decision for `protocol-c` `afterGen`, or a recorded decision to
      run the matrix with that one obligation declared `environment-not-reached` (runbook B4).

**C4. The recording location decision (PLAN.md §7-D6).**
- [ ] `architecture-workspaces/tiqian-validation-round2/out/` **or**
      `tiqian/out/p09-e1c65975-round2-prep/` side — these are different worktrees.

**C5. Durable retention of the procedure.**
- [ ] A decision on committing `p09-fixed-matrix-preparation-runbook.md` (currently untracked and
      referenced by no tracked document), or otherwise registering it as the P09 procedure of record.

**C6. Acceptance of the Boring half, or a fresh Boring run.**
- [ ] Evidence that `out/test-results/` is complete for all 10 targets **on the frozen candidate**
      (currently 4 of 10, with `ts.jsonl` from 09-29 01:47), **or** a fresh full chain-A run, since
      the retained `0 divergence / 736 tests` reading is attributed to a result set from a clone
      whose HEAD (`613b6b40`) does not exist in the coordinator repository.
- [ ] Acknowledgement that chain A currently fails at the `authored-tests` stage
      (`984 pass / 49 fail / 7 errors`, mostly timeouts) and that this is unaddressed.

**C7. Resource and exclusivity preconditions** (from PLAN.md §6 P1 and APPLY notes).
- [ ] Free disk (PLAN.md measured `/home` at 184 G / 90 % used) and confirmation that no other
      heavy test run is concurrent when the matrix starts.

---

## 7. Method and limits

*Searched.* All 95 `.git` locations under the workspace (`cat-file -t`, worktree-aware); the
`tiqian` loose-object path; all `tiqian` pack indexes (`verify-pack -v`); `for-each-ref --contains`;
checkout state of all 11 `tiqian*`/`bt-*` worktrees; `dc-warn/out/` text corpus with three
patterns (ripgrep via the grep tool); both repos' `.github/workflows/`; board
`board.json` (7 tasks, 5 milestones — **none** relates to P09, the compiler, or Tiqian; it is the
dispatch-plugin board, `updatedAt` 2026-09-30 00:51); the revision graph
(`merge-base --is-ancestor`, `rev-list --count`); attempt harness logs and stage `.status` files.

*Not searched / limits, labelled honestly.*
- Raw `tiqian` keyword counting is **not** a valid measure of Tiqian evidence (§3.1) because
  `TiqianArray` is a generated Swift type name. Any earlier figure based on raw `tiqian` hits
  should be discarded.
- I did **not** run `--batch-all-objects` over all repositories, nor search `/nix/store` or
  archive files for `8504d230`. Since a live checkout at that exact revision exists, absence
  elsewhere would not change the conclusion.
- I did **not** run the test suite (forbidden: ~29 min, concurrent agents) and did **not** modify
  any repository, worktree, or report.
- Exit codes were never measured through a pipe; `git cat-file` rc values were captured directly.
- The workspace-board JSON was read as a secondary source only; the primary source is the repo's
  own docs, as instructed.
- Dates are local (`America/Toronto`) unless suffixed UTC.

*Raw evidence.* `evidence/` — `gate-text.txt`, `revision-presence-sweep.txt`,
`revision-object-and-refs.txt`, `round2-checkout-state.txt`, `tiqian-hits-in-dcwarn-out.txt`,
`tiqian-prep-execution-state.txt`, `chainA-fixed3-stage-results.txt`,
`ten-target-consistency-readout.txt`.
