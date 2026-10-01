#!/usr/bin/env bash
# status-change: the section 3.4 item 2 three questions, made mechanical.
#
# Disaster recovery plan section 3.4 item 2 requires that every status change
# answer three questions before it is written:
#
#   1. which ruling authorizes this status change?
#   2. where is the evidence, as an in-repo path?
#   3. which tree does the conclusion hold for (a commit plus an is-ancestor
#      check)?
#
# The disaster's own root cause was that a status could be advanced with no
# point at which anyone had to answer those questions, so the change went
# through with nothing raising an alarm (the report's section 1.3 item 2).
# This script is that missing point: it refuses a status change whose three
# answers are absent or false.
#
# Q1 relevance, and its exact boundary. Q1 asks "which ruling authorizes this
# change?" A ruling that exists and is tracked but never mentions the branch or
# the commit being changed is not an answer to that question - it is merely a
# ruling. So, on top of "is a tracked ruling path", Q1 now also requires the
# ruling's committed content to contain a literal occurrence of the branch name
# or the tree commit sha (full or 12-char abbreviated). This is a weak,
# mechanical relevance gate: it proves the ruling NAMES the thing being
# changed, nothing more.
#
# What this gate catches: an unrelated ruling - one about a different subsystem
# or a different branch - that does not name this branch or this commit. That
# was the reported defect: a graphics ruling passed Q1 for an unrelated change.
#
# What this gate does NOT catch, by design: a ruling that names the branch but
# does not actually authorize the specific change on it. Whether a ruling that
# mentions a branch truly authorizes a given status change is a semantic
# judgement that cannot be made mechanically, so this script does not pretend
# to make it. The gate is a necessary condition for relevance (the ruling must
# at least name the subject), not a sufficient proof of authorization. A caller
# who needs the stronger guarantee must have a human confirm the ruling's
# operative text authorizes this exact change.
#
# Usage:
#   tools/status-change/check.sh <branch> --ruling <path> --evidence <path> \
#                                 --tree <commit> [--tree-base <commit>]
#
# Exit codes: 0 all three questions answered and verified
#             1 a question is unanswered, or its answer is false
#             2 usage error
#
# This script never edits the board. It answers "may this status change be
# written?", and the caller writes it. Keeping the check and the write apart is
# deliberate: a tool that both judged and wrote could not be audited by
# re-running it.

set -u

usage() {
  cat >&2 <<'USAGE'
usage: check.sh <branch> --ruling <path> --evidence <path> --tree <commit> [--tree-base <commit>]

  --ruling <path>      (Q1) in-repo path of the ruling that authorizes the change
  --evidence <path>    (Q2) in-repo path holding the evidence for it
  --tree <commit>      (Q3) commit the conclusion holds for
  --tree-base <commit> (Q3) base the tree must descend from (default: HEAD)
USAGE
  exit 2
}

[ $# -ge 1 ] || usage
BRANCH=$1; shift
RULING=""; EVIDENCE=""; TREE=""; TREE_BASE=""
while [ $# -ge 1 ]; do
  case "$1" in
    --ruling)     RULING=${2:-}; shift 2 ;;
    --evidence)   EVIDENCE=${2:-}; shift 2 ;;
    --tree)       TREE=${2:-}; shift 2 ;;
    --tree-base)  TREE_BASE=${2:-}; shift 2 ;;
    *) usage ;;
  esac
done

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
REPO=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel) || { echo "FAIL repo: not inside a git repository"; exit 1; }
[ -n "$TREE_BASE" ] || TREE_BASE=$(git -C "$REPO" rev-parse HEAD)

FAILS=0
note() { echo "$1"; case "$1" in FAIL*) FAILS=$((FAILS+1));; esac; }

# Q1: which ruling authorizes this change. The path must exist in the tree and
# must actually be a ruling, because "which ruling" answered with a
# non-ruling document is not an answer. And the ruling must actually be ABOUT
# this change: a tracked ruling that never mentions the branch or the commit
# being changed is not "the ruling that authorizes THIS change" - it is merely
# some ruling. Relevance is judged mechanically and weakly: the ruling's
# committed content must contain a literal occurrence of the branch name or
# the tree commit sha. That proves the ruling names the thing being changed; it
# does NOT prove the ruling semantically authorizes the change (see the header
# note for the exact boundary).
if [ -z "$RULING" ]; then
  note "FAIL Q1: no --ruling given; a status change must name the ruling that authorizes it"
