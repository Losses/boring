#!/usr/bin/env bash
# governance-sweep: §3.4 item 4 periodic stop/cancel sweep.
#
# Lists three object classes (see docs/architecture/GOVERNANCE-SWEEP.md):
#   1. stale candidates  — revisions still recorded as frozen in REFREEZE.md that a
#                          management ruling has sealed/rejected;
#   2. dead board rows   — status=doing rows whose branch exists neither locally nor on
#                          origin (sub-classified by two ordered evidence tiers:
#                          DEAD-MERGED via commit reachability, DEAD-MERGED-INFERRED via
#                          a labelled path-inference fallback for deleted branches, or
#                          DEAD-UNMERGED = no evidence the work reached the mainline);
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
#   SWEEP_MBASE  provenance anchor used by the class-2 path-inference tier (default:
#                b1188eec, the disaster start). It is no longer a scan window; it must
#                resolve to a readable commit or the sweep fails closed.
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

# class 2's fallback tier needs the anchor as a *readable commit*: without it, "this path did
# not exist at the anchor" cannot be decided, and every declared path would look like new
# content. An unresolvable anchor is a fail-closed stop.
ANCHOR="${SWEEP_MBASE:-b1188eec}"
git -C "$REPO" rev-parse --verify --quiet "$ANCHOR^{commit}" >/dev/null \
  || fail "SWEEP_MBASE not resolvable as a commit: $ANCHOR"
command -v awk >/dev/null 2>&1 || fail "awk not found in PATH"

