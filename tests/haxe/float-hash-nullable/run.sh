#!/usr/bin/env bash
# Durable runner for the nullable-float hashCode regression contract
# (board t-mvzn8ckw-vh3s).
#
# One invocation allocates one fresh run directory under
# out/float-hash-nullable/runs and never rewrites or removes another one, so
# every attempt including a failed one is retained. The contract asserts:
#   1) the generated Kotlin (f32 and f64) and Dart trees compile (exit 0);
#   2) the generated hashCode guards the nullable field (grep the artifacts:
#      the nullable float field must show "if (x == null) 0 else" on Kotlin
#      and "x == null ? 0 :" on Dart, i.e. no bare toBits() on a nullable);
#   3) the generated hashCode/equals are correct at runtime: the native
#      harnesses (native/Main.kt against the f64 tree, native/main.dart)
#      instantiate the generated class and assert null / signed zero hash
#      equal, NaN is stable, and equals semantics are unchanged.
# A stage runs only when its producer stage exited zero. Every assertion
# failure is a finding and the runner exits nonzero.
#
# Invoke from the repository root inside the pinned toolchain:
#   nix develop -c bash tests/haxe/float-hash-nullable/run.sh
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
cd "$ROOT" || exit 2
if [ "$ROOT" != "$(pwd)" ] || [ ! -f "$ROOT/flake.nix" ]; then
	printf 'the repository root was not resolved: %s\n' "$ROOT"
	exit 2
fi
if [ "${IN_NIX_SHELL:-}" = "" ]; then
	printf 'run this runner through: nix develop -c bash tests/haxe/float-hash-nullable/run.sh\n'
	exit 2
fi

RUN_PARENT="$ROOT/out/float-hash-nullable/runs"
mkdir -p "$RUN_PARENT" || exit 2
RUN="$(mktemp -d "$RUN_PARENT/float-hash-nullable-XXXXXXXX")" || {
	printf 'run directory allocation failed\n'
	exit 2
}
LOGS="$RUN/logs"
mkdir -p "$LOGS" || exit 2
BUILD="$RUN/build"
mkdir -p "$BUILD" || exit 2

FINDINGS="$RUN/findings.txt"
: >"$FINDINGS"
VERDICT=pass

log() { printf '%s\n' "$1"; }

# run_stage <stage> <command...>
# Records argv, both raw streams, and the numeric status. A nonzero status is
# a finding.
run_stage() {
	local stage="$1"
	shift
	printf '%s\0' "$@" >"$LOGS/$stage.argv"
	"$@" >"$LOGS/$stage.stdout" 2>"$LOGS/$stage.stderr"
	local status=$?
	printf '%s\n' "$status" >"$LOGS/$stage.status"
	log "$stage status=$status"
	if [ "$status" != "0" ]; then
		VERDICT=fail
		printf 'stage %s failed with status %s\n' "$stage" "$status" >>"$FINDINGS"
		sed 's/^/    /' "$LOGS/$stage.stderr" >>"$FINDINGS"
	fi
	return "$status"
}

# run_stage_in <dir> <stage> <command...>
# Like run_stage but runs the command from <dir>.
run_stage_in() {
	local dir="$1"
	local stage="$2"
	shift 2
	printf '%s\0' "$@" >"$LOGS/$stage.argv"
	( cd "$dir" && "$@" >"$LOGS/$stage.stdout" 2>"$LOGS/$stage.stderr" )
	local status=$?
	printf '%s\n' "$status" >"$LOGS/$stage.status"
	log "$stage status=$status"
	if [ "$status" != "0" ]; then
		VERDICT=fail
		printf 'stage %s failed with status %s\n' "$stage" "$status" >>"$FINDINGS"
		sed 's/^/    /' "$LOGS/$stage.stderr" >>"$FINDINGS"
	fi
	return "$status"
}

# grep_assert <stage> <file> <pattern> <message>
# Asserts the generated artifact contains the pattern (the nullable-hash
# guard). A missing pattern is a finding.
grep_assert() {
	local stage="$1"
	local file="$2"
	local pattern="$3"
	local message="$4"
	if grep -q "$pattern" "$file"; then
		log "$stage ok: $message"
	else
		VERDICT=fail
		printf 'stage %s failed: %s (pattern not found in %s)\n' "$stage" "$message" "$file" >>"$FINDINGS"
		log "$stage FAIL: $message"
	fi
}

# generate <target> <output-dir> <extra-define...>
generate() {
	local target="$1"
	local output_dir="$2"
	shift 2
	run_stage "gen-$target" haxe "$HERE/hxml/$target.hxml" "$@"
}

