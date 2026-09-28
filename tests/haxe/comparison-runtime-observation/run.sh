#!/usr/bin/env bash
# Durable runner for the comparison observation fixture.
#
# One invocation allocates one fresh run directory under
# out/comparison-runtime-observation/runs and never rewrites or removes another one, so
# every attempt including a failed one is retained. Every stage writes its
# NUL-separated argv, its working directory, separate raw standard output and
# standard error, and a numeric status file; no verdict is derived from log
# text. A stage runs only when its producer stage exited zero, and every
# dependent stage of a failed producer receives an explicit not-reached row
# naming that producer.
#
# Each generated program is invoked once per case, so a crash in one case
# cannot prevent the other cases from being recorded. A case whose process
# fails is a runtime failure of that target and stays a finding. Status 2 is
# the harness reporting an unknown case name, which is a harness defect.
# The expected observation text lives in expected.tsv and is authored from
# docs/specs/stdlib/16-dataclass-sorted-keys.md; no expectation is derived
# from any target output.
#
# Invoke from the repository root inside the pinned toolchain:
#   nix develop -c bash tests/haxe/comparison-runtime-observation/run.sh
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
# The fixture lives three levels below the repository root
# (tests/haxe/comparison-runtime-observation), so the repository root is three levels up.
ROOT="$(cd "$HERE/../../.." && pwd)"
cd "$ROOT" || exit 2
printf 'repository root %s\n' "$ROOT"
if [ "$ROOT" != "$(pwd)" ] || [ ! -f "$ROOT/flake.nix" ]; then
	printf 'the repository root was not resolved: %s\n' "$ROOT"
	exit 2
fi

if [ "${IN_NIX_SHELL:-}" = "" ]; then
	printf 'run this runner through: nix develop -c bash tests/haxe/comparison-runtime-observation/run.sh\n'
	exit 2
fi

RUN_PARENT="$ROOT/out/comparison-runtime-observation/runs"
mkdir -p "$RUN_PARENT" || exit 2
RUN="$(mktemp -d "$RUN_PARENT/comparison-XXXXXXXX")" || {
	printf 'run directory allocation failed\n'
	exit 2
}

LOGS="$RUN/logs"
mkdir -p "$LOGS" || exit 2

CASES="int-ordinary int-extremes array-order nullable-order string-order"

STATUS="$RUN/status.tsv"
TAB="$(printf '\t')"
printf 'stage%sexpected%sobserved%sproducer\n' "$TAB" "$TAB" "$TAB" >"$STATUS"
: >"$RUN/expected-stages.txt"
: >"$RUN/findings.txt"
VERDICT=recorded

log() {
	printf '%s\n' "$1"
}

# record_row <stage> <expected> <observed> <producer>
record_row() {
	printf '%s%s%s%s%s%s%s\n' "$1" "$TAB" "$2" "$TAB" "$3" "$TAB" "$4" >>"$STATUS"
	log "$1 expected=$2 observed=$3 producer=$4"
}

# expect_stage <stage>
expect_stage() {
	printf '%s\n' "$1" >>"$RUN/expected-stages.txt"
}

# run_process <stage> <command...>
# Records the argv in the lossless NUL-separated form, the working directory,
# both raw streams, and the numeric status, and states zero as the expected
# status. The command inherits this one pinned nix develop environment; no
# stage nests a second Nix call.
run_process() {
	local stage="$1"
	shift
	expect_stage "$stage"
	printf '%s\0' "$@" >"$LOGS/$stage.argv"
	printf '%s\n' "$ROOT" >"$LOGS/$stage.cwd"
	"$@" >"$LOGS/$stage.stdout" 2>"$LOGS/$stage.stderr"
	local observed=$?
	printf '%s\n' "$observed" >"$LOGS/$stage.status"
	record_row "$stage" zero "$observed" "$stage"
	return "$observed"
}

