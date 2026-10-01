#!/usr/bin/env bash
# doing-row-guard: mechanically discriminate live rows from ghost rows on the
# board's doing lane.
#
# Disaster recovery R4 found 33 rows in status "doing" whose branch fields did
# not resolve to any commit. A row's disposition cannot be read off that fact
# alone: "branch does not resolve" has distinct causes with different
# dispositions. This script separates them mechanically instead of by eyeball:
#
#   LIVE          branch resolves to a commit via `git rev-parse --verify
#                 <branch>^{commit}`. Real, locatable work.
#   INTEGRATED    branch does not resolve, but the row carries an
#                 integration record whose commit resolves and is an ancestor
#                 of the merge-back base (or of the recorded target tree). The
#                 work landed in the mainline and the branch was later
#                 deleted; the row is stale, not a ghost. NOT a sign-off.
#   LANDED_       branch does not resolve and there is no resolvable
#   UNRECORDED     integration record, but a commit sha found in the row's
#                 own progress reports (commented timeline entries, evidence,
#                 notes) resolves and is an ancestor of GUARD_BASE — suggesting
#                 the work reached the mainline without a recorded integration
#                 fact. Evidence is weaker than INTEGRATED: the sha is lifted
#                 from free text and may name a base point or related commit,
#                 not necessarily the row's tip. NOT a sign-off.
#   UNTRACEABLE   branch does not resolve and none of the above signals
#                 (integration record, free-text commit shas) yield a
#                 checkable mechanical trace. A ghost *candidate* only. It may
#                 be a real seat whose branch was never created, or a board
#                 field never filled in. Needs a human; this script does NOT
#                 delete or close these.
#   NO_BRANCH     branch field is empty. Cannot judge at all; the field is
#                 missing, not false.
#
# A row whose branch is named on the R4 disaster list (warn/r1, warn/ts3) is
# additionally flagged R4_NAMED regardless of verdict.
#
# What this guard CANNOT tell you:
#   - It cannot prove a row is a ghost. UNTRACEABLE means "no mechanical trace
#     in this checkout"; a branch may live in another clone or as an unpushed
#     worktree HEAD.
#   - It cannot judge whether UNTRACEABLE rows should be deleted, re-pointed,
#     or re-claimed. That disposition is human, on top of this report.
#   - INTEGRATED trusts the integration record; the script verifies only that
#     the recorded commit exists and is an ancestor of the base.
#   - LANDED_UNRECORDED trusts free-text mention of a commit sha; the sha may
#     name a base point, a sibling branch, or an unrelated landed commit
#     rather than the row's own work product. Treat it as "work plausibly
#     landed", not as a checkable integration fact.
#   - It cannot prove that a LANDED_UNRECORDED row is deletable: the work
#     reached the mainline, but the row's acceptance criteria still need
#     adjudication — there is no sign-off record.
#   - "Branch unresolvable" != "row should be deleted": the board field may
#     simply be unfilled or stale.
#
# Exit codes (fail-closed, same contract as status-change):
#   0 = guard ran; no UNTRACEABLE/NO_BRANCH rows
#   1 = guard ran; at least one UNTRACEABLE or NO_BRANCH row (findings printed)
#       LANDED_UNRECORDED is surfaced but NOT a finding — it does not prevent
#       exit 0 on its own, because the work demonstrably reached the mainline
#       (even though the record is missing).
#   2 = guard could NOT run (missing board, missing base tree, bad usage)
#
# Usage:
#   guard.sh sweep [--json]           # judge every doing row
#   guard.sh check <row-id-or-branch> # judge one row
#
# Configuration:
#   GUARD_REPO   git checkout of the boring repo (default: this script's repo)
#   GUARD_BOARD  path to .workspace-board/board.json (default: found walking up)
#   GUARD_BASE   tree INTEGRATED ancestry is judged against
#                (default: arch/agent-guided-governance)

set -u

fail() { printf 'DOING-GUARD-ERROR: %s\n' "$*" >&2; exit 2; }

REPO="${GUARD_REPO:-$(cd "$(dirname "$0")/../.." && pwd)}"
BOARD="${GUARD_BOARD:-}"
if [ -z "$BOARD" ]; then
  d="$REPO"
  while [ "$d" != "/" ]; do
    d=$(dirname "$d")
    if [ -r "$d/.workspace-board/board.json" ]; then BOARD="$d/.workspace-board/board.json"; break; fi
  done
  [ -n "$BOARD" ] || fail "no .workspace-board/board.json found above $REPO (set GUARD_BOARD)"
fi
BASE="${GUARD_BASE:-arch/agent-guided-governance}"

command -v git >/dev/null 2>&1 || fail "git not found in PATH"
command -v python3 >/dev/null 2>&1 || fail "python3 not found in PATH"
[ -r "$BOARD" ] || fail "board not readable: $BOARD"
git -C "$REPO" rev-parse --verify --quiet "${BASE}^{commit}" >/dev/null || fail "base tree not resolvable in $REPO: $BASE"

