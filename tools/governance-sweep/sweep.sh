#!/usr/bin/env bash
# governance-sweep: §3.4 item 4 periodic stop/cancel sweep.
#
# Lists three object classes (see docs/architecture/GOVERNANCE-SWEEP.md):
#   1. stale candidates  — revisions still recorded as frozen in REFREEZE.md that a
#                          management ruling has sealed/rejected;
#   2. dead board rows   — status=doing rows whose branch exists neither locally nor on
#                          origin (sub-classified: content already merged into the
#                          mainline vs. no known home);
#   3. orphan worktrees  — registered worktrees with a detached HEAD that are not
#                          active recovery work (recov-* branches are never orphans).
#
# Exit codes (fail-closed contract — the caller must distinguish these):
#   0 = the sweep ran and found none of the three classes;
#   1 = the sweep ran and found at least one object (findings printed);
#   2 = the sweep could NOT run (missing tool, missing path, failing git/jq command).
#       No "0 objects" output is ever produced on the failure path.
#
# Configuration (environment overrides):
#   SWEEP_REPO   git worktree/checkout of the boring repo   (default: this script's repo)
#   SWEEP_BOARD  path to .workspace-board/board.json        (default: sibling of repo root)
#   SWEEP_MAIN   mainline branch for merge classification  (default: arch/agent-guided-governance)
set -u

fail() { printf 'SWEEP-ERROR: %s\n' "$*" >&2; exit 2; }

REPO="${SWEEP_REPO:-$(cd "$(dirname "$0")/../.." && pwd)}"
BOARD="${SWEEP_BOARD:-}"
if [ -z "$BOARD" ]; then
  d="$REPO"
  while [ "$d" != "/" ]; do
    d=$(dirname "$d")
    if [ -r "$d/.workspace-board/board.json" ]; then BOARD="$d/.workspace-board/board.json"; break; fi
  done
  [ -n "$BOARD" ] || fail "no .workspace-board/board.json found above $REPO (set SWEEP_BOARD)"
fi
MAIN="${SWEEP_MAIN:-arch/agent-guided-governance}"

command -v git >/dev/null 2>&1 || fail "git not found in PATH"
command -v jq   >/dev/null 2>&1 || fail "jq not found in PATH"
git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || fail "not a git worktree: $REPO"
[ -r "$BOARD" ] || fail "board file not readable: $BOARD (set SWEEP_BOARD)"
REFREEZE="$REPO/docs/architecture/REFREEZE.md"
[ -r "$REFREEZE" ] || fail "REFREEZE.md not readable: $REFREEZE"

# mainline must resolve, or merge classification would silently mislabel everything
git -C "$REPO" rev-parse --verify --quiet "refs/heads/$MAIN" >/dev/null \
  || git -C "$REPO" rev-parse --verify --quiet "refs/remotes/origin/$MAIN" >/dev/null \
  || fail "mainline branch not resolvable: $MAIN"

STALE=0; DEAD_UNMERGED=0; DEAD_MERGED=0; EMPTY_BRANCH=0; ORPHAN=0

echo "== governance sweep @ $(git -C "$REPO" rev-parse HEAD) =="

# ---- class 1: stale candidates (frozen but sealed/rejected by a ruling) -------------
echo "-- class 1: stale candidates (frozen in REFREEZE.md, sealed by a ruling)"
# grep failure modes: 1=no match (fine, means no entry), 2=real error -> fail closed
rc=0; entries=$(grep -o 'Candidate revision: `[0-9a-f]\{8,\}`' "$REFREEZE") || rc=$?
[ "$rc" -le 1 ] || fail "grep on REFREEZE.md failed (rc=$rc)"
if [ -z "$entries" ]; then
  echo "   none: REFREEZE.md records no candidate revision"
