#!/usr/bin/env bash
# Focused A3 Swift evidence using the shared ChildEvidence probe. Each
# invocation retains a fresh output tree under out/a3-comparison-plan/runs.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
cd "$ROOT" || exit 2
if [ "${IN_NIX_SHELL:-}" = "" ]; then
	printf 'run this fixture through: nix develop -c bash tests/haxe/comparison-plan/run.sh\n' >&2
	exit 2
fi

. tests/support/stage-check.sh
PARENT=out/a3-comparison-plan/runs
mkdir -p "$PARENT" || exit 2
RUN="$(mktemp -d "$PARENT/run-XXXXXXXX")" || exit 2
mkdir -p "$RUN/plans" "$RUN/probe" || exit 2
baseline_overlay="$RUN/baseline-overlay"
mkdir -p "$baseline_overlay/swiftcompiler" || exit 2
sed '/^[[:space:]]*imports\.runtime("TiqianArray");$/d' \
	packages/compiler/reflaxe/swift/swiftcompiler/SwiftDecl.hx \
	>"$baseline_overlay/swiftcompiler/SwiftDecl.hx" || exit 2
baseline_hxml="$RUN/probe/static-data-baseline.hxml"
sed "/^-cp packages\/compiler\/reflaxe\/swift$/a -cp $baseline_overlay" \
	tests/haxe/swift-runtime-closure/static-data-array-only.hxml \
	>"$baseline_hxml" || exit 2

cp tests/haxe/comparison-plan/expected-probe.tsv "$RUN/expected-probe.tsv" || exit 2
cp tests/haxe/comparison-runtime-observation/expected.tsv "$RUN/expected-observations.tsv" || exit 2
cp tests/haxe/comparison-plan/expected-stages.txt "$RUN/expected-stages.txt" || exit 2

INPUTS=(
	packages/compiler/ComparatorPlan.hx
	packages/compiler/PolicyQueries.hx
	packages/compiler/SourceContainerAnalysis.hx
	packages/compiler/SourceComparisonAnalysis.hx
	packages/compiler/reflaxe/swift/swiftcompiler/SwiftComparisonPlan.hx
	packages/compiler/reflaxe/swift/swiftcompiler/SwiftType.hx
	packages/compiler/reflaxe/swift/swiftcompiler/SwiftDecl.hx
	packages/compiler/reflaxe/swift/swiftcompiler/SwiftExpr.hx
	tests/haxe/comparison-runtime-observation/comparison/ComparisonObserve.hx
	tests/haxe/comparison-runtime-observation/comparison/LeftSameKeyCase.hx
	tests/haxe/comparison-runtime-observation/comparison/RightSameKeyCase.hx
	tests/haxe/comparison-runtime-observation/comparison/ParameterCompositionCases.hx
	tests/haxe/comparison-runtime-observation/hxml/swift.hxml
	tests/haxe/comparison-runtime-observation/native/main.swift
	tests/haxe/comparison-runtime-observation/expected.tsv
	tests/haxe/comparison-plan/comparison-plan-probe.hxml
	tests/haxe/comparison-plan/comparisonplan/ComparisonPlanProbe.hx
	tests/haxe/comparison-plan/comparisonplan/PlanCases.hx
	tests/haxe/comparison-plan/comparisonplan/FlatCases.hx
	tests/haxe/comparison-plan/comparisonplan/CountAlias.hx
	tests/haxe/comparison-plan/comparisonplan/SequenceAlias.hx
	tests/haxe/comparison-plan/comparisonplan/left/Same.hx
	tests/haxe/comparison-plan/comparisonplan/right/Same.hx
	tests/haxe/comparison-plan/expected-probe.tsv
	tests/haxe/comparison-plan/expected-stages.txt
	tests/haxe/comparison-plan/stage-verdict.ts
	tests/haxe/comparison-plan/verdict-controls.ts
	tests/haxe/comparison-plan/run.ts
	tests/haxe/comparison-plan/run.sh
	tests/haxe/swift-runtime-closure/StaticDataArrayOnly.hx
	tests/haxe/swift-runtime-closure/static-data-array-only.hxml
	tests/haxe/swift-runtime-closure/native-static-data-array-only.swift
	tests/bundle-child-evidence/probe/EvidenceProbe.hx
	tests/bundle-child-evidence/probe/probe.hxml
	tools/bundle/ChildEvidence.hx
	tests/support/stage-check.sh
	"$baseline_overlay/swiftcompiler/SwiftDecl.hx"
	"$baseline_hxml"
)
sha256sum "${INPUTS[@]}" >"$RUN/input-hashes-before.txt" || exit 2