# run_case <target> <case> <command...>
# Runs one target program for one case and compares its observation text with
# the authored expectation of expected.tsv.
run_case() {
	local target="$1" case_name="$2"
	shift 2
	local stage="run-$target-$case_name"
	local expected
	expected="$(awk -F'\t' -v name="$case_name" '$1 == name { print $2 }' "$HERE/expected.tsv")"
	if [ -z "$expected" ]; then
		VERDICT=harness-defect
		log "no authored expectation for case $case_name"
		return 1
	fi
	# The stage is declared by the upfront declaration loop, so a case the run
	# never reaches keeps its declared row.
	printf '%s\0' "$@" >"$LOGS/$stage.argv"
	printf '%s\n' "$ROOT" >"$LOGS/$stage.cwd"
	"$@" >"$LOGS/$stage.stdout" 2>"$LOGS/$stage.stderr"
	local observed_status=$?
	printf '%s\n' "$observed_status" >"$LOGS/$stage.status"
	if [ "$observed_status" = "2" ]; then
		VERDICT=harness-defect
		record_row "$stage" harness-defect "$observed_status" "$stage"
		return 0
	fi
	if [ "$observed_status" != "0" ]; then
		record_row "$stage" "$expected" "runtime-failure-$observed_status" "$stage"
		printf 'stage %s failed inside the generated operation with status %s\n' "$stage" "$observed_status" >>"$RUN/findings.txt"
		return 0
	fi
	local observed
	observed="$(cat "$LOGS/$stage.stdout")"
	if [ "$observed" = "$expected" ]; then
		record_row "$stage" "$expected" match "$stage"
	else
		record_row "$stage" "$expected" mismatch "$stage"
		printf 'stage %s observed text differs from the authored expectation\n' "$stage" >>"$RUN/findings.txt"
	fi
	return 0
}

# mark_unreached <producer> <observed-status> <stage...>
mark_unreached() {
	local producer="$1" observed="$2"
	shift 2
	local stage
	for stage in "$@"; do
		record_row "$stage" not-reached "producer-$producer-status-$observed" "$producer"
		printf 'stage %s not reached through %s\n' "$stage" "$producer" >>"$RUN/findings.txt"
	done
}

# hash_file <stage> <path>
# One digest line, or an explicit failure. A failed digest is a harness
# defect; it never stops the remaining stages.
hash_file() {
	local stage="$1" path="$2"
	if ! sha256sum "$path" >>"$RUN/hashes.txt" 2>"$LOGS/hash-$stage.stderr"; then
		VERDICT=harness-defect
		log "cannot hash $path (stage $stage)"
		return 1
	fi
	return 0
}

# generated_module_path <target>
generated_module_path() {
	case "$1" in
	ts) printf 'comparison/ComparisonObserve.ts' ;;
	kotlin) printf 'comparison/ComparisonObserve.kt' ;;
	rust) printf 'comparison/comparison_observe.rs' ;;
	swift) printf 'comparison/ComparisonObserve.swift' ;;
	dart) printf 'lib/comparison/comparison_observe.dart' ;;
	esac
}

# generate <target> <output-dir> <define-name> <extra-define...>
# Runs one focused generation entry with --verbose, so the recorded output
# carries the actual Haxe classpaths, defines, and the absolute path of every
# module the compiler parsed. The module summary keeps the paths of the
# modules this fixture depends on.
generate() {
	local target="$1"
	shift
	local stage="gen-$target"
	local output_dir="$1"
	shift
	if ! run_process "$stage" haxe "$HERE/hxml/$target.hxml" --verbose "$@"; then
		return 1
	fi
	# A failed digest records a harness defect; the generated tree still exists
	# and the dependent stages still run.
	hash_file "$stage-generated" "$output_dir/$(generated_module_path "$target")"
	hash_file "$stage-filelist" "$output_dir/_GeneratedFiles.txt"
	{
		printf 'classpaths and defines of the generation\n'
		grep -E '^(Classpath|Defines):' "$LOGS/$stage.stdout" || printf 'no classpath or define line\n'
		printf 'paths of the modules this fixture depends on\n'
		grep -E '^Parsed .*(comparison/ComparisonObserve|std/SortedMap|std/ReadOnlyArray|runtime/SortedTable)' "$LOGS/$stage.stdout" |
			sort -u || printf 'no expected module path in the verbose output\n'
	} >"$LOGS/modules-$target.txt"
	return 0
}

