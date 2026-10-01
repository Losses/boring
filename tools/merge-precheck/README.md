# merge-precheck: the pre-merge three-check gate

`check.sh <branch> [--into <base>]` prints a PASS/FAIL line per check and a
final verdict (exit 0 only if all three pass). Recovery plan section 3.4 item
1: no branch merges on "the text applies cleanly" alone.

## The three checks

1. **Board** (`PASS board:`) - the branch has a workspace-board row and its
   `status` is `done`. A `doing` row (or no row at all) fails: work still on a
   branch is not finished work.
   - Command shape: read `status` from the row whose `branch` equals the
     argument in `.workspace-board/board.json`; the script walks up from the
     repo root to find the default board. There is no `TQ_BOARD_JSON`
     override — it was removed after the r56rr red-team review: pointing it
     at a forged board placed inside the worktree extracted a `VERDICT:
     PASS` for an unsigned branch, and the "`git status` shows it" defence
     was only an after-the-fact clue, not a control.
   - Pass criterion: `status == "done"`.

2. **Ruling timeline** (`PASS ruling:`) - the branch base must not predate the
   latest management ruling. A branch cut before the newest ruling has not
   been reviewed against it and is blocked.
   - Commands:
     `latest=$(git log -1 --format=%H -- 'docs/architecture/MANAGEMENT-RULING-*.md' docs/architecture/rulings/)`
     `mb=$(git merge-base <into> <branch>)`
     `git merge-base --is-ancestor "$mb" "$latest"`
   - Pass criterion: exit 0 (base is an ancestor of the latest ruling commit).

3. **Signoff** (`PASS signoff:`) - the board row's `merges` field carries a
   non-empty `confirm`, produced only by `wb_merge` with `confirm=` after
   review. A merge record without confirm is an unsigned claim.
   - Pass criterion: at least one entry in `merges` with non-empty `confirm`.

## What is deliberately absent

There is no textual merge test here - no `git merge-tree`, no
`merge --no-commit`. Textual cleanliness is never a pass reason; the gate is
process state (board, rulings, signoff), not conflict-freeness.

## Applicability: this gate constrains future merges only

On the real board as of 2026-10-01 the gate passes **zero** of the 271
branch-carrying rows - and that is accurate, not a bug: no merge record on
the board carries a `confirm` (PIT-477: `wb_merge` with `confirm=` is the
only signoff write path, and it has not been used on these branches), and
almost every branch base predates the latest ruling. The PASS path is
verified by creating a branch whose board row is `done` with a non-empty
`confirm` and whose base is an ancestor of the latest ruling (i.e. it was
cut or rebased after the ruling). Until the coordinator signs a row via
`wb_merge confirm=` (or a retro-signoff is ruled for the 17 historical
merges), expect FAIL on every real row; a FAIL is the gate doing its job,
not evidence that the gate is broken.

## Examples

    # blocked: row still doing, no signed merge
    tools/merge-precheck/check.sh warn/ts3

    # specify a non-default target branch
    tools/merge-precheck/check.sh <branch> --into arch/agent-guided-governance
