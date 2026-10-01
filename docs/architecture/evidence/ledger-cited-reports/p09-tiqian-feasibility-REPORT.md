# P09 Tiqian half — local feasibility report

Date: 2026-09-30 (America/Toronto). Builds on `dc-warn/out/p09-tiqian-scope/REPORT.md`.
Read-only with respect to every repository and the Tiqian worktree; all writes were to
`/tmp` and to this output directory. Raw logs in `evidence/`.

**Headline.** The Tiqian half is **locally executable in its static and probe layers** —
toolchain, pinned inputs, driver, haxelib shadowing and the Swift fallback recipe all
verified working today — but the matrix itself is **not safely startable by me** because it
must write into the locked `tiqian-validation-round2` worktree (its `out/` tree), and one
authorization gate (B4) is open. Additionally, **two of the audit's premises have moved**:
the runbook is now **tracked** (committed in `0a5c42a7`), and the manifest invariant
**fails today** (13 of 30 pinned original hashes mismatch; the 15 live derived inputs still match).

---

## 1. Input confirmation

| Input | Observed | Status |
| --- | --- | --- |
| Tiqian HEAD | `git rev-parse HEAD` = `8504d230228e8206689a2049bbb84b671c1f079a` (detached) | **Confirmed exactly as pinned.** |
| Tiqian worktree cleanliness | 0 tracked modifications; 6 untracked files (the three `boring-architecture-*-candidate.json` + three `boring-fixed-2159c657-*.json`) | **Confirmed clean** (evidence/inputs-and-revisions.txt). |
| Boring revision Tiqian's flake pins | `flake.nix` L11: `github:Losses/boring/304ed70c4ba09fe21edadcca4c85f963fd692927`; shellHook re-asserts the same string and stamps `.haxelib/boring/git/.boring-flake-revision` = `304ed70c…` (verified on disk) | **This is the pinned Boring version Tiqian consumes natively.** |
| Is the flake pin the frozen P09 candidate? | `304ed70c` exists in `boring-wt-architecture` but is **NOT an ancestor** of HEAD (merge-base `378dfdbf`; `rev-list 304ed70c..HEAD` = 150) | **FINDING (new): the two halves are natively pinned to different, divergent Boring lineages.** The runbook anticipates this: the flake mapping must be shadowed for the whole run by `HAXELIB_PATH=out/tiqian-fixed-2159c657-prep/haxelib` (verified resolving to the fixed snapshot, probe 5). So the divergence is handled **by procedure**, not by revision identity — but it means a P09 run must never rely on the flake default mapping. |
| Boring coordinator HEAD | `0a5c42a7` ("baseline") — **moved since the scope audit**, which saw `e1c65975`. `e1c65975` is an ancestor; `2159c657` is an ancestor 10 commits back (was 8). | Tree still dirty: 21 porcelain lines (SwiftExpr.hx + 19 test scripts + roots-guard files modified). |
| Trap check | `grep -c 'Test.equals' samples/boring/MathNaNTestSupport.hx` = **5** | Intact. |

## 2. The procedure — found, read, and now tracked (status change)

The recipe is `boring-wt-architecture/docs/investigations/architecture-round-2/p09-fixed-matrix-preparation-runbook.md`.
The scope audit recorded it as **untracked and cited by no tracked document** (Finding E).
**That has changed:** commit `0a5c42a7` ("baseline", on top of `e1c65975`) **adds this exact file
(309 lines) to git** — `git ls-files --error-unmatch` rc=0. The durability risk Finding E
described is **closed**. Caveat: the committed copy is the runbook as of 09-29; its B1
premise ("fixed revision = 2159c657") is 10 commits stale, and its B3 dart/libSystemPackage
caveats are stale in the *closed* direction (see §3).

What it specifies (summary): fixed pair `2159c657…` × `8504d230…`; 30 hash-pinned inputs
(15 originals + 15 derived); rebuilt matrix driver `out/bundle/driver.js` sha256
`bf2450d3…` (B2 closed); shell discipline (`HAXELIB_PATH` override **after** the flake
shellHook, same shell); four stage commands (`boring gen` in 2 group projects, `boring test`
engine 8 then protocol 3, `boring compare` per group); per-stage attempt-dir artifact set
(`before/after.json`, `argv.json`, `env.json`, streamed stdout/stderr, numeric `status`,
`parsed-modules.json`, `outputs.json`, `integrity.json`, per-bundle `<resultsDir>/<id>.jsonl`);
post-run invariant re-verification; explicit uncovered-scope list for the conclusion.

## 3. Prerequisite table (all verified today, exact evidence)