# mark_case_unreached <producer> <observed-status> <target>
mark_case_unreached() {
	local producer="$1" observed="$2" target="$3"
	mark_unreached "$producer" "$observed" \
		"run-$target-int-ordinary" "run-$target-int-extremes" "run-$target-array-order" \
		"run-$target-nullable-order" "run-$target-string-order"
}

# --- Identity -----------------------------------------------------------------
run_process identity-date date -u +%Y-%m-%dT%H:%M:%SZ
run_process identity-worktree git rev-parse HEAD
run_process identity-worktree-status git status --short
run_process identity-haxe haxe --version
run_process identity-bun bun --version
run_process identity-rustc rustc --version
run_process identity-kotlin kotlin -version
run_process identity-dart dart --version
run_process identity-swift swift --version
{
	printf 'run directory %s\n' "$RUN"
	printf 'repository root %s\n' "$ROOT"
	printf 'haxe binary %s\n' "$(command -v haxe || printf 'not found')"
	printf 'runner %s\n' "$HERE/run.sh"
} >"$RUN/identity.txt"

# Required stages, declared before any stage runs, so a stage the run never
# reaches stays in the exact membership check. run_process and run_case
# declare their own stage when they run.
for target in ts kotlin rust swift dart; do
	case "$target" in
	kotlin)
		expect_stage "kotlinc-library-$target"
		expect_stage "kotlinc-library-observation-$target"
		expect_stage "kotlinc-harness-$target"
		;;
	rust)
		expect_stage "rustc-library-$target"
		expect_stage "rustc-harness-$target"
		;;
	swift)
		expect_stage "swiftc-library-$target"
		expect_stage "swiftc-harness-$target"
		;;
	esac
	for case_name in $CASES; do
		expect_stage "run-$target-$case_name"
	done
done

# Authored inputs, hashed before and after the attempt.
: >"$RUN/sources.txt"
{
	printf '%s\n' comparison/ComparisonObserve.hx
	printf '%s\n' expected.tsv
	for hxml in ts kotlin rust swift dart; do
		printf 'hxml/%s.hxml\n' "$hxml"
	done
	printf '%s\n' native/main.ts native/Main.kt native/harness.rs native/main.swift native/main.dart
	printf '%s\n' run.sh
} | sed "s|^|$HERE/|" >"$RUN/sources.txt"
if ! sha256sum $(cat "$RUN/sources.txt") >"$RUN/source-hashes-before.txt" 2>"$LOGS/hash-sources-before.stderr"; then
	log "cannot hash the authored inputs before the attempt"
	cat "$LOGS/hash-sources-before.stderr"
	exit 2
fi

# --- TypeScript -----------------------------------------------------------------
TS_DIR="$RUN/ts-gen"
TS_ENTRY="$RUN/entry-ts"
mkdir -p "$TS_ENTRY" || exit 2
cp "$HERE/native/main.ts" "$TS_ENTRY/main.ts" || exit 2
hash_file harness-ts "$TS_ENTRY/main.ts"
gen_status=0
generate ts "$TS_DIR" -D "ts-output=$TS_DIR" || gen_status=$?
if [ "$gen_status" = "0" ]; then
	for case_name in $CASES; do
		run_case ts "$case_name" bun "$TS_ENTRY/main.ts" "$case_name"
	done
else
	mark_case_unreached "gen-ts" "$gen_status" ts
fi