STALE=0; DEAD_UNMERGED=0; DEAD_MERGED=0; DEAD_MERGED_INFERRED=0; EMPTY_BRANCH=0; ORPHAN=0

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
# "the branch is gone" is not the same fact as "the work is gone". Two ordered evidence
# tiers decide it, and the printed verdict always names the tier that decided it:
#
#   tier 1 reachability   A merge commit reachable from MAIN records the branch in the
#                         merged-in-branch position ("Merge branch '<br>'..." /
#                         "merge: <br> ..." / "merge: integrate <br> (...)"). MAIN's graph
#                         then holds the branch's commits: the merge's last parent is the
#                         last-seen branch tip and is re-checked with
#                         `git merge-base --is-ancestor <tip> <MAIN>`.
#   tier 2 path inference No recorder merge exists, usually because the work was recorded
#                         under an *aggregating* branch name, or because it reached the
#                         mainline before the anchor. Fall back to the row's own declared
#                         artifacts: a path named by its description/SOP that exists on MAIN
#                         and did NOT exist at the anchor (content older than the anchor
#                         cannot be this row's delivery), attributed to a reachable adding
#                         commit. This tier is an inference; it is not proof, hence the
#                         distinct verdict label.
#
# Both tiers read the WHOLE mainline history. The old window mbase..MAIN was blind: merges
# recorded before the anchor (e.g. "Merge branch 'warn/kotlin' into warn/zero") are
# ancestors of the anchor and were invisible, so already-merged work read as "home unknown".
# Formerly "DEAD-UNMERGED" now means: neither tier found evidence.
echo "-- class 2: dead board rows (status=doing, branch absent locally and on origin)"
# Field delimiter is US (0x1f). TAB is IFS whitespace, so `read` would drop the empty branch
# field of an EMPTY-BRANCH row and shift the row text into it.
rc=0; rows=$(jq -r '.tasks[]
  | select(.status=="doing")
  | [ .id, (.branch // ""),
      ([ (.description // ""), ((.sop // [])[] | (.text // ""), (.evidence // "")) ]
       | join(" ") | gsub("[\\n\\t\\r]+"; " ")) ]
  | join("\u001f")' "$BOARD") || rc=$?
[ "$rc" -eq 0 ] || fail "jq failed on board file (rc=$rc)"
total_doing=$(printf '%s\n' "$rows" | grep -c . || true)

# mainline merge records, read ONCE (newest first): <sha> TAB <parents> TAB <subject>
MERGES=$(mktemp) || fail "mktemp failed"
trap 'rm -f "$MERGES"' EXIT
rc=0; git -C "$REPO" log --merges --format='%H%x09%P%x09%s' "$MAIN" >"$MERGES" 2>/dev/null || rc=$?
[ "$rc" -eq 0 ] || fail "git log --merges $MAIN failed (rc=$rc)"
[ -s "$MERGES" ] || fail "no merge commits reachable from $MAIN"

# recorder_merges <branch>: every mainline merge whose SUBJECT carries the branch in the
# merged-in position. Exact token only ('warn/r1' must not match 'warn/r10'), and a mention
# inside an unrelated subject does not count. Bodies are deliberately left out of the search:
# a mention in a commit body does not record a merge. Positions accepted (all attested in
# this repo's history): "Merge branch '<br>'...", "merge: <br> ...",
# "merge: integrate <br> (...) into ...".
recorder_merges() {
  awk -F'\t' -v br="$1" -v p1="Merge branch '" -v q="'" '
    {
      subj = $3
      keep = 0
      if (index(subj, p1 br q) > 0) keep = 1
      else {
        n = split(subj, w, /[ \t]+/)
        if (n >= 2 && w[1] == "merge:" && w[2] == br) keep = 1
        else if (n >= 3 && w[1] == "merge:" && w[2] == "integrate" && w[3] == br) keep = 1
      }
      if (keep) print
    }' "$MERGES"
}

# path_evidence <row-text>: declared artifacts that exist on MAIN, are absent at the anchor,
# and can be attributed to a reachable adding commit -> one "path(add-sha)" per line.
PATH_RE='[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)+\.(hx|hxml|ts|tsx|js|mjs|sh|json|jsonl|md|kt|kts|rs|dart|swift|toml|yml|yaml|txt|tsv)'
path_evidence() {
  printf '%s' "$1" | grep -oE "$PATH_RE" | sort -u | head -40 | while IFS= read -r p; do
    [ -n "$p" ] || continue
    git -C "$REPO" cat-file -e "$MAIN:$p" 2>/dev/null || continue
    git -C "$REPO" cat-file -e "$ANCHOR:$p" 2>/dev/null && continue
    add=$(git -C "$REPO" log --diff-filter=A -1 --format=%h "$MAIN" -- "$p" 2>/dev/null | head -1)
    [ -n "$add" ] || continue
    printf '%s(%s)\n' "$p" "$add"
  done
}

while IFS=$'\x1f' read -r id br blob; do
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
  # tier 1: a recorder merge in MAIN's history already holds the branch's commits
  rm=""
  rc=0; rm=$(recorder_merges "$br") || rc=$?
  [ "$rc" -eq 0 ] || fail "merge-record lookup failed for $br (rc=$rc)"
  if [ -n "$rm" ]; then
    rec_n=$(printf '%s\n' "$rm" | grep -c . || true)
    line=$(printf '%s\n' "$rm" | head -1)
    msha=$(printf '%s' "$line" | cut -f1)
    mpar=$(printf '%s' "$line" | cut -f2)
    msub=$(printf '%s' "$line" | cut -f3)
    tip=""
    for p in $mpar; do tip=$p; done
    if [ -n "$tip" ] && git -C "$REPO" merge-base --is-ancestor "$tip" "$MAIN" 2>/dev/null; then
      echo "   DEAD-MERGED: $id  branch=$br  basis=reachability  merge=$msha \"$msub\"  tip=$tip (merge's last parent)  recorder-merges=$rec_n"
      DEAD_MERGED=$((DEAD_MERGED+1))
    else
      echo "   DEAD-UNMERGED: $id  branch=$br  (recorder merge $msha names the branch but its merged-in parent does not reach $MAIN; fail-closed)"
      DEAD_UNMERGED=$((DEAD_UNMERGED+1))
    fi
    continue
  fi
  # tier 2: no recorder merge -> labelled inference from the row's declared artifacts
  ev=""
  rc=0; ev=$(path_evidence "$blob") || rc=$?
  [ "$rc" -eq 0 ] || fail "path-evidence lookup failed for $br (rc=$rc)"
  if [ -n "$ev" ]; then
    ev_n=$(printf '%s\n' "$ev" | grep -c . || true)
    ev_list=$(printf '%s\n' "$ev" | head -3 | tr '\n' ' ')
    echo "   DEAD-MERGED-INFERRED: $id  branch=$br  basis=path-inference  paths=$ev_list (declared artifacts on $MAIN, absent at anchor $ANCHOR; hits=$ev_n)"
    DEAD_MERGED_INFERRED=$((DEAD_MERGED_INFERRED+1))
  else
    echo "   DEAD-UNMERGED: $id  branch=$br  (no recorder merge on $MAIN, no declared artifact that is new at anchor $ANCHOR; work home unknown)"
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
echo "dead rows (unmerged): $DEAD_UNMERGED  dead rows (merged): $DEAD_MERGED  dead rows (merged, path-inference): $DEAD_MERGED_INFERRED  empty-branch rows: $EMPTY_BRANCH"
echo "orphan worktrees:   $ORPHAN"
total=$((STALE + DEAD_UNMERGED + DEAD_MERGED + DEAD_MERGED_INFERRED + EMPTY_BRANCH + ORPHAN))
if [ "$total" -gt 0 ]; then
  echo "RESULT: $total object(s) need governance action (exit 1)"
  exit 1
fi
echo "RESULT: clean — no objects in any class (exit 0)"
exit 0
