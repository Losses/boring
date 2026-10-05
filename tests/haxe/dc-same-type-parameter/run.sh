#!/usr/bin/env bash
# Reproduction + verification fixture for Builder.sameTypeParameter dedup.
# Usage (no exec bit on dc-warn fuse):  bash tests/haxe/dc-same-type-parameter/run.sh <out.log-dir>
# Parses DEDUP / LIMITED / CONTROL lines and exits nonzero on regression
# of the fixed behavior (dedup ok:true + nested nodes Complete under
# maxRecordNodes=2 + concrete control dedup:true).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
OUTDIR="${1:-$HERE/out-run}"
mkdir -p "$OUTDIR" || exit 1
OUTDIR="$(cd "$OUTDIR" && pwd)" || exit 1
ROOT="$(cd "$HERE/../../.." && pwd)"

run_haxe() {
	cd "$ROOT" || return 1
	timeout 1800 \
		nix develop "$ROOT" -c haxe "$HERE/build.hxml" \
		>"$OUTDIR/probe.stdout" 2>"$OUTDIR/probe.stderr"
	echo $?
}

status_file="$OUTDIR/exit.txt"
if [ "${SKIP_HAXE:-}" = "" ]; then
	run_haxe >"$status_file"
	st="$(cat "$status_file")"
else
	st="$(cat "$status_file" 2>/dev/null || echo 1)"
fi
cat "$OUTDIR/probe.stdout"

fail=0
grep -q '^DEDUP ok:true' "$OUTDIR/probe.stdout" || { echo "CHECK-FAIL: dedup not ok:true"; fail=1; }
grep -q '^DEDUP child state:Complete' "$OUTDIR/probe.stdout" || { echo "CHECK-FAIL: child not Complete"; fail=1; }
grep -q '^DEDUP pair state:Complete' "$OUTDIR/probe.stdout" || { echo "CHECK-FAIL: pair not Complete"; fail=1; }
grep -q '^LIMITED allNestedComplete:true' "$OUTDIR/probe.stdout" || { echo "CHECK-FAIL: maxRecordNodes=2 nested not all Complete"; fail=1; }
grep -q '^LIMITED allNestedComplete:true sawNested:true' "$OUTDIR/probe.stdout" || { echo "CHECK-FAIL: budget path saw no nested nodes"; fail=1; }
grep -q '^CONTROL concrete dedup:true' "$OUTDIR/probe.stdout" || { echo "CHECK-FAIL: concrete control dedup not true"; fail=1; }
[ "$st" = "0" ] || { echo "CHECK-FAIL: haxe exit=$st"; fail=1; }
echo "run.sh verdict: $([ $fail = 0 ] && echo PASS || echo FAIL)"
exit $fail