# --- Kotlin ---------------------------------------------------------------------
# The first library stage compiles every emitted file, which is the whole tree
# the compiler wrote. The second stage compiles the library the observation
# links against: the business module and the general runtime. The test host
# package stays out of it only if the whole tree failed to compile, and that
# failure stays a finding with its diagnostic.
KOTLIN_DIR="$RUN/kotlin-gen"
BUILD="$RUN/build"
mkdir -p "$BUILD" || exit 2
KOTLIN_JAR="$BUILD/kotlin-library.jar"
HARNESS_JAR="$BUILD/kotlin-harness.jar"
gen_status=0
generate kotlin "$KOTLIN_DIR" -D "kotlin-output=$KOTLIN_DIR" || gen_status=$?
if [ "$gen_status" = "0" ]; then
	kotlin_all_sources="$(find "$KOTLIN_DIR" -name '*.kt' | sort | tr '\n' ' ')"
	kotlin_tree_sources="$(find "$KOTLIN_DIR" -name '*.kt' -not -path '*/runtime/test/*' | sort | tr '\n' ' ')"

	stage="kotlinc-library-kotlin"
	# shellcheck disable=SC2086
	printf '%s\0' kotlinc -Xallow-kotlin-package $kotlin_all_sources -include-runtime -d "$KOTLIN_JAR" >"$LOGS/$stage.argv"
	printf '%s\n' "$ROOT" >"$LOGS/$stage.cwd"
	# shellcheck disable=SC2086
	kotlinc -Xallow-kotlin-package $kotlin_all_sources -include-runtime -d "$KOTLIN_JAR" \
		>"$LOGS/$stage.stdout" 2>"$LOGS/$stage.stderr"
	kotlin_tree_status=$?
	printf '%s\n' "$kotlin_tree_status" >"$LOGS/$stage.status"
	record_row "$stage" zero "$kotlin_tree_status" "$stage"
	if [ "$kotlin_tree_status" != "0" ]; then
		printf 'the emitted Kotlin tree does not compile as a whole; the observation library excludes runtime/test\n' >>"$RUN/findings.txt"
	fi

	stage="kotlinc-library-observation-kotlin"
	# shellcheck disable=SC2086
	printf '%s\0' kotlinc -Xallow-kotlin-package $kotlin_tree_sources -include-runtime -d "$KOTLIN_JAR" >"$LOGS/$stage.argv"
	printf '%s\n' "$ROOT" >"$LOGS/$stage.cwd"
	# shellcheck disable=SC2086
	kotlinc -Xallow-kotlin-package $kotlin_tree_sources -include-runtime -d "$KOTLIN_JAR" \
		>"$LOGS/$stage.stdout" 2>"$LOGS/$stage.stderr"
	kotlin_library_status=$?
	printf '%s\n' "$kotlin_library_status" >"$LOGS/$stage.status"
	record_row "$stage" zero "$kotlin_library_status" "$stage"

	if [ "$kotlin_library_status" != "0" ]; then
		mark_unreached "kotlinc-library-observation-kotlin" "$kotlin_library_status" "kotlinc-harness-kotlin"
		mark_case_unreached "kotlinc-library-observation-kotlin" "$kotlin_library_status" kotlin
	else
		hash_file kotlinc-library-kotlin "$KOTLIN_JAR"
		stage="kotlinc-harness-kotlin"
		printf '%s\0' kotlinc -Xallow-kotlin-package -cp "$KOTLIN_JAR" "$HERE/native/Main.kt" -d "$HARNESS_JAR" >"$LOGS/$stage.argv"
		printf '%s\n' "$ROOT" >"$LOGS/$stage.cwd"
		kotlinc -Xallow-kotlin-package -cp "$KOTLIN_JAR" "$HERE/native/Main.kt" -d "$HARNESS_JAR" \
			>"$LOGS/$stage.stdout" 2>"$LOGS/$stage.stderr"
		kotlin_harness_status=$?
		printf '%s\n' "$kotlin_harness_status" >"$LOGS/$stage.status"
		record_row "$stage" zero "$kotlin_harness_status" "$stage"
		if [ "$kotlin_harness_status" != "0" ]; then
			mark_case_unreached "$stage" "$kotlin_harness_status" kotlin
		else
			hash_file "$stage" "$HARNESS_JAR"
			for case_name in $CASES; do
				run_case kotlin "$case_name" java -cp "$KOTLIN_JAR:$HARNESS_JAR" MainKt "$case_name"
			done
		fi
	fi
