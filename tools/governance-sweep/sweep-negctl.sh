#!/usr/bin/env bash
# sweep-negctl.sh: negative control for sweep.sh class 2, the question "did the vanished
# branch's work reach the mainline?".
#
# The defect this control pins: class 2 used to decide class membership with
#   git log --merges --format=%s b1188eec..MAIN | grep -F <branch>
# which has two blind spots. The window hides merges recorded before the anchor, and a
# substring match cannot tell "warn/ts" from the merged "warn/ts3". A detector that only
# ever widens is a rubber stamp, so this control pins BOTH directions: a row whose work
# reached the mainline must read as merged, and a row whose work never reached it must keep
# reading as unmerged, in every revision of the sweep.
#
# Method: build a fixture board (SWEEP_BOARD) holding exactly four `doing` rows, none of
# whose branches exists as a ref:
#   A  MERGED-REAL     the live `warn/kotlin` row: merged 2026-09-27 under the aggregating
#                      branch `warn/zero`, so it is recorded only by merges that are
#                      ANCESTORS of the window anchor, invisible to the old criterion.
#   B  NEVER-MERGED    the live W0 row, taken from its board row (branch in $UNMERGED_BR):
#                      self-declared as never committed; its five deliverables exist
#                      nowhere on the mainline.
#   C  SUBSTRING-TRAP  synthetic branch `warn/ts`, a strict prefix of the merged `warn/ts3`
#                      and inside the old window: a substring test calls it merged.
#   D  PATH-INFERENCE  synthetic branch `negctl/no-ref-<pid>` declaring one real mainline
#                      artifact that did not exist at the anchor: the deleted-branch
#                      fallback tier must catch it and label it as an inference.
#
# Then it runs the sweep under test over that fixture and asserts, for the sweep under test
# POST-FIX (A merged by reachability, B and C unmerged, D merged by path-inference) and for
# the PRE-FIX revision (A unmerged, C merged). A against B, and B against D, must come out
# opposite.
#
# MUTATION USE: point --sweep at the pre-fix revision and this script must FAIL (the mutant
# is killed). Pointing it at the tree's fixed revision must PASS.
#
# Usage: tools/governance-sweep/sweep-negctl.sh [options]
#   --sweep <file>      sweep under test      (default $ROOT/tools/governance-sweep/sweep.sh)
#   --pre-fix <ref>     revision holding the pre-fix criterion, read with
#                       <ref>:tools/governance-sweep/sweep.sh
#                       (default $SWEEP_NEGCTL_PRE_FIX_COMMIT, else d939448a, the commit
#                       that introduced the criterion)
#   --board <file>      live board to lift rows A/B from (default: walked up from $ROOT)
#   --keep              keep the fixture board and print where it is
# Env: SWEEP_MAIN (mainline), SWEEP_MBASE (anchor), same defaults as sweep.sh.

set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SWEEP=$ROOT/tools/governance-sweep/sweep.sh
MAIN="${SWEEP_MAIN:-arch/agent-guided-governance}"
ANCHOR="${SWEEP_MBASE:-b1188eec}"
MERGED_BR="warn/kotlin"
UNMERGED_BR="warn/w0-freeze"
TRAP_BR="warn/ts"
BOARD=""
PRE_FIX_COMMIT="${SWEEP_NEGCTL_PRE_FIX_COMMIT:-d939448a}"
KEEP=0

while [ $# -gt 0 ]; do
  case "$1" in
    --sweep) SWEEP=$2; shift 2 ;;
    --pre-fix) PRE_FIX_COMMIT=$2; shift 2 ;;
    --board) BOARD=$2; shift 2 ;;
    --keep) KEEP=1; shift ;;
    -h | --help) sed -n '2,45p' "$0"; exit 0 ;;
    *) echo "sweep-negctl: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

note() { echo "sweep-negctl: $*"; }
die() { echo "sweep-negctl: FATAL: $*" >&2; exit 2; }