MODE="${1:-sweep}"
case "$MODE" in
  sweep) JSON="${2:-}"; if [ "$JSON" != "" ] && [ "$JSON" != "--json" ]; then fail "usage: guard.sh sweep [--json] | check <row-id-or-branch>"; fi ;;
  check) [ -n "${2:-}" ] || fail "usage: guard.sh check <row-id-or-branch>" ;;
  *) fail "usage: guard.sh sweep [--json] | check <row-id-or-branch>" ;;
esac

# Rows named by disaster recovery plan R4.
R4_ROWS="warn/r1 warn/ts3"

python3 - "$BOARD" "$REPO" "$BASE" "$MODE" "${2:-}" "$R4_ROWS" <<'PY'
import json, re, subprocess, sys

board_path, repo, base, mode, target, r4_arg = sys.argv[1:7]
r4 = set(r4_arg.split())

def git(args):
    return subprocess.run(["git", "-C", repo] + args, capture_output=True, text=True)

def resolves(ref):
    return bool(ref) and git(["rev-parse", "--verify", "--quiet", ref + "^{commit}"]).returncode == 0

def is_ancestor(a, b):
    return git(["merge-base", "--is-ancestor", a, b]).returncode == 0

def row_free_text(row):
    """Gather prose fields from a row that may name a work commit.

    Scans agent progress reports (timeline entries of type 'commented'),
    plus the top-level notes and evidence fields.  These are the fields
    where a seat reports actual commits it produced; the row's title and
    description name the *subject* of the work and are excluded because
    they often reference shas that are not the row's own product."""
    parts = [row.get("notes", ""), row.get("evidence", "")]
    for sop in row.get("sop") or []:
        parts.append(sop.get("evidence", ""))
    for entry in row.get("timeline") or []:
        if entry.get("type") == "commented":
            parts.append(entry.get("text", ""))
    return "\n".join(parts)

SHA_RE = re.compile(r"\b([0-9a-f]{7,40})\b")

def find_landed_sha(row, base):
    """Return the first commit sha found in the row's free text that resolves
    and is an ancestor of *base*, or None."""
    seen = set()
    for m in SHA_RE.finditer(row_free_text(row)):
        sha = m.group(0)
        if sha in seen:
            continue
        seen.add(sha)
        if resolves(sha) and is_ancestor(sha, base):
            return sha
    return None

board = json.load(open(board_path))
doing = [t for t in board["tasks"] if t.get("status") == "doing"]

def judge(row):
    br = (row.get("branch") or "").strip()
    flags = []
    if br in r4:
        flags.append("R4_NAMED")
    if not br:
        flags.append("NO_BRANCH")
        return flags
    if resolves(br):
        flags.append("LIVE")
        return flags
    integ = row.get("integration") or {}
    commit = integ.get("commit", "")
    if resolves(commit):
        into = integ.get("into") or base
        anchor = into if resolves(into) else base
        if is_ancestor(commit, anchor):
            flags.append("INTEGRATED")
            return flags
    # Third evidence path: scan the row's own free text for a commit sha
    # that resolves and is an ancestor of base — work that plausibly
    # landed without a recorded integration fact.
    landed = find_landed_sha(row, base)
    if landed:
        flags.append("LANDED_UNRECORDED")
        return flags
    flags.append("UNTRACEABLE")
    return flags

if mode == "check":
    rows = [t for t in doing if t["id"] == target or (t.get("branch") or "").strip() == target]
    if not rows:
        sys.stderr.write("DOING-GUARD-ERROR: no doing row matches %r\n" % target)
        sys.exit(2)
else:
    rows = doing

results = []
findings = 0
for t in rows:
    flags = judge(t)
    br = (t.get("branch") or "").strip()
    if "UNTRACEABLE" in flags or "NO_BRANCH" in flags:
        findings += 1
    integ = t.get("integration") or {}
    # Re-run find_landed_sha for the results dict (cheap: judge already
    # computed it, but we need it again for display).
    landed_sha = find_landed_sha(t, base) if "LANDED_UNRECORDED" in flags else ""
    results.append({
        "id": t["id"],
        "branch": br,
        "flags": flags,
        "verdict": [f for f in flags if f != "R4_NAMED"][0],
        "integration_commit": integ.get("commit", ""),
        "landed_sha": landed_sha,
        "title": t["title"],
    })

json_mode = (mode == "sweep" and "--json" in sys.argv)

if json_mode:
    print(json.dumps({"doing_total": len(rows), "findings": findings, "rows": results},
                     ensure_ascii=False, indent=1))
else:
    print("doing rows judged: %d" % len(rows))
    for r in results:
        line = "%s  branch=%-28s %s" % (r["id"], r["branch"] or "(empty)", ",".join(r["flags"]))
        if r["verdict"] == "INTEGRATED":
            line += "  [%s -> mainline (signoff not recorded here)]" % r["integration_commit"]
        elif r["verdict"] == "LANDED_UNRECORDED" and r["landed_sha"]:
            line += "  [sha %s in row text -> mainline (free-text evidence, NOT a signoff)]" % r["landed_sha"]
        print(line)

# Findings are UNTRACEABLE / NO_BRANCH rows; exit 1 so a sweep is never
# silently green while ghost candidates exist.
sys.exit(1 if findings else 0)
PY