else
	mark_unreached "gen-kotlin" "$gen_status" "kotlinc-library-kotlin" "kotlinc-library-observation-kotlin" "kotlinc-harness-kotlin"
	mark_case_unreached "gen-kotlin" "$gen_status" kotlin
fi

# --- Rust -----------------------------------------------------------------------
RUST_DIR="$RUN/rust-gen"
RUST_BUILD="$RUN/build-rust"
mkdir -p "$RUST_BUILD" || exit 2
RUST_LIB="$RUST_BUILD/libcmpgen.rlib"
RUST_HARNESS="$RUST_BUILD/harness"
gen_status=0
generate rust "$RUST_DIR" -D "rust-output=$RUST_DIR" || gen_status=$?
if [ "$gen_status" = "0" ]; then
	stage="rustc-library-rust"
	printf '%s\0' rustc --edition=2024 --crate-type lib --crate-name cmpgen -o "$RUST_LIB" "$RUST_DIR/lib.rs" >"$LOGS/$stage.argv"
	printf '%s\n' "$ROOT" >"$LOGS/$stage.cwd"
	rustc --edition=2024 --crate-type lib --crate-name cmpgen -o "$RUST_LIB" "$RUST_DIR/lib.rs" \
		>"$LOGS/$stage.stdout" 2>"$LOGS/$stage.stderr"
	rust_library_status=$?
	printf '%s\n' "$rust_library_status" >"$LOGS/$stage.status"
	record_row "$stage" zero "$rust_library_status" "$stage"
	if [ "$rust_library_status" != "0" ]; then
		mark_unreached "$stage" "$rust_library_status" "rustc-harness-rust"
		mark_case_unreached "$stage" "$rust_library_status" rust
	else
		hash_file "$stage" "$RUST_LIB"
		stage="rustc-harness-rust"
		printf '%s\0' rustc --edition=2024 -o "$RUST_HARNESS" "$HERE/native/harness.rs" --extern "cmpgen=$RUST_LIB" >"$LOGS/$stage.argv"
		printf '%s\n' "$ROOT" >"$LOGS/$stage.cwd"
		rustc --edition=2024 -o "$RUST_HARNESS" "$HERE/native/harness.rs" --extern "cmpgen=$RUST_LIB" \
			>"$LOGS/$stage.stdout" 2>"$LOGS/$stage.stderr"
		rust_harness_status=$?
		printf '%s\n' "$rust_harness_status" >"$LOGS/$stage.status"
		record_row "$stage" zero "$rust_harness_status" "$stage"
		if [ "$rust_harness_status" != "0" ]; then
			mark_case_unreached "$stage" "$rust_harness_status" rust
		else
			hash_file "$stage" "$RUST_HARNESS"
			for case_name in $CASES; do
				run_case rust "$case_name" "$RUST_HARNESS" "$case_name"
			done
		fi
	fi
else
	mark_unreached "gen-rust" "$gen_status" "rustc-library-rust" "rustc-harness-rust"
	mark_case_unreached "gen-rust" "$gen_status" rust
fi