if [ -z "$BOARD" ]; then
  d=$ROOT
  while [ "$d" != "/" ]; do
    d=$(dirname "$d")
    if [ -r "$d/.workspace-board/board.json" ]; then BOARD="$d/.workspace-board/board.json"; break; fi
  done
fi
[ -n "$BOARD" ] && [ -r "$BOARD" ] || die "no readable .workspace-board/board.json (use --board)"

command -v git >/dev/null 2>&1 || die "git not found in PATH"
command -v jq >/dev/null 2>&1 || die "jq not found in PATH"
[ -r "$SWEEP" ] || die "sweep under test not readable: $SWEEP"
git -C "$ROOT" rev-parse --verify --quiet "$MAIN^{commit}" >/dev/null || die "$MAIN not resolvable"
git -C "$ROOT" rev-parse --verify --quiet "$ANCHOR^{commit}" >/dev/null || die "anchor $ANCHOR not resolvable"

TMP=$(mktemp -d)
if [ "$KEEP" = 1 ]; then
  trap 'echo "sweep-negctl: kept fixture dir: $TMP"' EXIT
else
  trap 'rm -rf "$TMP"' EXIT
fi

note "argv='$0' '$*'"
note "root=$ROOT"
note "board=$BOARD"
note "sweep under test=$SWEEP sha256=$(sha256sum "$SWEEP" | awk '{print $1}')"
note "main=$MAIN anchor=$ANCHOR"

# ---------------------------------------------------------------- preconditions
# Every premise of this control is checked first, so that a fixture which cannot probe
# anything stops with a message and never reports a green run.
for br in "$MERGED_BR" "$UNMERGED_BR" "$TRAP_BR"; do
  if git -C "$ROOT" rev-parse --verify --quiet "refs/heads/$br" >/dev/null \
    || git -C "$ROOT" rev-parse --verify --quiet "refs/remotes/origin/$br" >/dev/null; then
    die "premise broken: ref for '$br' exists; class 2 skips live branches, so this row cannot probe it"
  fi
done
for br in "$MERGED_BR" "$UNMERGED_BR"; do
  n=$(jq -r --arg br "$br" '[.tasks[] | select(.status=="doing" and (.branch // "")==$br)] | length' "$BOARD")
  [ "$n" -ge 1 ] || die "premise broken: no doing row with branch=$br in $BOARD"
  note "premise ok: $n live doing row(s) with branch=$br, ref absent locally and on origin"
done

# the artifact for row D: on MAIN, absent at the anchor
ARTIFACT=""
for p in samples/boring/WidenedFieldNonNull.hx samples/boring/ShiftPopStatement.hx \
  tests/ts/warnstd-kotlin-regression.test.ts samples/boring/FromCharCodeToString.hx; do
  git -C "$ROOT" cat-file -e "$MAIN:$p" 2>/dev/null || continue
  git -C "$ROOT" cat-file -e "$ANCHOR:$p" 2>/dev/null && continue
  ARTIFACT=$p
  break
done
[ -n "$ARTIFACT" ] || die "premise broken: no candidate artifact is on $MAIN and absent at $ANCHOR"
note "premise ok: probe artifact $ARTIFACT present on $MAIN, absent at anchor $ANCHOR"

# ---------------------------------------------------------------- fixture board
PROBE_BR="negctl/no-ref-$$"
A=$(jq -c --arg br "$MERGED_BR" \
  '[.tasks[] | select(.status=="doing" and (.branch // "")==$br)
    | {id, status, branch, description, sop}][0]' "$BOARD")
B=$(jq -c --arg br "$UNMERGED_BR" \
  '[.tasks[] | select(.status=="doing" and (.branch // "")==$br)
    | {id, status, branch, description, sop}][0]' "$BOARD")
[ "$A" != "null" ] && [ "$B" != "null" ] || die "could not lift rows A/B out of $BOARD"

