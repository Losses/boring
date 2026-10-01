#!/usr/bin/env bash
# merge-precheck: three independent checks that must pass before a branch merge
# (disaster recovery plan section 3.4 item 1: the pre-merge three-check gate).
#
# Usage:
#   tools/merge-precheck/check.sh <branch> [--into <base-branch>]
#
# The three checks, all required:
#   1. board   the branch's workspace-board row exists and its status is done
#   2. ruling  the branch base (merge-base of branch and its target) is an
#              ancestor of the latest ruling commit - i.e. no ruling newer than
#              the base invalidates the work; rulings are read from
#              docs/architecture/MANAGEMENT-RULING-*.md and docs/architecture/rulings/
#   3. signoff the board row's merges field carries a non-empty confirm
#              (produced by wb_merge confirm=)
#
# Textual conflict-freeness is never a pass reason here. This script contains
# no merge-tree and no merge --no-commit logic by design; a merge that is
# merely textually clean does NOT pass this gate.
#
# Board location: the nearest .workspace-board/board.json found walking up
# from the repository root, but a board that lies inside the repository being
# evaluated is refused. The board is the workspace-level record of what has
# been signed off; a candidate that commits its own .workspace-board/board.json
# would otherwise supply the evidence for its own sign-off, and because the
# forgery is committed it leaves no working-tree clue to catch afterwards
# (r56c review). Only a board outside the candidate repository is authoritative.
# There is no env-var override (TQ_BOARD_JSON was removed in r56rr review: it
# was a false-green attack surface that could extract a PASS from a forged
# board placed inside the worktree).

set -u

usage() { echo "usage: $0 <branch> [--into <base-branch>]" >&2; exit 2; }

[ $# -ge 1 ] || usage
BRANCH=$1; shift
INTO_OVERRIDE=""
while [ $# -ge 1 ]; do
  case "$1" in
    --into) INTO_OVERRIDE=${2:-}; shift 2 ;;
    *) usage ;;
  esac
done

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
REPO=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel) || { echo "FAIL repo: not inside a git repository"; exit 1; }

BOARD=${TQ_BOARD_JSON:-}
if [ -z "$BOARD" ]; then
  dir=$REPO
  while :; do
    if [ -f "$dir/.workspace-board/board.json" ]; then
      # A board inside the repository under evaluation is not authoritative:
      # the candidate could have committed it and forged its own sign-off.
      case "$dir/.workspace-board/board.json" in
        "$REPO"/*)
          echo "FAIL board: refusing $dir/.workspace-board/board.json - the board is inside the repository under evaluation ($REPO), where a candidate could commit a forged copy and supply its own sign-off"
          exit 1 ;;
      esac
      BOARD=$dir/.workspace-board/board.json; break
    fi
    [ "$dir" = "/" ] && break
    dir=$(dirname "$dir")
  done
else
  # TQ_BOARD_JSON was an attack surface (r56rr review).
  # Reject it with a hard FAIL.
  echo "FAIL board: TQ_BOARD_JSON override is no longer supported (removed after r56rr security review)"
  exit 1
fi
if [ -z "$BOARD" ] || [ ! -f "$BOARD" ]; then
  echo "FAIL board: workspace-board/board.json not found walking up from $REPO"
  exit 1
fi

# Read the board row for the branch. Fields: found, status, baseBranch, confirm.
read -r ROW_STATUS ROW_BASE ROW_CONFIRM <<EOF
$(python3 - "$BOARD" "$BRANCH" <<'PY'
import json, sys
board, branch = sys.argv[1], sys.argv[2]
rows = [t for t in json.load(open(board)).get("tasks", [])
        if (t.get("branch") or "") == branch]
if not rows:
    print("NOTFOUND - -")
else:
    r = rows[0]
    confirm = "yes" if any((m.get("confirm") or "").strip()
                           for m in (r.get("merges") or [])) else "no"
    print(r.get("status") or "-", r.get("baseBranch") or "-", confirm)
PY
)
EOF

FAILS=0
note() { echo "$1"; case "$1" in FAIL*) FAILS=$((FAILS+1));; esac; }

# Check 1: board row status.
if [ "$ROW_STATUS" = "NOTFOUND" ]; then
  note "FAIL board: no board row carries branch '$BRANCH' in $BOARD"
else
  if [ "$ROW_STATUS" = "done" ]; then
    note "PASS board: row status is done"
  else
    note "FAIL board: row status is '$ROW_STATUS' (needs done; a doing or todo row is not mergeable)"
  fi
fi

# Check 2: ruling timeline - branch base must not predate the latest ruling commit.
LATEST=$(git -C "$REPO" log -1 --format=%H -- 'docs/architecture/MANAGEMENT-RULING-*.md' docs/architecture/rulings/)
if [ -z "$LATEST" ]; then
  note "FAIL ruling: no ruling commits found under docs/architecture/"
else
  if ! git -C "$REPO" rev-parse --verify --quiet "refs/heads/$BRANCH" >/dev/null; then
    note "FAIL ruling: branch '$BRANCH' does not resolve in this repository"
  else
    INTO=${INTO_OVERRIDE:-$ROW_BASE}
    [ -n "$INTO" ] || INTO=master
    if ! git -C "$REPO" rev-parse --verify --quiet "refs/heads/$INTO" >/dev/null; then
      note "FAIL ruling: target branch '$INTO' does not resolve in this repository"
    else
      MB=$(git -C "$REPO" merge-base "$INTO" "$BRANCH")
      if git -C "$REPO" merge-base --is-ancestor "$MB" "$LATEST"; then
        note "PASS ruling: branch base $(git -C "$REPO" rev-parse --short "$MB") is an ancestor of latest ruling $LATEST"
      else
        note "FAIL ruling: branch base $(git -C "$REPO" rev-parse --short "$MB") predates latest ruling $LATEST - the branch was cut before the newest ruling and needs re-review against it"
      fi
    fi
  fi
fi

# Check 3: signoff via wb_merge confirm=.
if [ "$ROW_STATUS" = "NOTFOUND" ]; then
  note "FAIL signoff: no board row, therefore no signed merge record"
elif [ "$ROW_CONFIRM" = "yes" ]; then
  note "PASS signoff: merges field carries a non-empty confirm"
else
  note "FAIL signoff: merges field has no confirm entry (wb_merge with confirm= has not happened)"
fi

echo "----"
if [ "$FAILS" -eq 0 ]; then
  echo "VERDICT: PASS - $BRANCH may proceed to merge review"
  exit 0
else
  echo "VERDICT: FAIL - $BRANCH blocked by $FAILS of 3 checks"
  exit 1
fi