| Prerequisite | Status | Evidence |
| --- | --- | --- |
| Pinned nix store paths (driver, haxe 4.3.7, bun 1.3.13, reflaxe, kotlin 2.4.10, rust 1.97.1, openjdk 25.0.4, swift dist + FHS) | **ALL PRESENT** | `evidence/store-paths.txt`; all 9 runbook paths `[ -e ]` rc=0 |
| dart SDK ("not materialized" per runbook) | **PRESENT — runbook stale** | `/nix/store/qpggxvncr1jwa7xjn0wf0i6045na7hki-dart-3.13.0` exists and is on the chainA PATH (`env.json`) |
| `libSystemPackage.so` (B3 "never produced") | **PRESENT — B3 build blocker closed, runbook stale** | `/nix/store/0svbxvdamgqh4jdlnp48yvyn4v6cvfpk-boring-swift-system-1.6.6/` contains both `libSystemPackage.so` and `SystemPackage.swiftmodule` |
| Swift fallback toolchain (B3 recipe) | **WORKS — I ran it** | raw dist alone: rc=127 (`libncurses.so.6: cannot open shared object file`); with runbook `LD_LIBRARY_PATH` + symlink SDK tree: `swiftc --version` rc=0 (Swift 6.2.4) and `swiftc -typecheck -sdk … import Glibc` rc=0. `evidence/pf-swift2.out`, `pf-swift4.err`, `probes-run.txt` |
| Rebuilt matrix driver | **VERIFIED** | `sha256sum out/bundle/driver.js` = `bf2450d3…` == B2 pin, 52,779 bytes; no-arg usage probe rc=2 with expected usage line (rc captured directly) |
| haxelib shadowing | **VERIFIED** | with `HAXELIB_PATH` = prep dir: `haxelib path boring --global` rc=0 → `publication-staging/fixed-compiler-2159c657/packages/compiler/`; `reflaxe` rc=0 → store path |
| 30-manifest hash invariant | **PARTIAL FAIL — new finding** | 17/30 match; **13 ORIGINALS mismatch** (11 `out/architecture-candidate-inputs/hxml/*.hxml` + 2 candidate JSONs). Their mtimes (09-29 **13:26**) postdate the manifest (02:43): the provenance originals were rewritten in place after pinning (they now carry resolved store-path content). **All 15 derived LIVE inputs still match.** `evidence/manifest-hash-recompute.txt`. The runbook's own post-run invariant ("30-manifest recomputation") would fail today on the originals; the run must either re-pin the originals or record this drift. |
| Disk | OK | `/home`: 229 G free (1.9 T, 88 % used) — improved from the audit's 184 G |
| Network | **Not needed for what I ran**; the matrix stages themselves are all local given the store paths above. Unverified: whether `nix develop` in the consumer checkout can build without fetching (flake tarballs appear cached — the driver/kotlin/rust store paths exist). | — |
| Authorization (B4) | **STILL OPEN** | `manifest.json` `protocolCException.status = "requires-execution-authorization"`, `genStartAbsenceRecorded: false`; `outputs/` and `results/` still absent. `protocol-c` `afterGen` (`bun engine-haxe/out/protocol-c/gen/c-header.js`) must not be run without an explicit authorization decision. |
| Write access to run location | **NOT AVAILABLE TO ME** | Every stage command's cwd is the locked `tiqian-validation-round2` worktree and outputs go under its `out/` (gitignored but inside the locked worktree). My mandate makes that tree read-only, so **the matrix was not started**. |

## 4. What I actually ran (vs. what the recipe says)

**I ran (all read-only, rc captured directly, never through a pipe):** items 1–9 in
`evidence/probes-run.txt` — haxe/bun versions, driver hash + usage probe, haxelib shadow
resolution, the B3 Swift fallback recipe end-to-end at probe level, store-path existence,
manifest hash recomputation, revision ancestry checks, trap check. **All passed** except the
two expected negatives recorded (swiftc without LD_LIBRARY_PATH rc=127; typecheck without
SDK tree rc=1) and the manifest 13/30 mismatch.

**The recipe says (not run):** the four stage commands (`boring gen` ×2 groups,
`boring test` ×2, `boring compare` ×2) — not run because they write into the locked Tiqian
worktree, take on the order of the full matrix, and one obligation (protocol-c afterGen)
needs authorization I do not hold. **Not run — not faked.**

**Also not run:** the full Boring suite (forbidden, ~29 min); any `nix develop` shell in the
consumer checkout (would materialize/write; unnecessary given direct store-path probes).

## 5. Revision-pair statement

- **Tiqian side: FIXED and verified** — `8504d230228e8206689a2049bbb84b671c1f079a`, exact
  detached HEAD of the locked checkout, tracked tree clean.