# --- Swift ----------------------------------------------------------------------
SWIFT_DIR="$RUN/swift-gen"
SWIFT_BUILD="$RUN/build-swift"
mkdir -p "$SWIFT_BUILD" || exit 2
SWIFT_MODULE=CmpObs
SWIFT_LIB="$SWIFT_BUILD/lib$SWIFT_MODULE.so"
SWIFT_HARNESS="$SWIFT_BUILD/runner"
# The generated tree is one self-contained module: Runtime.swift carries every
# runtime symbol the business files reference, so no import resolution is
# needed. The pinned loader flag mirrors the root Package.swift linker
# settings; the toolchain otherwise records an unspecified interpreter path.
loader_args=()
if [ "${BORING_SWIFT_DYNAMIC_LINKER:-}" != "" ]; then
	loader_args=(-Xlinker -dynamic-linker -Xlinker "$BORING_SWIFT_DYNAMIC_LINKER")
fi
gen_status=0
generate swift "$SWIFT_DIR" -D "swift-output=$SWIFT_DIR" || gen_status=$?
if [ "$gen_status" = "0" ]; then
	stage="swiftc-library-swift"
	swift_sources="$(find "$SWIFT_DIR" -name '*.swift' | sort | tr '\n' ' ')"
	# shellcheck disable=SC2086
	printf '%s\0' swiftc -emit-library -emit-module "${loader_args[@]}" $swift_sources -module-name "$SWIFT_MODULE" -o "$SWIFT_LIB" >"$LOGS/$stage.argv"
	printf '%s\n' "$ROOT" >"$LOGS/$stage.cwd"
	# shellcheck disable=SC2086
	swiftc -emit-library -emit-module "${loader_args[@]}" $swift_sources -module-name "$SWIFT_MODULE" -o "$SWIFT_LIB" \
		>"$LOGS/$stage.stdout" 2>"$LOGS/$stage.stderr"
	swift_library_status=$?
	printf '%s\n' "$swift_library_status" >"$LOGS/$stage.status"
	record_row "$stage" zero "$swift_library_status" "$stage"
	if [ "$swift_library_status" != "0" ]; then
		mark_unreached "$stage" "$swift_library_status" "swiftc-harness-swift"
		mark_case_unreached "$stage" "$swift_library_status" swift
	else
		hash_file "$stage" "$SWIFT_LIB"
		stage="swiftc-harness-swift"
		printf '%s\0' swiftc "${loader_args[@]}" "$HERE/native/main.swift" -I "$SWIFT_BUILD" -L "$SWIFT_BUILD" -l"$SWIFT_MODULE" -o "$SWIFT_HARNESS" >"$LOGS/$stage.argv"
		printf '%s\n' "$ROOT" >"$LOGS/$stage.cwd"
		swiftc "${loader_args[@]}" "$HERE/native/main.swift" -I "$SWIFT_BUILD" -L "$SWIFT_BUILD" -l"$SWIFT_MODULE" -o "$SWIFT_HARNESS" \
			>"$LOGS/$stage.stdout" 2>"$LOGS/$stage.stderr"
		swift_harness_status=$?
		printf '%s\n' "$swift_harness_status" >"$LOGS/$stage.status"
		record_row "$stage" zero "$swift_harness_status" "$stage"
		if [ "$swift_harness_status" != "0" ]; then
			mark_case_unreached "$stage" "$swift_harness_status" swift
		else
			hash_file "$stage" "$SWIFT_HARNESS"
			for case_name in $CASES; do
				run_case swift "$case_name" env LD_LIBRARY_PATH="$SWIFT_BUILD:${BORING_SWIFT_LIBDISPATCH:-}" "$SWIFT_HARNESS" "$case_name"
			done
		fi
	fi
else
	mark_unreached "gen-swift" "$gen_status" "swiftc-library-swift" "swiftc-harness-swift"
	mark_case_unreached "gen-swift" "$gen_status" swift
fi

