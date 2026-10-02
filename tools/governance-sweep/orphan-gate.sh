#!/usr/bin/env bash
# orphan-gate.sh: disposition gate for orphan worktrees (governance §3.4 item 4).
#
# Judges whether an orphan tree can be REMOVED without losing anything not
# already integrated. One verdict line per tree:
#   REMOVABLE: every check below passed; nothing unlanded remains
#   PROTECTED(why): the tree still holds unique shared-style value
#                      (e.g. HEAD has commits not on mainline); do NOT delete
#                      before a human ports that content
#   NEEDS-DECISION(reason): a check could not be completed, or unique content
#                      exists only in this tree; fail-closed, never REMOVABLE
#
# Checks performed (in order), each of which can only lower the verdict:
#   C0. tree must be a boring-repo git worktree; a non-git dir only passes as
#       REMOVABLE if it matches a pure build-artifact pattern (out/, target/,
#       .haxelib/, node_modules/...)
#   C1. HEAD must be an ancestor of mainline (git merge-base --is-ancestor).
#       Commits ahead of main  -> PROTECTED (unique commits would be lost)
#   C2. every MODIFIED tracked file's blob must appear in some commit on any
#       ref (git hash-object + git log --all --find-object). For a static
#       analysis tree, a dirty blob that has ever been committed is assumed
#       preserved; a blob found in NO commit is unique-to-this-tree ->
#       NEEDS-DECISION.
#   C3. every UNTRACKED (non-ignored) file must either (a) be byte-identical
#       to the mainline version of the same path, or (b) exist with identical
#       content under one of the alternate roots (ORPHAN_ALT_ROOTS, e.g. the
#       dc-warn mirror or workspace archive dirs), or else NEEDS-DECISION.
#   Build-artifact subpaths (out/, target/, .haxelib/, node_modules/, *.log,
#   .DS_Store...) inside an otherwise git worktree are exempt from C2/C3.
#
# FAIL-CLOSED DIRECTION: any git/filesystem error, unreadable path, or
# unexpected command output yields NEEDS-DECISION. This script can never emit
# REMOVABLE on an error path: it is an advisory gate; deletion itself is
# always a separate, human-approved action.
#
# Usage:
#   orphan-gate.sh [--main <branch>] <tree-path> [<tree-path> ...]
# Env:
#   ORPHAN_MAIN      mainline branch (default arch/agent-guided-governance)
#   ORPHAN_REPO      repo used for git queries (default: the tree's own gitdir)
#   ORPHAN_ALT_ROOTS colon-separated extra roots scanned for duplicate
#                    untracked content (default: workspace root + dc-warn)
#   ORPHAN_MAX_FILES safety cap on untracked-file scan per tree (default 2000)
set -u

MAIN="${ORPHAN_MAIN:-arch/agent-guided-governance}"
ALT_ROOTS="${ORPHAN_ALT_ROOTS:-/home/losses/Development/tq-workspace:/home/losses/Development/tq-workspace/dc-warn}"
MAX_FILES="${ORPHAN_MAX_FILES:-2000}"

# pure build-artifact directory names (whole-tree verdict or per-path exemption)
is_artifact_name() {
  case "$(basename "$1")" in
    out|target|build|dist|.haxelib|node_modules|.cache|__pycache__|.gradle|.dart_tool) return 0 ;;
    *) return 1 ;;
  esac
}
is_artifact_file() {
  case "$(basename "$1")" in
    *.log|*.tmp|*.o|*.pyc|.DS_Store) return 0 ;;
    *) return 1 ;;
  esac
}

die() { printf 'NEEDS-DECISION %s (gate-internal error: %s)\n' "${TREE:-?}" "$*"; }