- **Boring side: STILL UNDECIDED, and the ground has shifted again.** Runbook says
  `2159c657` (now 10 commits behind HEAD `0a5c42a7`); the audit's alternative `e1c65975` is
  now itself superseded by `0a5c42a7` ("baseline"), which additionally commits the runbook,
  f32 example HXMLs, and further Rust/Swift/Dart compiler changes. Consequences:
  1. The prepared artifacts (snapshot `fixed-compiler-2159c657`, 12 prep HXMLs, 3 project
     JSONs, prep haxelib) are pinned to `2159c657` and remain internally consistent — but a
     gate run on them would freeze a candidate that predates both Rust fixes *and* the
     additional `0a5c42a7` compiler work. That contradicts the evident intent of "baseline".
  2. Choosing `e1c65975` instead requires the alternate staging snapshot
     (`publication-staging/fixed-compiler-e1c65975`, present, 26 top-level entries) and the
     second prep tree (`tiqian/out/p09-e1c65975-round2-prep/`) — a full re-preparation, none
     of whose per-file hashes I verified.
  3. Choosing current HEAD `0a5c42a7` has **no prepared snapshot or prep tree at all**.
- **Native flake pin divergence:** Tiqian's own flake pins `304ed70c` (divergent lineage, 150
  commits off the candidate line). Any P09 run is valid only under the prep-haxelib shadow;
  the runbook already mandates this, and I verified the shadow resolves correctly.

**Therefore: the pair is half-fixed. The Boring side is the single open decision; without it
no stage command may legitimately be run.**

## 6. Decider's minimum (everything cited exists on disk)

1. **Decide the pair and write it down**: Tiqian `8504d230228e8206689a2049bbb84b671c1f079a` ×
   Boring `2159c657` (prepared; excludes subsequent compiler work) **or** `e1c65975`
   (alternate snapshot prepared) **or** re-select at current HEAD (requires a fresh staging
   snapshot + re-preparation). Specified by: runbook §Fixed revision pair; scope-audit §6 C1.
2. **Resolve the 13 drifted original hashes**: re-pin or record the drift before the run,
   since the runbook's own invariant check will fail on them (§3 above).
3. **Authorization decision for protocol-c afterGen** (B4), or run the matrix declaring that
   obligation `environment-not-reached` in the conclusion's uncovered-scope list (runbook §Review scope).
4. **Recording location** (two candidate `out/` trees, PLAN.md §7-D6) — and note both live
   inside Tiqian worktrees, so whoever runs it needs write access to the chosen one.
5. **Run, in the chosen Tiqian worktree, cwd = tree root**, PATH per
   `dc-warn/out/chainA-fixed-rerun/evidence/env.json` (all required store paths verified
   present, dart included): flake `nix develop -c` shell → override `HAXELIB_PATH` to the prep
   haxelib **in the same shell** → the four stage commands (runbook §Stage commands) with
   per-stage attempt directories retaining the full artifact set (runbook §Stage commands,
   last paragraph).
6. **Post-run invariants** (runbook §Invariant re-verification): 30-hash recomputation
   (see caveat in 2), 1366-entry inventory digest, `git status --short` clean in the consumer,
   both `git rev-parse HEAD`, driver sha `bf2450d3…` assert (I re-confirmed the driver hash
   today). Conclusion may cite only the pair, the per-bundle JSONL test-ID sets, and the
   invariant re-verification; the uncovered scope must list protocol-c afterGen, the driver
   residual (roots/--output), the frozen-out post-2159c657 compiler work, and any aborted stage.
7. **Agent-side report** at a new `dc-warn/out/<name>/REPORT.md`, mirroring the chain-A convention.

**Document gaps now remaining:** the work plan still names neither the runbook nor the
preparation review; the runbook is now committed (gap closed) but is stale on B3/dart (both
closed in reality) and on B1 (10 commits of drift). These staleness items should be amended
in a follow-up commit before someone executes §6.5 cold.

## 7. Explicit not-run list

- All four matrix stage commands (`boring gen/test/compare` on the fixed projects) — **not run**; blocker: writes into the locked `tiqian-validation-round2` worktree; B4 authorization; Boring-side revision undecided.
- `bun engine-haxe/out/protocol-c/gen/c-header.js` (protocol-c afterGen) — **not run**; blocker: `requires-execution-authorization`.
- Any `nix develop` shell in the consumer checkout — **not run** (write/materialization; not needed for the probes).
- Full Boring suite — **not run** (forbidden by task constraints).
- Verification of the `e1c65975` alternate prep tree's hashes — **not done** (out of scope; noted as required if that side of the decision is taken).

## 8. Method and limits

Exit codes captured directly (never through pipes). Nothing outside this output directory and
`/tmp` was written; the Tiqian worktree, both repositories, and the coordination tree are
untouched (trap file intact = 5). Raw evidence: `evidence/inputs-and-revisions.txt`,
`store-paths.txt`, `probes-run.txt`, `manifest-hash-recompute.txt`, `pf-*.out/err`.