# --- Kotlin f32 -----------------------------------------------------------------
KOTLIN_F32_DIR="$RUN/kotlin-f32-gen"
KOTLIN_F32_JAR="$BUILD/kotlin-f32-library.jar"
if generate kotlin "$KOTLIN_F32_DIR" -D float-precision=f32 -D "kotlin-output=$KOTLIN_F32_DIR"; then
	kotlin_f32_sources="$(find "$KOTLIN_F32_DIR" -name '*.kt' -not -path '*/runtime/test/*' | sort | tr '\n' ' ')"
	# shellcheck disable=SC2086
	run_stage kotlinc-f32 kotlinc $kotlin_f32_sources -Xallow-kotlin-package -include-runtime -d "$KOTLIN_F32_JAR"
	# Artifact assertion: the nullable float field must be null-guarded.
	F32_SRC="$(find "$KOTLIN_F32_DIR" -name 'NullableFloatRecord.kt' | head -1)"
	if [ -n "$F32_SRC" ]; then
		grep_assert grep-f32-null-guard "$F32_SRC" 'if (this.value == null) 0 else' 'Kotlin f32 nullable float field is null-guarded'
	fi
fi

# --- Kotlin f64 -----------------------------------------------------------------
KOTLIN_F64_DIR="$RUN/kotlin-f64-gen"
KOTLIN_F64_JAR="$BUILD/kotlin-f64-library.jar"
KOTLIN_F64_HARNESS="$BUILD/kotlin-f64-harness.jar"
if generate kotlin "$KOTLIN_F64_DIR" -D float-precision=f64 -D "kotlin-output=$KOTLIN_F64_DIR"; then
	kotlin_f64_sources="$(find "$KOTLIN_F64_DIR" -name '*.kt' -not -path '*/runtime/test/*' | sort | tr '\n' ' ')"
	# shellcheck disable=SC2086
	run_stage kotlinc-f64 kotlinc $kotlin_f64_sources -Xallow-kotlin-package -include-runtime -d "$KOTLIN_F64_JAR"
	F64_SRC="$(find "$KOTLIN_F64_DIR" -name 'NullableFloatRecord.kt' | head -1)"
	if [ -n "$F64_SRC" ]; then
		grep_assert grep-f64-null-guard "$F64_SRC" 'if (this.value == null) 0 else' 'Kotlin f64 nullable float field is null-guarded'
	fi
	if [ -f "$KOTLIN_F64_JAR" ]; then
		run_stage kotlinc-f64-harness kotlinc -Xallow-kotlin-package -cp "$KOTLIN_F64_JAR" "$HERE/native/Main.kt" -d "$KOTLIN_F64_HARNESS"
		if [ -f "$KOTLIN_F64_HARNESS" ]; then
			run_stage run-kotlin-f64 java -cp "$KOTLIN_F64_JAR:$KOTLIN_F64_HARNESS" MainKt
		fi
	fi
fi

# --- Dart -----------------------------------------------------------------------
DART_DIR="$RUN/dart-gen"
DART_ENTRY="$RUN/entry-dart"
mkdir -p "$DART_ENTRY" || exit 2
cp "$HERE/native/main.dart" "$DART_ENTRY/main.dart" || exit 2
if generate dart "$DART_DIR" -D float-precision=f64 -D "dart-output=$DART_DIR" -D "dart-test-output=$RUN/dart-gen-tests"; then
	DART_SRC="$(find "$DART_DIR" -name 'float_hash_nullable_contract.dart' | head -1)"
	if [ -n "$DART_SRC" ]; then
		grep_assert grep-dart-null-guard "$DART_SRC" 'this.value == null ? 0 :' 'Dart nullable float field is null-guarded'
	fi
	# The harness imports ../dart-gen relative to its own directory, so run it
	# from the entry directory where the generated tree is a sibling.
	run_stage_in "$DART_ENTRY" dart-analyze dart analyze
	run_stage_in "$DART_ENTRY" dart-compile dart compile exe main.dart
	if [ -f "$DART_ENTRY/main.exe" ]; then
		run_stage run-dart "$DART_ENTRY/main.exe"
	fi
fi

printf 'run directory %s\n' "$RUN"
printf 'verdict %s\n' "$VERDICT"
if [ -s "$FINDINGS" ]; then
	printf 'findings\n'
	cat "$FINDINGS"
	exit 1
fi
printf 'float-hash-nullable contract: all targets passed\n'
exit 0