# --- Dart -----------------------------------------------------------------------
DART_DIR="$RUN/dart-gen"
DART_ENTRY="$RUN/entry-dart"
mkdir -p "$DART_ENTRY" || exit 2
cp "$HERE/native/main.dart" "$DART_ENTRY/main.dart" || exit 2
hash_file harness-dart "$DART_ENTRY/main.dart"
gen_status=0
generate dart "$DART_DIR" -D "dart-output=$DART_DIR" -D "dart-test-output=$RUN/dart-gen-tests" || gen_status=$?
if [ "$gen_status" = "0" ]; then
	for case_name in $CASES; do
		run_case dart "$case_name" dart run "$DART_ENTRY/main.dart" "$case_name"
	done
else
	mark_case_unreached "gen-dart" "$gen_status" dart
fi

# --- Owned-file checks ------------------------------------------------------------
run_process format-check haxelib run formatter --check -s "$HERE/comparison"
run_process doc-style-check bun tools/doc-style/check.ts "$HERE"

# The authored inputs must hold the same bytes after the attempt as before.
if ! sha256sum $(cat "$RUN/sources.txt") >"$RUN/source-hashes-after.txt" 2>"$LOGS/hash-sources-after.stderr"; then
	VERDICT=harness-defect
	log "cannot hash the authored inputs after the attempt"
fi
if ! cmp -s "$RUN/source-hashes-before.txt" "$RUN/source-hashes-after.txt"; then
	VERDICT=harness-defect
	log "the authored inputs changed during the attempt"
	{
		printf 'before\n'
		cat "$RUN/source-hashes-before.txt"
		printf 'after\n'
		cat "$RUN/source-hashes-after.txt"
	} >"$RUN/source-hash-diff.txt"
fi

# Exact stage membership: every declared stage appears exactly once and no
# extra stage exists.
sort "$RUN/expected-stages.txt" -o "$RUN/expected-stages-sorted.txt"
awk -F'\t' 'NR > 1 { print $1 }' "$STATUS" | sort -o "$RUN/observed-stages.txt"
comm -3 "$RUN/expected-stages-sorted.txt" "$RUN/observed-stages.txt" >"$RUN/stage-diff.txt"
if [ -s "$RUN/stage-diff.txt" ]; then
	VERDICT=harness-defect
	{
		printf 'the recorded stage set differs from the declared set\n'
		cat "$RUN/stage-diff.txt"
	} >"$RUN/membership-finding.txt"
	printf 'membership check failed; see stage-diff.txt\n' >>"$RUN/findings.txt"
else
	printf 'the recorded stage set equals the declared set\n' >"$RUN/membership-finding.txt"
fi

# Warnings: a nonempty standard error of a successful stage stays evidence.
: >"$RUN/warnings.txt"
while IFS="$TAB" read -r stage expected observed producer; do
	[ "$stage" = "stage" ] && continue
	[ -z "$stage" ] && continue
	if [ -s "$LOGS/$stage.stderr" ]; then
		printf '%s ended with status %s and wrote standard error\n' "$stage" "$observed" >>"$RUN/warnings.txt"
		sed 's/^/    /' "$LOGS/$stage.stderr" >>"$RUN/warnings.txt"
	fi
	if grep -qi 'warning' "$LOGS/$stage.stdout" 2>/dev/null; then
		printf '%s standard output carries warning text; see logs/%s.stdout\n' "$stage" "$stage" >>"$RUN/warnings.txt"
	fi
done <"$STATUS"

{
	printf 'run directory %s\n' "$RUN"
	printf 'verdict %s\n' "$VERDICT"
	printf 'stages declared %s recorded %s\n' "$(wc -l <"$RUN/expected-stages.txt")" "$(( $(wc -l <"$STATUS") - 1 ))"
	printf 'findings\n'
	cat "$RUN/findings.txt"
	printf 'membership\n'
	cat "$RUN/membership-finding.txt"
	printf 'status rows\n'
	cat "$STATUS"
	printf 'warnings\n'
	cat "$RUN/warnings.txt"
} >"$RUN/summary.txt"

log "run directory $RUN"
log "verdict $VERDICT"
[ "$VERDICT" = "recorded" ] || exit 1
exit 0
