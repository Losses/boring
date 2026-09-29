#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT" || exit 2
if [ "${IN_NIX_SHELL:-}" = "" ]; then
    printf '%s\n' 'run with: nix develop -c bash tests/haxe/dart-comparison-consumer/run.sh' >&2
    exit 2
fi

PARENT=out/dart-comparison-consumer/runs
mkdir -p "$PARENT" || exit 2
RUN="$(mktemp -d "$PARENT/attempt-XXXXXXXX")" || exit 2
mkdir -p "$RUN/entry" || exit 2
printf '%s\n' "$RUN"

INPUTS=(
    packages/compiler/SourceComparisonAnalysis.hx
    packages/compiler/SourceContainerAnalysis.hx
    packages/compiler/reflaxe/dart/dartcompiler/DartDecl.hx
    packages/compiler/reflaxe/dart/dartcompiler/DartExpr.hx
    packages/compiler/reflaxe/dart/dartcompiler/DartComparisonPlan.hx
    packages/compiler/reflaxe/dart/dartcompiler/DartType.hx
    tests/haxe/dart-comparison-consumer/dartcomparison/EnumCases.hx
    samples/boring/PrintedCollection.hx
    samples/boring/PrintedEnumOps.hx
    samples/boring/PrintedSortedFields.hx
    packages/compiler/PolicyQueries.hx
    tests/haxe/dart-comparison-consumer/dart.hxml
    tests/haxe/dart-comparison-consumer/README.md
    tests/haxe/dart-comparison-consumer/native/main.dart
    tests/haxe/dart-comparison-consumer/expected.stdout
    tests/haxe/dart-comparison-consumer/run.sh
    tests/haxe/dart-comparison-consumer/dartcomparison/ComparisonCases.hx
    tests/haxe/comparison-runtime-observation/comparison/ParameterCompositionCases.hx
    tests/haxe/dart-comparison-consumer/dartcomparison/left/Same.hx
    tests/haxe/dart-comparison-consumer/dartcomparison/left/LeftWrapper.hx
    tests/haxe/dart-comparison-consumer/dartcomparison/right/Same.hx
    tests/haxe/dart-comparison-consumer/dartcomparison/right/RightWrapper.hx
)
sha256sum "${INPUTS[@]}" >"$RUN/input-sha256.txt" || exit 2
printf 'head=%s\n' "$(git rev-parse HEAD)" >"$RUN/provenance.txt"
printf 'haxe=%s\n' "$(haxe --version 2>&1)" >>"$RUN/provenance.txt"
printf 'dart=%s\n' "$(dart --version 2>&1)" >>"$RUN/provenance.txt"
printf 'cwd=%s\n' "$ROOT" >>"$RUN/provenance.txt"

run_stage() {
    local name="$1"
    shift
    printf '%s\0' "$@" >"$RUN/$name.argv"
    printf '%q ' "$@" >"$RUN/$name.command"
    printf '\n' >>"$RUN/$name.command"
    "$@" >"$RUN/$name.stdout" 2>"$RUN/$name.stderr"
    local status=$?
    printf '%s\n' "$status" >"$RUN/$name.status"
    return "$status"
}

run_stage compiler-path haxelib path boring || exit 1
printf 'HAXELIB_PATH=%s\n' "${HAXELIB_PATH:-}" >>"$RUN/provenance.txt"
run_stage generate haxe tests/haxe/dart-comparison-consumer/dart.hxml \
    -D "dart-output=$RUN/dart-gen" \
    -D "dart-test-output=$RUN/dart-gen-tests" || exit 1
cp tests/haxe/dart-comparison-consumer/native/main.dart "$RUN/entry/main.dart" || exit 2
run_stage analyze dart analyze "$RUN/dart-gen" "$RUN/entry/main.dart" || exit 1
run_stage program dart run "$RUN/entry/main.dart" || exit 1
run_stage expected diff -u tests/haxe/dart-comparison-consumer/expected.stdout "$RUN/program.stdout" || exit 1
sha256sum "${INPUTS[@]}" >"$RUN/input-sha256-after.txt" || exit 2
cmp "$RUN/input-sha256.txt" "$RUN/input-sha256-after.txt" || exit 2
printf 'Dart comparison consumer passed: %s\n' "$RUN"
