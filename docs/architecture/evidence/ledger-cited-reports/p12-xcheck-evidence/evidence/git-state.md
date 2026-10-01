# XCHECK git-state evidence (read-only; taken 2026-09-30 ~11:45-11:55 local)

Repo: /home/losses/Development/tq-workspace/boring-wt-architecture
Branch: arch/agent-guided-governance

## Current HEAD (NEW since the review's anchor)

HEAD = 0a5c42a702d938ca4da39cbcefae2cc450e021fe
  subject: "baseline"
  author: wire
  date: Wed Sep 30 11:23:41 2026 -04:00 (= 15:23:41Z)

The review's anchor was e1c6597514634fd347d392709793cc19bd96c9a2 (top commit at review time,
2026-09-29). 0a5c42a7 sits directly on top of e1c65975 and postdates:
  - the board snapshot the review cites (15:18:41.870Z)
  - the W1 row confirmation (15:16:04.572Z)
  - the review's own REPORT.md mtime (11:29:10 local) and PROGRAMME-REVIEW.md mtime (11:42:47 local)

Dirty state: 21 porcelain entries (all " M" modified): SwiftExpr.hx + 19 test runner
scripts + tools/roots-guard/* + tools/git-hooks/commit-msg. (Review recorded 25 entries at
its anchor: 15 modified + 10 untracked.)

## What 0a5c42a7 "baseline" integrates (git diff e1c65975..0a5c42a7; 67 files, +2778/-29)

1. The frozen P08 candidate, byte-exact:
   - SwiftExpr.hx committed hash = bf7dde2cec3b89464738019c733eb6f1d8e666bbc976176bf30cc77007be6078
     = the candidate hash in p08-candidate-freeze/FREEZE.md section 6.2 ("the patched file"
     of INTEGRATION.diff).
   - SwiftArrayBoundary.hx and SwiftDecl.hx also carry the frozen worktree edits
     (worktree hashes b522865c.../... match the commit; e1c65975 versions differ).
   => The frozen candidate's bytes are for the first time in the coordination tree's history.

2. Board-accepted fix rows (row-to-commit mapping the review left [NOT ESTABLISHED]):
   - fix/dart-fallthrough-nullguard (t-mun3ejy5-16zz): DartExpr.hx fall-through promotion
     gate (+ dc-null-guard-fallthrough fixture).
   - fix/dart-nullguard-mutation-closure (t-mun44ta0-aw1p): DartExpr.hx
     nonNullLocals closure reset (ClosurePromotionReset probes p9/p11).
   - fix/rust-fault-variant-regression (t-mun8mco9-f8e2): RustExpr.hx declared-fault-enum
     growth lookup (PIT-248), + RustCompiler/RustDecl/RustEmissionState changes.
   - fix/swift-generated-tree-runtime (t-mun5d99p-op76): SwiftDecl.hx
     imports.runtime("BoringException") with an explicit code comment "(task t-mun5d99p-op76)".

3. W1 fix (t-munu29i9-70b7, done 15:16:04Z): NOT in 0a5c42a7.
   - Committed SwiftExpr.hx = bf7dde2c = pre-W1 (freeze record section 7.9: the
     switchExplicitReturn function is byte-identical base-vs-candidate, warnings unchanged).
   - `git log --all -S statementArms` and `git rev-list --all | xargs git grep statementArms`
     return nothing: the W1 fix (markers statementArms/valueIsReturn, present in
     dc-warn/out/w1-fix/PATCH.diff) was NEVER committed on any ref. It exists only in
     scratch (w1-wt worktree + PATCH.diff) and the board confirm record.
   - The review's [NOT ESTABLISHED] on W1 integration remains correct today.

4. Other: docs/investigations/architecture-round-2/p09-fixed-matrix-preparation-runbook.md
   (+309 lines, new; status: preparation-only-not-executed, generationStarted: false),
   new fixtures (try-tail, try-tail-min, swift-rt-plain, swift-rt-probe, dc-null-guard-fallthrough),
   tools (precision-guard/check.ts, roots-guard hardening), examples/*.hxml refresh,
   d-observation.md wording refresh.

## State inconsistency (flag)

Worktree SwiftExpr.hx sha256 = 0a9bed91ef91... = the e1c65975 BASE file (unpatched),
while HEAD's SwiftExpr.hx = bf7dde2c... (candidate). So the current working tree does NOT
contain the candidate patch in SwiftExpr.hx even though HEAD does; `git diff HEAD` for that
file is the inverse of INTEGRATION.diff. (Worktree SwiftArrayBoundary.hx/SwiftDecl.hx DO
match HEAD.) The p09-tiqian-feasibility report (11:47) independently observed the same 21
porcelain lines.

## Commit presence (all verified in current HEAD history via merge-base --is-ancestor)

f104e3bf, 4581308d, 3fb8c565, 5eb3429b, f3a8955a, 8a2a9c6a, d873da91, 8a9a8c49,
c4787f70, cde5e97c, 2159c657, e5e21854 — all present.
e5e21854 subject: "chore(architecture): checkpoint unfinished Swift arrays and policy
migration plan" (Mon Sep 28 02:20:36 2026 -0400).

## P09/Tiqian execution evidence search (optimistic falsification)

- docs/investigations/architecture-round-2/p09-fixed-matrix-preparation-runbook.md:
  "status: preparation-only-not-executed", "generationStarted: false". Fixed pair recorded:
  Boring 2159c657 + Tiqian 8504d230. Blockers B1 (Rust fixes frozen out), B3 (Swift
  libSystemPackage.so never built), B4 (protocol-c afterGen not authorised) open at writing.
- dc-warn/out/p09-tiqian-feasibility/REPORT.md (2026-09-30 11:47, post-review): matrix
  "not safely startable" (locked worktree + open B4); NEW: manifest invariant fails today
  (13 of 30 pinned original hashes mismatch); runbook now tracked (committed in 0a5c42a7).
- No P09 run results anywhere: board rows for P09 are prep/audit/doing only; no new
  done row since the review's snapshot (board updatedAt still 15:18:41.870Z).
- dc-warn/out dirs modified Sep 30 after the snapshot (in-flight, unaccepted): w1-fix,
  switchexpr-destination, lambda-return-contract, ci-collection-wire, record-cell-fix,
  p1-run-xcheck, p10-reflection (draft), p09-tiqian-feasibility, reanchor-v2,
  array-root-adjudication. None is an accepted gate result.
