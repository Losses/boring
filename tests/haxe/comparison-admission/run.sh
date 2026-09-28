#!/usr/bin/env bash
# Focused finite source admission contract for the A3 source phase. Each run
# keeps a fresh output tree under out/comparison-admission-contract, records a
# status per attempt, and verifies that every excluded input kept its bytes.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
cd "$ROOT" || exit 2
if [ "${IN_NIX_SHELL:-}" = "" ]; then
	printf 'run this fixture through: nix develop -c bash tests/haxe/comparison-admission-contract/run.sh\n' >&2
	exit 2
fi

FIXTURE=tests/haxe/comparison-admission-contract
OUT=out/comparison-admission-contract
mkdir -p "$OUT" || exit 2
RUN="$(mktemp -d "$OUT/run-XXXXXXXX")" || exit 2

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
if timeout 300 haxe "$FIXTURE/admission-probe.hxml" >"$RUN/probe.stdout" 2>"$RUN/probe.stderr"; then
	printf 'attempt\tadmission-probe\t0\n'
else
	status=$?
	printf 'attempt\tadmission-probe\t%s\n' "$status"
fi
if [ -s "$RUN/probe.stderr" ]; then
	printf 'probe stderr captured in %s/probe.stderr\n' "$RUN"
fi

cp "$FIXTURE/admission-expected.tsv" "$RUN/expected.tsv" || exit 2
if diff -u "$RUN/expected.tsv" "$RUN/probe.stdout" >"$RUN/expected.diff"; then
	printf 'attempt\texpected-results\t0\n'
else
	status=$?
	printf 'attempt\texpected-results\t%s\n' "$status"
	cat "$RUN/expected.diff"
fi

for file in "${EXCLUDED[@]}"; do
	sha256sum "$file" || exit 2
done >"$RUN/excluded-after.txt"
if diff -u "$RUN/excluded-before.txt" "$RUN/excluded-after.txt" >"$RUN/excluded.diff"; then
	printf 'attempt\texcluded-inputs\t0\n'
else
	status=$?
	printf 'attempt\texcluded-inputs\t%s\n' "$status"
	cat "$RUN/excluded.diff"
fi

printf 'output tree: %s\n' "$RUN"
exit "$status"
