#!/usr/bin/env bash
# Focused finite source admission check for the A3 source phase. Each run
# keeps a fresh output tree under out/comparison-source-admission, records a
# status per attempt, and verifies that every excluded input kept its bytes.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
cd "$ROOT" || exit 2
if [ "${IN_NIX_SHELL:-}" = "" ]; then
	printf 'run this fixture through: nix develop -c bash tests/haxe/comparison-source-admission/run.sh\n' >&2
	exit 2
fi

FIXTURE=tests/haxe/comparison-source-admission
OUT=out/comparison-source-admission
mkdir -p "$OUT" || exit 2
RUN="$(mktemp -d "$OUT/run-XXXXXXXX")" || exit 2
: >"$RUN/runner.stdout"
: >"$RUN/runner.stderr"
trap 'printf "%s\n" "$?" >"$RUN/runner.status"' EXIT
report() { printf '%s\n' "$1" | tee -a "$RUN/runner.stdout"; }
report_error() { printf '%s\n' "$1" | tee -a "$RUN/runner.stderr" >&2; }

INPUTS=(
	packages/compiler/SourceComparisonAnalysis.hx
	"$FIXTURE/admission-probe.hxml"
	"$FIXTURE/admission/AdmissionCases.hx"
	"$FIXTURE/admission/AdmissionProbe.hx"
	"$FIXTURE/admission-expected.tsv"
	"$FIXTURE/run.sh"
)
sha256sum "${INPUTS[@]}" >"$RUN/input-hashes-before.txt" || exit 2

# Inputs this phase must not change. The macro check reads only the shared
# source analysis, so the Swift adapter and the other shared consumers stay
# byte-identical across the run.
EXCLUDED=(
	packages/compiler/PolicyQueries.hx
	packages/compiler/ComparatorPlan.hx
	packages/compiler/SourceContainerAnalysis.hx
	packages/compiler/reflaxe/swift/swiftcompiler/SwiftComparisonPlan.hx
	packages/compiler/reflaxe/swift/swiftcompiler/SwiftDecl.hx
	packages/compiler/reflaxe/swift/swiftcompiler/SwiftExpr.hx
	packages/compiler/reflaxe/swift/swiftcompiler/SwiftType.hx
)
for file in "${EXCLUDED[@]}"; do
	sha256sum "$file" || exit 2
done >"$RUN/excluded-before.txt"

status=0
timeout 300 haxe "$FIXTURE/admission-probe.hxml" >"$RUN/probe.stdout" 2>"$RUN/probe.stderr"
probe_status=$?
printf '%s\n' "$probe_status" >"$RUN/probe.status"
report "$(printf 'attempt\tadmission-probe\t%s' "$probe_status")"
if [ "$probe_status" != "0" ]; then status="$probe_status"; fi
if [ -s "$RUN/probe.stderr" ]; then
	report "probe stderr captured in $RUN/probe.stderr"
fi

cp "$FIXTURE/admission-expected.tsv" "$RUN/expected.tsv" || exit 2
if diff -u "$RUN/expected.tsv" "$RUN/probe.stdout" >"$RUN/expected.diff"; then
	printf '0\n' >"$RUN/expected.status"
	report "$(printf 'attempt\texpected-results\t0')"
else
	diff_status=$?
	printf '%s\n' "$diff_status" >"$RUN/expected.status"
	status="$diff_status"
	report "$(printf 'attempt\texpected-results\t%s' "$diff_status")"
	cat "$RUN/expected.diff" | tee -a "$RUN/runner.stdout"
fi

for file in "${EXCLUDED[@]}"; do
	sha256sum "$file" || exit 2
done >"$RUN/excluded-after.txt"
if diff -u "$RUN/excluded-before.txt" "$RUN/excluded-after.txt" >"$RUN/excluded.diff"; then
	printf '0\n' >"$RUN/excluded.status"
	report "$(printf 'attempt\texcluded-inputs\t0')"
else
	diff_status=$?
	printf '%s\n' "$diff_status" >"$RUN/excluded.status"
	status="$diff_status"
	report "$(printf 'attempt\texcluded-inputs\t%s' "$diff_status")"
	cat "$RUN/excluded.diff" | tee -a "$RUN/runner.stdout"
fi

sha256sum "${INPUTS[@]}" >"$RUN/input-hashes-after.txt" || exit 2
if ! cmp -s "$RUN/input-hashes-before.txt" "$RUN/input-hashes-after.txt"; then
	status=1
	report_error "selected inputs changed during the admission attempt"
fi

report "output tree: $RUN"
exit "$status"
