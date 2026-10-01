# P12 programme review — method report

Deliverable: `PROGRAMME-REVIEW.md` (the draft, five sections). This file records method,
what was and was not established, and blockers. Date: 2026-09-30.

## Mandate

Draft the P12 programme review: (1) programme review against the two architecture
consultations and the audit, with document+section citations for every claim about what a
consultation said; (2) accepted revisions, strictly (board done rows + formally accepted
revisions; a patch in a scratch worktree is not accepted); (3) consolidated evidence gaps,
quoted not re-derived; (4) next scheduled mechanisms, or a statement that the plan does not
name one; (5) the closure question from the gates' state. Consolidation from retained
evidence only: no repository writes, no plan/report modifications, no re-run of the
consults' work.

## Method

1. **Plan.** Read `boring-wt-architecture/docs/architecture-work-plan.md` in full (453
   lines). Extracted verbatim into `evidence/plan-extracts.md`: goal and the five
   completion criteria (lines 18-34), the P08-P12 gate list (216-226), the P11 gate
   (222-224), the gate-dependency text (228-240), the status paragraphs on open gates and
   Tiqian (108-134, 173-190), the delivery table (99-106), and the acceptance-rule
   context (414-418). P12 (lines 225-226) quoted verbatim in the review; it is unchecked.
2. **Consultations.** Read in full: `dc-warn/out/sol-architecture-consult/{SOL2-ARCH-ANSWER.md,
   ASTRA-ANSWER.md, CODEX-AUDIT.md, CODEX-ARCH-ANSWER.md}` plus `QUESTION.md` for context.
   Verbatim copies in `evidence/consult/`. SOL-ANSWER.md was NOT read (not among the
   named sources; it is referenced inside CODEX-ARCH-ANSWER.md, whose reference I cite as
   such).