C=$(jq -cn --arg br "$TRAP_BR" '{id: "negctl-substring-trap", status: "doing", branch: $br,
  title: "substring trap: strict prefix of a merged branch name",
  description: "范围: negative-control probe; the branch name is a strict prefix of a branch that did land. 非目标: no artifact is declared, so the path-inference tier has nothing to infer from.",
  sop: [{text: "the detector must not read this row as landed", evidence: ""}]}')
D=$(jq -cn --arg br "$PROBE_BR" --arg p "$ARTIFACT" '{id: "negctl-path-inference", status: "doing", branch: $br,
  title: "deleted branch whose declared artifact is already on the mainline",
  description: ("范围: negative-control probe for the deleted-branch fallback tier. 改动: " + $p + " (declared artifact, already on the mainline, absent at the anchor)."),
  sop: [{text: "the fallback tier must report this as merged by path inference, not as reachability", evidence: ""}]}')

FIXTURE=$TMP/board.json
jq -n --argjson a "$A" --argjson b "$B" --argjson c "$C" --argjson d "$D" \
  '{tasks: [$a, $b, $c, $d]}' >"$FIXTURE" || die "could not build the fixture board"
note "fixture board=$FIXTURE rows=$(jq -r '.tasks | length' "$FIXTURE") branches=$(jq -r '[.tasks[].branch] | join(",")' "$FIXTURE")"

# ---------------------------------------------------------------- run both revisions
PRE=$TMP/sweep.pre-fix.sh
git -C "$ROOT" show "$PRE_FIX_COMMIT:tools/governance-sweep/sweep.sh" >"$PRE" 2>"$TMP/pre.err" \
  || { sed 's/^/  /' "$TMP/pre.err"; die "cannot read the pre-fix sweep from $PRE_FIX_COMMIT"; }
note "pre-fix revision=$PRE_FIX_COMMIT sha256=$(sha256sum "$PRE" | awk '{print $1}')"

run_sweep() { # run_sweep <script> <transcript-out> -> rc
  SWEEP_REPO="$ROOT" SWEEP_BOARD="$FIXTURE" SWEEP_MAIN="$MAIN" SWEEP_MBASE="$ANCHOR" \
    bash "$1" >"$2" 2>&1
}

run_sweep "$SWEEP" "$TMP/post.txt"
POST_RC=$?
run_sweep "$PRE" "$TMP/pre.txt"
PRE_RC=$?

verdict_line() { # verdict_line <transcript> <branch> -> the class-2 line for that branch
  awk -v want="branch=$2" '/^   DEAD-/{ for (i = 1; i <= NF; i++) if ($i == want) { print; exit } }' "$1"
}
label_of() { printf '%s' "$1" | awk '{ l = $1; sub(/:$/, "", l); print l }'; }

ASSERT_PASS=0
ASSERT_FAIL=0
assert() { # assert <label> <expected> <actual>
  if [ "$2" = "$3" ]; then
    echo "ok     $1 [$3]"
    ASSERT_PASS=$((ASSERT_PASS + 1))
  else
    echo "NOT OK $1: expected '$2', got '$3'"
    ASSERT_FAIL=$((ASSERT_FAIL + 1))
  fi
}
assert_has() { # assert_has <label> <needle> <haystack>
  case "$3" in
    *"$2"*) echo "ok     $1 [$2]"; ASSERT_PASS=$((ASSERT_PASS + 1)) ;;
    *) echo "NOT OK $1: '$2' not in '$3'"; ASSERT_FAIL=$((ASSERT_FAIL + 1)) ;;
  esac
}
assert_opposite() { # assert_opposite <label> <verdict-a> <verdict-b> : exactly one is merged
  case "$2:$3" in
    merged:unmerged | unmerged:merged)
      echo "ok     $1 [$2 vs $3]"; ASSERT_PASS=$((ASSERT_PASS + 1)) ;;
    *)
      echo "NOT OK $1: the two rows must be judged differently, got '$2' vs '$3'"
      ASSERT_FAIL=$((ASSERT_FAIL + 1)) ;;
  esac
}

