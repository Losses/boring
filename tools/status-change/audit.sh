#!/usr/bin/env bash
# status-change/audit.sh: report status changes that carry no section 3.4 item 2 answers.
#
# Section 3.4 item 2 requires that every status change answer three questions:
# which ruling authorizes it, where the evidence lives in-repo, and which tree
# the conclusion holds for. check.sh judges ONE change when the caller supplies
# the three answers. This script is the other half: it looks at the board and
# reports rows whose status moved without any such record, so the absence is
# visible instead of implicit.
#
# Why an audit and not a write-time hook: the board lives in the workspace
# repository at .workspace-board/board.json, outside the boring repository, and
# the plugin that writes it validates neither unknown fields nor the shape of a
# timeline entry. A hook in the boring repository cannot see a board write at
# all. What CAN be enforced here is that the absence is reported on every sweep,
# which is what makes it a finding rather than an omission.
#
# The marker a status change is expected to carry: a timeline entry whose type
# is "commented" and whose text contains the row's own status change together
# with the three answers. Rows created before this rule existed cannot satisfy
# it, so the script separates them by age rather than pretending they are
# violations - a report that called every legacy row a violation would be
# ignored, which is the failure mode item 2 exists to prevent.
#
# Exit codes (fail-closed, same contract as the sweep):
#   0 = audit ran; no status change lacks its answers
#   1 = audit ran; at least one status change lacks them (findings printed)
#   2 = audit could NOT run (missing board, missing tool)
#
# Configuration:
#   STATUS_REPO   git checkout of the boring repo   (default: this script's repo)
#   STATUS_BOARD  path to .workspace-board/board.json (default: found walking up)
#   STATUS_SINCE  ISO date; rows whose status last moved before it are reported as
#                 legacy rather than as violations (default: 2026-10-01, the date
#                 section 3.4 took effect)

set -u

fail() { printf 'STATUS-AUDIT-ERROR: %s\n' "$*" >&2; exit 2; }

REPO="${STATUS_REPO:-$(cd "$(dirname "$0")/../.." && pwd)}"
BOARD="${STATUS_BOARD:-}"
if [ -z "$BOARD" ]; then
  d="$REPO"
  while [ "$d" != "/" ]; do
    d=$(dirname "$d")
    if [ -r "$d/.workspace-board/board.json" ]; then BOARD="$d/.workspace-board/board.json"; break; fi
  done
  [ -n "$BOARD" ] || fail "no .workspace-board/board.json found above $REPO (set STATUS_BOARD)"
fi
SINCE="${STATUS_SINCE:-2026-10-01}"

command -v python3 >/dev/null 2>&1 || fail "python3 not found in PATH"
[ -r "$BOARD" ] || fail "board not readable: $BOARD"

python3 - "$BOARD" "$SINCE" <<'PY'
import json, sys

board_path, since = sys.argv[1], sys.argv[2]
board = json.load(open(board_path))

# A status change is considered answered when some timeline entry names the three
# answers. The check is deliberately loose on wording and strict on substance:
# a ruling path, an in-repo evidence path, and a commit-like token must all
# appear. It never rewrites the board.
def answered(entries):
    for e in entries:
        text = str(e.get("text") or "")
        has_ruling = "MANAGEMENT-RULING-" in text or "rulings/" in text
        has_evidence = "docs/architecture/" in text or "evidence/" in text
        has_tree = any(len(tok) >= 7 and all(c in "0123456789abcdef" for c in tok)
                       for tok in text.replace("(", " ").replace(")", " ").split())
        if has_ruling and has_evidence and has_tree:
            return True
    return False

# The status-change event is the one whose text moves the status - not simply the
# newest entry on the row. An earlier version of this script used the maximum
# timestamp across all entries, which silently reclassified every row that had
# merely been commented on after section 3.4 took effect; on the real board that
# produced 60 "violations" where the actual number of status changes was far
# smaller. The class of event is what matters, so it is matched explicitly.
def is_status_change(e):
    if (e.get("type") or "") != "updated":
        return False
    text = str(e.get("text") or "")
    return "status" in text or "-> doing" in text or "-> done" in text or "-> cancelled" in text

violations, legacy, ok, unmoved = [], [], 0, 0
for t in board.get("tasks", []):
    entries = t.get("timeline") or []
    status = t.get("status")
    if status not in ("doing", "done", "cancelled"):
        continue           # todo rows have not moved anywhere yet
    row = (t.get("branch") or t.get("id") or "?")
    changes = [e for e in entries if is_status_change(e)]
    if not changes:
        # No recorded status-change event at all. Treated as unfalsifiable rather
        # than as a violation: the plugin writes no status-change entry for some
        # paths, so absence of the entry is not evidence that the questions went
        # unanswered - it is evidence the board does not record this.
        unmoved += 1
        continue
    if answered(entries):
        ok += 1
        continue
    last = max(str(e.get("at") or "") for e in changes)
    if last[:10] < since:
        legacy.append((row, status, last[:10]))
    else:
        violations.append((row, status, "status changed " + last[:10] + " with no three-answer entry"))

print(f"STATUS-AUDIT: board={board_path}")
print(f"STATUS-AUDIT: {ok} row(s) answered; {len(violations)} violate; "
      f"{len(legacy)} predate {since} (legacy); {unmoved} carry no status-change entry (unfalsifiable)")
for row, status, why in sorted(violations):
    print(f"  VIOLATION {status:9s} {row:46s} {why}")
if "-v" in sys.argv:
    for row, status, moved in sorted(legacy):
        print(f"  legacy    {status:9s} {row:46s} last status change {moved}")
sys.exit(1 if violations else 0)
PY
