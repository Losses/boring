# merge-precheck: the pre-merge three-check gate

`check.sh <branch> [--into <base>]` prints a PASS/FAIL line per check and a
final verdict (exit 0 only if all three pass). Recovery plan section 3.4 item
1: no branch merges on "the text applies cleanly" alone.

## The three checks

1. **Board** (`PASS board:`) - the branch has a workspace-board row and its
   `status` is `done`. A `doing` row (or no row at all) fails: work still on a
   branch is not finished work.
   - Command shape: read `status` from the row whose `branch` equals the
     argument in `.workspace-board/board.json` (override with `TQ_BOARD_JSON`;
     the script walks up from the repo root to find it).
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

## Examples

    # blocked: row still doing, no signed merge
    tools/merge-precheck/check.sh warn/ts3

    # specify a non-default target branch
    tools/merge-precheck/check.sh <branch> --into arch/agent-guided-governance