mkdir -p "$RUN/toolchain" || exit 2
printf '%s\n' "haxe version: $(haxe --version 2>&1)" "IN_NIX_SHELL: ${IN_NIX_SHELL:-unset}" >"$RUN/toolchain/identity.txt"
haxelib path boring >"$RUN/toolchain/boring-path.txt" 2>"$RUN/toolchain/boring-path-stderr.txt"
boring_status=$?
haxelib path reflaxe >"$RUN/toolchain/reflaxe-path.txt" 2>"$RUN/toolchain/reflaxe-path-stderr.txt"
reflaxe_status=$?
printf '%s\n' "$boring_status" >"$RUN/toolchain/boring-path-status.txt"
printf '%s\n' "$reflaxe_status" >"$RUN/toolchain/reflaxe-path-status.txt"
if [ "$boring_status" != "0" ] || [ "$reflaxe_status" != "0" ]; then
	printf 'haxelib path lookup failed; evidence retained at %s\n' "$RUN" >&2
	exit 2
fi
boring_path="$(awk '/\/packages\/compiler\/$/ { print; exit }' "$RUN/toolchain/boring-path.txt")"
if [ "$boring_path" = "" ]; then
	printf 'haxelib boring path did not expose packages/compiler; evidence retained at %s\n' "$RUN" >&2
	exit 2
fi
boring_realpath="$(realpath -e "$boring_path")" || exit 2
case "$boring_realpath/" in
	"$ROOT/"*) printf '%s\n' "$boring_realpath" >"$RUN/toolchain/boring-resolved-path.txt" ;;
	*) printf 'haxelib boring path escaped checkout: %s\n' "$boring_realpath" >&2; exit 2 ;;
esac
reflaxe_path="$(awk '/^\// { print; exit }' "$RUN/toolchain/reflaxe-path.txt")"
printf '%s\n' "$reflaxe_path" >"$RUN/toolchain/reflaxe-resolved-path.txt"

bun tests/haxe/comparison-plan/verdict-controls.ts >"$RUN/verdict-controls.json" 2>"$RUN/verdict-controls-stderr.txt"
controls_status=$?
printf '%s\n' "$controls_status" >"$RUN/verdict-controls-status.txt"
if [ "$controls_status" != "0" ]; then
	sha256sum "${INPUTS[@]}" >"$RUN/input-hashes-after.txt"
	printf 'verdict controls failed; evidence retained at %s\n' "$RUN" >&2
	exit "$controls_status"
fi

cat >"$RUN/provenance.txt" <<EOF
repository root: $ROOT
attempt: $RUN
git head: $(git rev-parse HEAD)
git status:
$(git status --short)
haxe: $(haxe --version 2>&1)
bun: $(bun --version 2>&1)
swiftc: $(swiftc --version 2>&1 | head -n 1)
boring haxelib source: $(cat "$RUN/toolchain/boring-resolved-path.txt")
reflaxe haxelib source: $(cat "$RUN/toolchain/reflaxe-resolved-path.txt")
selected input hashes are in input-hashes-before.txt; they are not a full source closure
EOF

probe_js="$RUN/probe/evidence-probe.js"
probe_hxml="$RUN/probe/probe.hxml"
sed "s#^-js .*#-js $probe_js#" tests/bundle-child-evidence/probe/probe.hxml >"$probe_hxml"
printf '%s\n' "haxe $probe_hxml" >"$RUN/probe/command.txt"
haxe "$probe_hxml" >"$RUN/probe/stdout.txt" 2>"$RUN/probe/stderr.txt"
probe_compile_status=$?
printf '%s\n' "$probe_compile_status" >"$RUN/probe/status.txt"
if [ "$probe_compile_status" != "0" ]; then
	printf 'probe compile failed; evidence retained at %s\n' "$RUN" >&2
	sha256sum "${INPUTS[@]}" >"$RUN/input-hashes-after.txt"
	if ! cmp -s "$RUN/input-hashes-before.txt" "$RUN/input-hashes-after.txt"; then
		printf 'selected inputs changed during the attempt\n' >"$RUN/input-mutation.txt"
	fi
	exit "$probe_compile_status"
fi

bun tests/haxe/comparison-plan/run.ts "$RUN" "$probe_js" "$baseline_hxml"
orchestrator_status=$?
sha256sum "${INPUTS[@]}" >"$RUN/input-hashes-after.txt" || exit 2
if ! cmp -s "$RUN/input-hashes-before.txt" "$RUN/input-hashes-after.txt"; then
	printf 'selected inputs changed during the attempt\n' >"$RUN/input-mutation.txt"
	orchestrator_status=1
fi
if [ "$orchestrator_status" != "0" ]; then
	printf 'A3 attempt failed; evidence retained at %s\n' "$RUN" >&2
	cat "$RUN/findings.txt" >&2 2>/dev/null || true
	exit "$orchestrator_status"
fi

findings="$RUN/stage-findings.txt"
if ! stage_check "$RUN/status.tsv" "$RUN/expected-stages.txt" "$findings"; then
	printf 'stage membership check failed; evidence retained at %s\n' "$RUN" >&2
	cat "$findings" >&2
	exit 1
fi
printf 'A3 focused Swift evidence: %s\n' "$RUN"