3. **Board.** `wb_board milestone=m-mulwvr32-3jht` (snapshot `updatedAt
   2026-09-30T15:18:41.870Z`; 75 open rows; `branches.mode: noop` with `spawnSync but
   ENOENT`, so the board's git backend saw nothing). Full `wb_task_show` on three rows:
   `t-munu29i9-70b7` (W1 — read the complete confirm record, SOP evidence, claims and
   timeline), `t-munq08t2-rgxp` (the P08 gate row — description and SOP criteria),
   `t-muo92xms-s28t` (the W1 residual ruling row). The 33 done rows were transcribed
   handle-by-handle into `evidence/board-m-mulwvr32-3jht.md` from the snapshot.
    A second `wb_board` query (`status=todo` and `status=doing`, same `updatedAt`, i.e.
    the board state had not moved) let me verify every open-row branch name cited in
    review §1.2(i); the full open-row transcription (21 todo + 26 doing) is in the same
    evidence file.
4. **My own read-only verification in the repository** (no writes; `boring-wt-architecture`
   treated as read-only):
   - `git rev-parse HEAD` = `e1c6597514634fd347d392709793cc19bd96c9a2`; branch
     `arch/agent-guided-governance`; `git status --porcelain` = 25 entries; `git log
     --oneline -15`; and `git log --oneline --all` grepped for the eleven
     plan-recorded integrated commits (the delivery table at :99-106 plus `cde5e97c`
     at :160) and `2159c657` — all present. Recorded in
     `evidence/git-verification.txt`.
   - `.github/workflows/ci.yml` (both "Run generation and tests" steps, lines 35 and 135)
     and `package.json` scripts: confirmed the CI chain contains no bare `test` invocation
     (`"test": "bun test tests/ packages/registry/tests/"`, line 9). Recorded in
     `evidence/ci-and-scripts.txt`.
   - `docs/investigations/architecture-round-1.md` lines 263-279 (work order) and
     `x-guidance-evaluation.md` line 95 (P11 acceptance) — verbatim in
     `evidence/round1-workorder-p11.md`.
   - `docs/investigations/architecture-round-2/candidate-integration-queue.md` read in
     full (79 lines).
5. **Retained reviews and cross-checks (read, not re-run):** `dc-warn/out/freeze-xcheck/REPORT.md`
   (full), `dc-warn/out/p08-implementation-review/REPORT.md` (full, incl. verdict and
   conditions), `dc-warn/out/p08-behaviour-review/REPORT.md` (Q5 table, §8, claim ledger),
   `dc-warn/out/p08-candidate-freeze/FREEZE.md` (status line, §0, §8 references),
   `dc-warn/out/gap-fixture-archive/README.md` (the "collected by nothing" section,
   lines 150-170). Verbatim copies of the four large reports in `evidence/`.
6. **Writing.** `dc-warn/` is a `fuse.rclone` mount (no symlinks, exec bits dropped); all
   files were written with `bash` + `cat >`.

Labels used in the review: **[DOC: source]** = a document states it (I quote, I did not
re-verify); **[VERIFIED]** = I checked it myself in this session; **[NOT ESTABLISHED]** =
not established, with blocker and establishing means named.

## What I verified myself

- The P12 gate text and the five completion criteria, verbatim, in the plan file.
- HEAD/branch/dirty-count of the coordination tree; presence in history of the eleven
  plan-named integrated commits and of `2159c657`; that the two most recent commits are
  the integrations of the two accepted Rust fix rows.
- That both CI jobs omit the bare `test` script that would collect `tests/**`, and that
  the script exists in `package.json:9`.
- The plan work order (architecture-round-1.md:263-279) and the P11 acceptance line
  (x-guidance-evaluation.md:95).
- The FREEZE.md status line ("the acceptance is not complete"; "does not accept the
  candidate"), the freeze-xcheck CONFIRMED verdict and F1-F3, the implementation review's
  REJECT verdict and four open conditions (by reading the reports).
- The W1 row's full confirm record (coordinator confirmation with independent
  reproduction; explicit out-of-scope note for the build-phase warning).
- The P08 board row's state (todo, 0/3, unclaimed, created 2026-09-30T06:24) and the
  board snapshot's done-row list (33 rows), cancelled row (1), and absence of any P09/P10/
  P12 gate row.
- The open-row branch names cited in review §1.2(i) (roots-guard defeat-classes and
  hardening rows, `chore/dedupe-hxml-roots`, `chore/archive-xs-fixture-family`,
  `chore/option-c-attempt-prune`, `fix/rust-string-expectation-family`,
  `fix/rust-module-keyed-read-sites`, `fix/test-timeout-budget`, the
  runner-identity/provenance rows) [VERIFIED: wb_board re-query, same snapshot
  `updatedAt: 2026-09-30T15:18:41.870Z`].

## What I could not establish (with what would establish it)

1. **Integration of the W1 fix into the coordination tree / the frozen P08 candidate.**
   The confirm record says it was verified in the `w1-wt` worktree; no W1 commit appears
   in the tree history and the frozen candidate predates the acceptance. What would
   establish it: a commit in `boring-wt-architecture` or a new freeze record whose bytes
   include the W1 change.
2. **The exact accepted bytes of the other 32 done rows.** I read their titles, SOP
   evidence lines and the board's done status; I did not read each confirm record. What
   would establish it: `wb_task_show` per row (the confirm text).
3. **The P09 baseline budget decision (owner + funded recovery, standard retained).** No
   such decision appears in the plan, the round-2 queue, or the board snapshot. What would
   establish it: a recorded owner decision (plan/queue/board).
4. **Current Tiqian availability, routing and any current fixed-pair evidence.** The
   consults leave it unestablished and I re-ran nothing. What would establish it: a fresh
   P09 stage record per the CODEX-ARCH Part 1 §5 table.
5. **Current state of the four scratch repairs** (string-family-fix,
   test-timeout-budget, rust-modkey-fix, roots-guard-f2). The CODEX-AUDIT descriptions are
   2026-09-30 document claims; I did not re-inspect the scratch trees. What would
   establish it: re-inspection of the scratch trees and the coordination tree.
6. **Whether P08-P10 ever closed temporarily.** [DOC: CODEX-AUDIT §6] "I did not establish
   that none ever closed temporarily." What would establish it: gate-status history and
   coordinator acceptance records (the audit's §6 inspection list).
7. **The mapping of the four done comparison-consumer re-review rows to the `2159c657`
   integration bytes.** I verified the commit exists; I did not verify row-by-row byte
   identity. What would establish it: the rows' confirm records + the commit diff.
8. **The current content of the boundary record (`RECORD.md`).** It drifted through
   revisions during the reviews (131 → 170 → 186 → 279 lines per the audit; the behaviour
   review measured 367 lines / a different hash and it changed mid-session per its §8).
   It is not one of my named sources; the consults' audits of the earlier revisions stand.
   What would establish it: a fresh pinned-hash read.
9. **The full sign-off content of `audit/p09-fixed-matrix-preparation`** (done, but what
   exactly its acceptance covered beyond the preparation title). What would establish it:
   its confirm record.

## Unverifiable items, with blockers

- **Branch state as seen by the board.** The board's git backend returned `spawnSync but
  ENOENT` (`branches.mode: noop`); the board can establish nothing about branches.
  Workaround: I verified commit history directly in the repository instead.
- **Executed evidence.** This review is consolidation from retained evidence; per mandate
  I re-ran no builds, tests or CI. All execution results cited belong to their recorded
  inputs (the consults and reviews each say the same about themselves, e.g.
  [DOC: SOL2 "Limits of this judgement"; CODEX-AUDIT closing paragraph]).
- **fuse.rclone mount limits.** `dc-warn/` drops exec bits and does not allow symlinks;
  all deliverables are plain files written with `cat >`. No impact on content.

## Files

- `PROGRAMME-REVIEW.md` — the draft (sections 1-5 as mandated).
- `REPORT.md` — this file.
- `evidence/plan-extracts.md` — verbatim plan passages with file sha256.
- `evidence/board-m-mulwvr32-3jht.md` — done-row transcription, open-row transcription
  (21 todo + 26 doing) and gate-naming rows, from the wb_board snapshot (re-queried at
  the same `updatedAt`).
- `evidence/git-verification.txt` — my git reads (HEAD, branch, dirty count, log, commit
  presence).
- `evidence/ci-and-scripts.txt` — my ci.yml/package.json reads (the collection gap).
- `evidence/round1-workorder-p11.md` — verbatim work order + P11 acceptance line.
- `evidence/consult/` — verbatim copies of QUESTION.md, SOL2-ARCH-ANSWER.md,
  ASTRA-ANSWER.md, CODEX-AUDIT.md, CODEX-ARCH-ANSWER.md.
- `evidence/freeze-xcheck-REPORT.md`, `evidence/p08-implementation-review-REPORT.md`,
  `evidence/p08-behaviour-review-REPORT.md`,
  `evidence/p08-candidate-freeze-FREEZE.md` — verbatim copies of the retained reports.
