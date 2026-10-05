#!/usr/bin/env bash
# Observation runner for the fs-missing-isdirectory probe.
#
# One Haxe source (fsprobe/IsDirectoryProbe.hx) is generated and run on four
# target chains: TypeScript, Kotlin, Dart and Rust. Every arm prints the same
# three lines; run.sh records the argv, the separated stdout/stderr and the
# numeric exit status of every stage into one fresh attempt directory and
# never rewrites it. The last block compares each run stage's stdout with
# expected.txt so a target that raises on the missing path is visible as a
# non-zero run status instead of a silently different line.
#
# Invoked as:
#   XDG_CACHE_HOME=/tmp/fs-missing-isdirectory-cache \
#     nix develop -c bash tests/haxe/fs-missing-isdirectory/run.sh
# (the scratch mount may drop the executable bit; call through `bash`).
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
if [ ! -f "$ROOT/boring.json" ]; then
	printf 'boring.json absent at %s; wrong worktree\n' "$ROOT"
	exit 1
fi
if [ -z "${IN_NIX_SHELL:-}${IN_NIX:-}" ]; then
	printf 'run through: nix develop -c bash tests/haxe/fs-missing-isdirectory/run.sh\n'
	exit 1
fi

OUT="${FS_MISSING_ISDIR_OUT:-$ROOT/out/fs-missing-isdirectory}"
ATTEMPT="${FS_MISSING_ISDIR_ATTEMPT:-attempt-$(date -u +%Y%m%dT%H%M%SZ)}"
RUN="$OUT/$ATTEMPT"
if [ -e "$RUN" ]; then
	printf 'attempt directory %s already exists; refusing to overwrite\n' "$RUN"
	exit 1
fi
mkdir -p "$RUN/stages" || exit 1

# Every arm resolves the probe's relative paths against $ROOT; the existing
# directory is created once here so "missing" really names no path.
EXISTING_REL="out/fs-missing-isdirectory/probe/existing-directory"
rm -rf "$ROOT/$EXISTING_REL"
mkdir -p "$ROOT/$EXISTING_REL"

TAB="$(printf '\t')"
printf 'stage%sexit%snote\n' "$TAB" "$TAB" >"$RUN/status.tsv"

# stage <name> <command...>: run from $ROOT, record everything.
stage() {
	local name=$1
	shift
	local dir="$RUN/stages/$name"
	mkdir -p "$dir"
	{
		printf 'cwd %s\n' "$ROOT"
		printf 'argv'
		printf ' %q' "$@"
		printf '\n'
	} >"$dir/argv"
	( cd "$ROOT" && "$@" ) >"$dir/stdout" 2>"$dir/stderr"
	local st=$?
	printf '%s\n' "$st" >"$dir/status"
	printf '%s%s%s\n' "$name" "$TAB" "$st" >>"$RUN/status.tsv"
	printf 'stage %-24s exit=%s\n' "$name" "$st"
	return "$st"
}

{
	printf 'attempt %s\n' "$ATTEMPT"
	printf 'date %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	printf 'worktree %s\n' "$ROOT"
	haxe --version
	printf 'bun %s\n' "$(bun --version)"
	printf 'node %s\n' "$(node --version)"
	printf 'kotlinc %s\n' "$(kotlinc -version 2>&1 | head -1)"
	printf 'dart %s\n' "$(dart --version 2>&1 | head -1)"
	printf 'rustc %s\n' "$(rustc --version)"
} >"$RUN/identity.txt" 2>&1

# --- TypeScript
ts_case() {
	local gen="$RUN/ts-gen"
	if ! stage gen-ts haxe tests/haxe/fs-missing-isdirectory/gen/ts.hxml -D ts-output="$gen"; then
		return
	fi
	cp "$HERE/native/harness.ts" "$gen/harness.ts"
	stage run-ts bun "$gen/harness.ts"
}
ts_case

# --- Kotlin: the driver's two-pass recipe (library first, then the harness).
kotlin_case() {
	local gen="$RUN/kotlin-gen" build="$RUN/kotlin-build"
	if ! stage gen-kotlin haxe tests/haxe/fs-missing-isdirectory/gen/kotlin.hxml -D kotlin-output="$gen"; then
		return
	fi
	mkdir -p "$build"
	find "$gen" -name '*.kt' ! -path '*/runtime/test/*' >"$RUN/kotlin-lib-files.txt"
	if ! stage compile-kotlin kotlinc -Xallow-kotlin-package @"$RUN/kotlin-lib-files.txt" -include-runtime -d "$build/library.jar"; then
		return
	fi
	if ! stage compile-kotlin-harness kotlinc -Xallow-kotlin-package -cp "$build/library.jar" "$HERE/native/Harness.kt" -d "$build/tests.jar"; then
		return
	fi
	stage run-kotlin java -cp "$build/library.jar:$build/tests.jar" HarnessKt
}
kotlin_case

# --- Dart
dart_case() {
	local gen="$RUN/dart-gen"
	if ! stage gen-dart haxe tests/haxe/fs-missing-isdirectory/gen/dart.hxml -D dart-output="$gen" -D dart-test-output="$RUN/dart-test-gen"; then
		return
	fi
	cp "$HERE/native/harness.dart" "$gen/harness.dart"
	{
		printf 'name: fsmissing_isdirectory_probe\n'
		printf 'environment:\n'
		printf "  sdk: '>=3.0.0'\n"
	} >"$gen/pubspec.yaml"
	stage run-dart dart "$gen/harness.dart"
}
dart_case

# --- Rust
rust_case() {
	local gen="$RUN/rust-gen" build="$RUN/rust-build"
	if ! stage gen-rust haxe tests/haxe/fs-missing-isdirectory/gen/rust.hxml -D rust-output="$gen"; then
		return
	fi
	mkdir -p "$build"
	if ! stage rustc-lib rustc --crate-type lib --edition=2024 --crate-name fs_missing_isdirectory -o "$build/libfs_missing_isdirectory.rlib" "$gen/lib.rs"; then
		return
	fi
	if ! stage rustc-bin rustc --edition=2024 -o "$build/harness" "$HERE/native/harness.rs" --extern "fs_missing_isdirectory=$build/libfs_missing_isdirectory.rlib"; then
		return
	fi
	stage run-rust "$build/harness"
}
rust_case

# --- readings and comparison
printf '\nreadings (stdout of each run stage):\n'
for arm in ts kotlin dart rust; do
	status="$(cat "$RUN/stages/run-$arm/status" 2>/dev/null || printf 'not-reached')"
	stdout="$RUN/stages/run-$arm/stdout"
	if [ -f "$stdout" ] && cmp -s "$stdout" "$HERE/expected.txt"; then
		verdict=MATCH
	elif [ -f "$stdout" ]; then
		verdict=MISMATCH
	else
		verdict=NO-STDOUT
	fi
	printf -- '-- %s exit=%s %s\n' "$arm" "$status" "$verdict"
	if [ -f "$stdout" ]; then sed 's/^/   /' "$stdout"; else printf '   (no stdout)\n'; fi
done
printf 'attempt directory: %s\n' "$RUN"