judge() {
  # canonicalize to an absolute path: git -C + a relative path can resolve
  # against the caller's cwd on linked worktrees, which would mis-hash blobs
  TREE=$(cd "$1" 2>/dev/null && pwd) || { printf 'NEEDS-DECISION %s (path missing/unreadable)\n' "$1"; return; }

  # ---- C0: git worktree? -----------------------------------------------
  if ! git -C "$TREE" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if is_artifact_name "$TREE"; then
      printf 'REMOVABLE %s (C0: not a git tree, pure artifact dir %s)\n' "$TREE" "$(basename "$TREE")"
    else
      printf 'NEEDS-DECISION %s (C0: not a git worktree and not a known artifact dir; manual inspection required)\n' "$TREE"
    fi
    return
  fi

  if ! git -C "$TREE" rev-parse --verify --quiet "refs/heads/$MAIN" >/dev/null 2>&1 \
     && ! git -C "$TREE" rev-parse --verify --quiet "refs/remotes/origin/$MAIN" >/dev/null 2>&1; then
    printf 'NEEDS-DECISION %s (mainline %s not resolvable from this worktree)\n' "$TREE" "$MAIN"
    return
  fi

  # ---- C1: HEAD ancestor of main? --------------------------------------
  HEAD=$(git -C "$TREE" rev-parse HEAD 2>/dev/null) || { die "rev-parse HEAD failed"; return; }
  if git -C "$TREE" merge-base --is-ancestor "$HEAD" "$MAIN" 2>/dev/null; then
    C1=OK
  else
    AHEAD=$(git -C "$TREE" rev-list --count "$MAIN..$HEAD" 2>/dev/null) || AHEAD="?"
    if [ "$AHEAD" = "?" ]; then die "rev-list count failed"; return; fi
    if [ "$AHEAD" -gt 0 ]; then
      printf 'PROTECTED %s (C1: HEAD %s has %s commit(s) not on %s, e.g. %s)\n' \
        "$TREE" "${HEAD:0:8}" "$AHEAD" "$MAIN" \
        "$(git -C "$TREE" log --format='%h %s' -1 "$HEAD" 2>/dev/null | cut -c1-60)"
    else
      # HEAD diverged: 0 ahead on this side while not an ancestor -> ambiguous
      printf 'NEEDS-DECISION %s (C1: HEAD %s is not an ancestor of %s but shows 0 commits ahead — divergent history, verify by hand)\n' "$TREE" "${HEAD:0:8}" "$MAIN"
    fi
    return
  fi

  # ---- status snapshot ---------------------------------------------------
  if ! STATUS=$(git -C "$TREE" status --porcelain=v1 -uall 2>/dev/null); then
    die "git status failed"; return
  fi
  MOD=$(printf '%s\n' "$STATUS" | grep -cE '^ ?[MDA]|^R' || true)
  UNTRACKED_LINES=$(printf '%s\n' "$STATUS" | grep -E '^\?\?' | sed 's/^?? //' || true)
  UTCOUNT=$(printf '%s\n' "$UNTRACKED_LINES" | grep -c . || true)

  # ---- C2: modified tracked blobs must exist on some ref ----------------
  RISK_MOD=0; OK_MOD=0; SAMPLE_MOD=""
  if [ "$MOD" -gt 0 ]; then
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      f=$(printf '%s' "$line" | sed 's/^...//' | sed 's/ -> .*//')
      case "$f" in *'['*']'*) continue ;; esac   # skip porcelain rename quoting edge
      full="$TREE/$f"
      [ -f "$full" ] || { RISK_MOD=$((RISK_MOD+1)); SAMPLE_MOD="$SAMPLE_MOD $f(unreadable)"; continue; }
      is_artifact_file "$full" && continue
      blob=$(git -C "$TREE" hash-object "$full" 2>/dev/null) || { RISK_MOD=$((RISK_MOD+1)); SAMPLE_MOD="$SAMPLE_MOD $f(hash-fail)"; continue; }
      if git -C "$TREE" log --all --format=%H --find-object="$blob" -n 1 >/dev/null 2>&1 \
         && [ -n "$(git -C "$TREE" log --all --format=%H --find-object="$blob" -n 1 2>/dev/null)" ]; then
        OK_MOD=$((OK_MOD+1))
      else
        RISK_MOD=$((RISK_MOD+1)); SAMPLE_MOD="$SAMPLE_MOD $f"
      fi
    done <<< "$(printf '%s\n' "$STATUS" | grep -E '^ ?[MD]|^R')"
  fi
  if [ "$RISK_MOD" -gt 0 ]; then
    printf 'NEEDS-DECISION %s (C2: %s/%s modified tracked blob(s) exist in NO commit on any ref: %s)\n' \
      "$TREE" "$RISK_MOD" "$MOD" "$(printf '%s' "$SAMPLE_MOD" | cut -c1-120)"
    return
  fi

  # ---- C3: untracked files must be reproducible elsewhere or on main ----
  RISK_UN=0; OK_UN=0; SAMPLE_UN=""
  n=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    n=$((n+1)); [ "$n" -gt "$MAX_FILES" ] && { RISK_UN=$((RISK_UN+1)); SAMPLE_UN="$SAMPLE_UN (scan-cap $MAX_FILES exceeded)"; break; }
    case "$f" in *'/') continue ;; esac          # untracked directory entries: expanded below not needed, dir content listed by -uall? we use default listing -> dirs appear with trailing /
    full="$TREE/$f"
    if [ -d "$full" ]; then continue; fi
    [ -f "$full" ] || { RISK_UN=$((RISK_UN+1)); SAMPLE_UN="$SAMPLE_UN $f(unreadable)"; continue; }
    is_artifact_file "$full" && { OK_UN=$((OK_UN+1)); continue; }
    h=$(sha256sum "$full" 2>/dev/null | cut -d' ' -f1) || { RISK_UN=$((RISK_UN+1)); SAMPLE_UN="$SAMPLE_UN $f(sha-fail)"; continue; }
    found=0
    # (a) identical to mainline blob at same path?
    mainblob=$(git -C "$TREE" rev-parse -q --verify "$MAIN:$f" 2>/dev/null) && [ -n "$mainblob" ] && {
      mh=$(git -C "$TREE" cat-file blob "$mainblob" 2>/dev/null | sha256sum | cut -d' ' -f1)
      [ "$mh" = "$h" ] && found=1
    }
    # (b) same content anywhere under alternate roots?
    if [ "$found" = 0 ]; then
      IFS=':' read -ra ROOTS <<< "$ALT_ROOTS"
      for r in "${ROOTS[@]}"; do
        [ "$found" = 1 ] && break
        [ -n "$r" ] || continue
        hits=$(find "$r" -type f -name "$(basename "$f")" -not -path "$full" -print -quit 2>/dev/null)
        [ -z "$hits" ] || {
          hh=$(sha256sum "$hits" 2>/dev/null | cut -d' ' -f1)
          [ "$hh" = "$h" ] && found=1
        }
      done
    fi
    if [ "$found" = 1 ]; then OK_UN=$((OK_UN+1)); else RISK_UN=$((RISK_UN+1)); SAMPLE_UN="$SAMPLE_UN $f"; fi
  done <<< "$UNTRACKED_LINES"

  if [ "$RISK_UN" -gt 0 ]; then
    printf 'NEEDS-DECISION %s (C3: %s/%s untracked file(s) exist nowhere else (not on %s, not in alt roots):%s)\n' \
      "$TREE" "$RISK_UN" "$UTCOUNT" "$MAIN" "$(printf '%s' "$SAMPLE_UN" | cut -c1-160)"
    return
  fi

  printf 'REMOVABLE %s (C1 HEAD=%s ancestor-of-%s; C2 0/%s risky mods; C3 0/%s risky untracked)\n' \
    "$TREE" "${HEAD:0:8}" "$MAIN" "$MOD" "$UTCOUNT"
}

MAIN_ARG=""
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --main) MAIN="$2"; shift 2 ;;
    --main=*) MAIN="${1#--main=}"; shift ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
[ ${#ARGS[@]} -gt 0 ] || { echo "usage: $0 [--main <branch>] <tree>..." >&2; exit 2; }

for t in "${ARGS[@]}"; do judge "$t"; done
