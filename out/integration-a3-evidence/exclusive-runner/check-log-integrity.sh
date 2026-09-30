#!/usr/bin/env bash
set -u

# Integrity checker for a sealed attempt.
# Usage: check-log-integrity.sh <attempt-dir>
# Verifies, for the attempt's harness.log:
# - the last line is the end marker, its sha256 covers every byte before
#   it, and NOTHING follows the marker: this is judged in the BYTE view
#   (total bytes == the byte offset just past the marker line's newline),
#   so bytes appended without a trailing newline are caught as well;
# - the sealed stage-evidence manifest is EXACTLY equal to the actual
#   stage file set: every manifest entry matches the live file hash, and
#   every live stage file appears in the manifest. Modified, deleted, and
#   unmanifested-added stage files are all reported and fail the check.
# Exit 0 only when all checks pass.

ATT="${1:-}"
[ -n "$ATT" ] && [ -d "$ATT" ] || {
    printf '%s\n' "usage: check-log-integrity.sh <attempt-dir>" >&2
    exit 1
}
LOG="$ATT/harness.log"
STAGES="$ATT/stages"
[ -f "$LOG" ] || {
    printf '%s\n' "INTEGRITY FAIL: no harness log"
    exit 1
}

MARKER="harness end marker sha256="

# --- byte view: locate the end marker and the offset just past it ----
# grep -b reports BYTE offsets, so none of this depends on how the file
# splits into lines. marker_off = first byte of the last end-marker line.
total_bytes=$(wc -c <"$LOG")
marker_off=$(grep -abo "^$MARKER" "$LOG" | tail -n 1 | cut -d: -f1)
if [ -z "$marker_off" ]; then
    printf '%s\n' "INTEGRITY FAIL: no end marker (unsealed log)"
    exit 1
fi
# Bytes of the marker line including its terminating newline: head -n 1
# stops after the first LF and never appends one, so the count is exact
# even when that LF is missing (then the marker line simply ends at EOF).
marker_line_bytes=$(tail -c "+$((marker_off + 1))" "$LOG" | head -n 1 | wc -c | tr -d '[:space:]')
marker_end=$((marker_off + marker_line_bytes))
# Nothing follows the end marker: the marker line must reach EOF exactly.
if [ "$total_bytes" -ne "$marker_end" ]; then
    printf '%s\n' "INTEGRITY FAIL: content after the end marker ($((total_bytes - marker_end)) byte(s) past the marker line, byte $marker_end of $total_bytes)"
    exit 1
fi
# Marker line number, derived from the byte prefix (message text only).
last=$(( $(head -c "$marker_off" "$LOG" | wc -l | tr -d '[:space:]') + 1 ))

marker_line=$(tail -c "+$((marker_off + 1))" "$LOG" | head -n 1 | tr -d '\n')
recorded=${marker_line#"$MARKER"}
prefix_sha=$(head -c "$marker_off" "$LOG" | sha256sum | cut -d' ' -f1)
if [ "$recorded" != "$prefix_sha" ]; then
    printf '%s\n' "INTEGRITY FAIL: prefix sha mismatch (recorded $recorded, actual $prefix_sha)"
    exit 1
fi

# Exact set equality between the sealed stage-evidence manifest (all
# bytes before the marker line) and the actual stage files.
manifest=$(head -c "$marker_off" "$LOG" | grep '^stage-evidence ' | sed 's/^stage-evidence //' | sort)
actual=$(cd "$STAGES" 2>/dev/null && sha256sum -- * 2>/dev/null | sort)
manifest_names=$(printf '%s\n' "$manifest" | awk '{print $2}' | sort)
actual_names=$(printf '%s\n' "$actual" | awk '{print $2}' | sort)
if [ "$manifest_names" != "$actual_names" ]; then
    printf '%s\n' "INTEGRITY FAIL: stage evidence set differs from manifest"
    printf '%s\n' "--- manifest only:"
    comm -23 <(printf '%s\n' "$manifest_names") <(printf '%s\n' "$actual_names") | sed 's/^/  deleted: /'
    printf '%s\n' "--- actual only (unmanifested):"
    comm -13 <(printf '%s\n' "$manifest_names") <(printf '%s\n' "$actual_names") | sed 's/^/  added: /'
    exit 1
fi
if [ "$manifest" != "$actual" ]; then
    printf '%s\n' "INTEGRITY FAIL: stage evidence hash changed"
    diff <(printf '%s\n' "$manifest") <(printf '%s\n' "$actual") | sed 's/^/  /'
    exit 1
fi
printf '%s\n' "INTEGRITY OK: sealed at line $last, sha $prefix_sha, stage manifest exact"
exit 0