else
  case "$RULING" in
    docs/architecture/MANAGEMENT-RULING-*.md|docs/architecture/rulings/*.md) ;;
    *) note "FAIL Q1: '$RULING' is not a ruling path (expected docs/architecture/MANAGEMENT-RULING-*.md or docs/architecture/rulings/*.md)" ;;
  esac
  # Content guard (PIT-487): "is a ruling" is judged by the file content. A
  # file that self-identifies as a test fixture is not a ruling even at a
  # ruling-shaped path. The self-identification lives in the header (first ~25
  # lines of the committed content).
  if git -C "$REPO" ls-files --error-unmatch "$RULING" >/dev/null 2>&1 \
     && git -C "$REPO" show "$TREE_BASE:$RULING" 2>/dev/null | head -25 \
        | grep -qiE '本文件.*测试夹具|this file.*test fixture'; then
    note "FAIL Q1: '$RULING' self-identifies as a test fixture, not a ruling or authorization"
  fi
  if git -C "$REPO" ls-files --error-unmatch "$RULING" >/dev/null 2>&1; then
    note "PASS Q1: ruling $RULING is tracked at $TREE_BASE"
    # Relevance: the ruling must name the change subject. Read the committed
    # content (the ruling is tracked, so its content is in the tree), and look
    # for a literal occurrence of the branch name or the tree commit sha.
    RULING_CONTENT=$(git -C "$REPO" show "$TREE_BASE:$RULING" 2>/dev/null || true)
    if [ -z "$RULING_CONTENT" ]; then
      note "FAIL Q1: cannot read ruling content at $TREE_BASE:$RULING"
    else
      RELEVANT=0
      if printf '%s' "$RULING_CONTENT" | grep -Fq -- "$BRANCH"; then
        RELEVANT=1
      fi
      if [ "$RELEVANT" -eq 0 ] && [ -n "$TREE" ]; then
        # The ruling may name the commit by the literal token the caller passed
        # (e.g. a 7-char abbreviation like ccfe6869) or by its full sha.
        if printf '%s' "$RULING_CONTENT" | grep -Fq -- "$TREE"; then
          RELEVANT=1
        elif FULL=$(git -C "$REPO" rev-parse --verify --quiet "$TREE^{commit}" 2>/dev/null); then
          if printf '%s' "$RULING_CONTENT" | grep -Fq -- "$FULL"; then
            RELEVANT=1
          else
            SHORT=${FULL:0:12}
            if printf '%s' "$RULING_CONTENT" | grep -Fq -- "$SHORT"; then
              RELEVANT=1
            fi
          fi
        fi
      fi
      if [ "$RELEVANT" -eq 1 ]; then
        note "PASS Q1: ruling $RULING names the change subject (branch '$BRANCH' or tree commit)"
      else
        note "FAIL Q1: ruling '$RULING' does not mention branch '$BRANCH' or tree commit '$TREE'; it cannot be the ruling that authorizes this change"
      fi
    fi
  else
    note "FAIL Q1: ruling '$RULING' is not a tracked file in this repository"
  fi
fi

# Q2: where the evidence lives, in-repo. An answer outside version control is
# how the disaster lost evidence: a scratch path that no longer exists cannot
# answer this question later. The path must be tracked, not merely present.
if [ -z "$EVIDENCE" ]; then
  note "FAIL Q2: no --evidence given; a status change must name an in-repo evidence path"
else
  case "$EVIDENCE" in
    /*) note "FAIL Q2: '$EVIDENCE' is absolute; evidence must be a repo-relative in-repo path" ;;
    ..*) note "FAIL Q2: '$EVIDENCE' escapes the repository" ;;
    dc-warn/*|*/dc-warn/*)
      note "FAIL Q2: '$EVIDENCE' is under dc-warn, which is outside version control; commit it first" ;;
  esac
  if git -C "$REPO" ls-files --error-unmatch "$EVIDENCE" >/dev/null 2>&1; then
    note "PASS Q2: evidence $EVIDENCE is tracked and in-repo"
  else
    note "FAIL Q2: evidence '$EVIDENCE' is not a tracked file; evidence kept outside version control is not evidence"
  fi
fi

# Q3: which tree the conclusion holds for. A commit must be named, and unless
# the caller says otherwise it must be an ancestor of the current HEAD, so a
# conclusion cannot be asserted against a tree that does not contain it.
if [ -z "$TREE" ]; then
  note "FAIL Q3: no --tree given; a conclusion must name the commit it holds for"
else
  if ! git -C "$REPO" rev-parse --verify --quiet "$TREE^{commit}" >/dev/null; then
    note "FAIL Q3: '$TREE' does not resolve to a commit in this repository"
  elif git -C "$REPO" merge-base --is-ancestor "$TREE" "$TREE_BASE"; then
    note "PASS Q3: $TREE is an ancestor of $TREE_BASE"
  else
    note "FAIL Q3: $TREE is not an ancestor of $TREE_BASE; the conclusion does not hold for that tree"
  fi
fi

echo "----"
if [ "$FAILS" -eq 0 ]; then
  echo "VERDICT: PASS - branch '$BRANCH' may have its status changed on these answers"
  exit 0
fi
echo "VERDICT: FAIL - branch '$BRANCH' has $FAILS unanswered or false question(s); do not change its status"
exit 1