A_LINE=$(verdict_line "$TMP/post.txt" "$MERGED_BR")
B_LINE=$(verdict_line "$TMP/post.txt" "$UNMERGED_BR")
C_LINE=$(verdict_line "$TMP/post.txt" "$TRAP_BR")
D_LINE=$(verdict_line "$TMP/post.txt" "$PROBE_BR")
PA_LINE=$(verdict_line "$TMP/pre.txt" "$MERGED_BR")
PB_LINE=$(verdict_line "$TMP/pre.txt" "$UNMERGED_BR")
PC_LINE=$(verdict_line "$TMP/pre.txt" "$TRAP_BR")

echo
echo "--- sweep under test, class 2 over the fixture (rc=$POST_RC) ---"
sed -n '/^-- class 2/,/doing rows scanned/p' "$TMP/post.txt" | sed 's/^/  /'
echo
echo "--- pre-fix revision, same fixture (rc=$PRE_RC) ---"
sed -n '/^-- class 2/,/doing rows scanned/p' "$TMP/pre.txt" | sed 's/^/  /'
echo

assert "sweep under test found objects (exit 1, not the fail-closed 2)" 1 "$POST_RC"
assert "sweep under test printed no SWEEP-ERROR" no "$(grep -q '^SWEEP-ERROR' "$TMP/post.txt" && echo yes || echo no)"
for br in "$MERGED_BR" "$UNMERGED_BR" "$TRAP_BR" "$PROBE_BR"; do
  assert "class 2 emitted a verdict for $br" yes "$([ -n "$(verdict_line "$TMP/post.txt" "$br")" ] && echo yes || echo no)"
done

echo "-- POST: the fixed criterion"
assert "A landed-anyway ($MERGED_BR) is merged" "DEAD-MERGED" "$(label_of "$A_LINE")"
assert_has "A says it was decided by reachability" "basis=reachability" "$A_LINE"
assert "B never-landed ($UNMERGED_BR) is still unmerged" "DEAD-UNMERGED" "$(label_of "$B_LINE")"
assert "C substring trap ($TRAP_BR) is not merged" "DEAD-UNMERGED" "$(label_of "$C_LINE")"
assert "D deleted-ref probe is merged by inference" "DEAD-MERGED-INFERRED" "$(label_of "$D_LINE")"
assert_has "D says it was decided by path inference" "basis=path-inference" "$D_LINE"
assert_has "D cites the declared artifact" "$ARTIFACT" "$D_LINE"

echo "-- mutation pair: the two judgements must be opposite"
A_V=$(label_of "$A_LINE"); A_V=$([ "$A_V" = "DEAD-UNMERGED" ] && echo unmerged || echo merged)
B_V=$(label_of "$B_LINE"); B_V=$([ "$B_V" = "DEAD-UNMERGED" ] && echo unmerged || echo merged)
D_V=$(label_of "$D_LINE"); D_V=$([ "$D_V" = "DEAD-UNMERGED" ] && echo unmerged || echo merged)
assert_opposite "known-merged row vs known-unmerged row" "$A_V" "$B_V"
assert_opposite "known-unmerged row vs deleted-ref path-inference row" "$B_V" "$D_V"

echo "-- PRE-FIX: what the control is calibrated against"
assert "pre-fix misses A (the window blind spot)" "DEAD-UNMERGED" "$(label_of "$PA_LINE")"
assert "pre-fix still reports B as unmerged" "DEAD-UNMERGED" "$(label_of "$PB_LINE")"
assert "pre-fix false-positives C (the substring blind spot)" "DEAD-MERGED" "$(label_of "$PC_LINE")"

echo
if [ "$ASSERT_FAIL" -eq 0 ]; then
  echo "sweep-negctl: PASS ($ASSERT_PASS assertions) - landed work reads as merged, never-landed work does not"
  echo "sweep-negctl: mutation check: rerun with --sweep <pre-fix copy>; it must FAIL, or this control has no teeth."
  exit 0
fi
echo "sweep-negctl: FAIL ($ASSERT_FAIL of $((ASSERT_PASS + ASSERT_FAIL)) assertions failed)"
exit 1