else
  while IFS= read -r e; do
    sha=$(printf '%s' "$e" | sed 's/.*`\([0-9a-f]*\)`.*/\1/')
    # is there a ruling that seals/rejects this revision?
    hits=""
    for r in "$REPO"/docs/architecture/MANAGEMENT-RULING-*.md; do
      [ -e "$r" ] || fail "no MANAGEMENT-RULING-*.md files under $REPO/docs/architecture"
      if grep -q "$sha" "$r" && grep -qiE 'REJECT|sealed' "$r"; then
        hits="$hits $(basename "$r")"
      fi
    done
    if [ -n "$hits" ]; then
      echo "   STALE: candidate $sha frozen in REFREEZE.md but sealed by:$hits"
      STALE=$((STALE+1))
    else
      echo "   ok:    candidate $sha frozen, no sealing ruling found"
    fi
  done <<< "$entries"
fi

# ---- class 2: dead board rows (doing, branch gone locally + origin) -----------------
echo "-- class 2: dead board rows (status=doing, branch absent locally and on origin)"
rc=0; rows=$(jq -r '.tasks[]
  | select(.status=="doing")
  | (if (.branch // "") == "" then .id + "\t" else .id + "\t" + .branch end)' "$BOARD") || rc=$?
[ "$rc" -eq 0 ] || fail "jq failed on board file (rc=$rc)"
total_doing=$(printf '%s\n' "$rows" | grep -c . || true)
while IFS=$'\t' read -r id br; do
  if [ -z "$br" ]; then
    echo "   EMPTY-BRANCH: $id (doing row carries no branch field at all)"
    EMPTY_BRANCH=$((EMPTY_BRANCH+1))
    continue
  fi
  local_ok=0; origin_ok=0
  git -C "$REPO" rev-parse --verify --quiet "refs/heads/$br"        >/dev/null 2>&1 && local_ok=1
  git -C "$REPO" rev-parse --verify --quiet "refs/remotes/origin/$br" >/dev/null 2>&1 && origin_ok=1
  if [ "$local_ok" = 1 ] || [ "$origin_ok" = 1 ]; then
    continue
  fi
  # sub-classify: is the branch name in a mainline merge commit since the disaster base?
  mbase="b1188eec"   # first disaster merge commit; recoverable via SWEEP_MBASE
  mbase="${SWEEP_MBASE:-$mbase}"
  merged=""
  rc=0; merged=$(git -C "$REPO" log --merges --format=%s "$mbase..$MAIN" 2>/dev/null \
                 | grep -F "$br" | head -1) || rc=$?
  [ "$rc" -le 1 ] || fail "git log --merges failed (rc=$rc)"
  if [ -n "$merged" ]; then
    echo "   DEAD-MERGED:   $id  branch=$br  (content on $MAIN via: $merged)"
    DEAD_MERGED=$((DEAD_MERGED+1))
  else
    echo "   DEAD-UNMERGED: $id  branch=$br  (no merge record on $MAIN; work home unknown)"
    DEAD_UNMERGED=$((DEAD_UNMERGED+1))
  fi
done <<< "$rows"
echo "   (doing rows scanned: $total_doing)"

# ---- class 3: orphan worktrees (detached, not active recovery work) -----------------
echo "-- class 3: orphan worktrees (detached HEAD, not recov-*/active)"
wtlist=$(git -C "$REPO" worktree list --porcelain) || fail "git worktree list failed"
path=""
declare -A seen_paths
while IFS= read -r line; do
  case "$line" in
    "worktree "*) path="${line#worktree }" ;;
    "branch "*)   path="" ;;  # has a checked-out branch -> not detached
    "detached"*)
      base=$(basename "$path")
      case "$base" in
        recov-*) : ;; # active recovery worktrees are never orphans
        *)
          echo "   ORPHAN: $path (detached)"
          ORPHAN=$((ORPHAN+1)) ;;
      esac
      path="" ;;
  esac
done <<< "$wtlist"

# ---- summary ------------------------------------------------------------------------
echo "== summary =="
echo "stale candidates:   $STALE"
echo "dead rows (unmerged): $DEAD_UNMERGED  dead rows (merged): $DEAD_MERGED  empty-branch rows: $EMPTY_BRANCH"
echo "orphan worktrees:   $ORPHAN"
total=$((STALE + DEAD_UNMERGED + DEAD_MERGED + EMPTY_BRANCH + ORPHAN))
if [ "$total" -gt 0 ]; then
  echo "RESULT: $total object(s) need governance action (exit 1)"
  exit 1
fi
echo "RESULT: clean — no objects in any class (exit 0)"
exit 0
