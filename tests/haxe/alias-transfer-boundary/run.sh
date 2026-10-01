#!/usr/bin/env bash
# Durable staged evidence runner for the alias-transfer-boundary fixture.
#
# One invocation allocates one fresh run directory under
# out/alias-transfer-boundary/runs/ and never rewrites an earlier one. Stages
# run with the pinned toolchain on PATH and record shell-quoted argv, cwd,
# separated streams, and exit status under $RUN/stages/<id>/ (identity
# stages under $RUN/identity/<label>/).
#
# The fixture observes the container-identity transfer across two shapes:
# (a) a Holder.Null<Array<Int>> field, and (b) an Array -> ReadOnlyArray
# argument/return relay. Per target the stages are gen, native compile,
# native run, and compare against the authored expected lines
# (expected.txt). A failed generation is an observation: the dependent
# native stages are recorded not-reached, never as a semantic difference.
# A compare difference is a recorded observation and not a fixture failure.
#
# Verdict vocabulary:
#   success                every stage ran to its expected status and all
#                           compares matched the authored lines
#   observed-differences   every stage ran to its expected status and at
#                           least one compare recorded a value difference
#   failed                 a stage exited with a non-expected status or a
#                           dependency was recorded not-reached
#   harness-defect         setup, identity, hashing, or membership failure
#
# Only failed and harness-defect exit nonzero; the others are retained
# evidence. Run from the repository root with the pinned toolchain on PATH
# and HAXELIB_PATH pointing at the worktree .haxelib (see README.md):
#   PATH=<pinned-tools> HAXELIB_PATH=$PWD/.haxelib \
#     bash tests/haxe/alias-transfer-boundary/run.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/../../support/stage-check.sh"
ROOT="$(cd "$HERE/../../.." && pwd)"
cd "$ROOT" || exit 1
if [ ! -f AGENT.md ]; then
	printf 'AGENT.md absent at %s; wrong worktree\n' "$ROOT"
	exit 1
fi
if [ ! -f tests/support/stage-check.sh ] \
	|| [ ! -f tests/haxe/alias-transfer-boundary/oracle.hxml ] \
	|| [ ! -f tests/haxe/alias-transfer-boundary/expected.txt ] \
	|| [ ! -f tests/haxe/alias-transfer-boundary/atb/ContainerAliasOracle.hx ] \
	|| [ ! -f tests/haxe/alias-transfer-boundary/atb/NullableHolder.hx ] \
	|| [ ! -f tests/haxe/alias-transfer-boundary/native/main.js ] \
	|| [ ! -f tests/haxe/alias-transfer-boundary/native/Main.kt ] \
	|| [ ! -f tests/haxe/alias-transfer-boundary/native/harness.rs ] \
	|| [ ! -f tests/haxe/alias-transfer-boundary/native/native-main.swift ] \
	|| [ ! -f tests/haxe/alias-transfer-boundary/native/main.dart ]; then
	printf 'fixture input missing; refusing to run\n'
	exit 1
fi
for t in ts kotlin rust swift dart; do
	[ -f "tests/haxe/alias-transfer-boundary/gen/$t.hxml" ] || {
		printf 'gen hxml missing for %s\n' "$t"
		exit 1
	}
done

# The boring library resolves through the worktree .haxelib (gitignored;
# set up once per checkout, see README.md). A missing dev pointer is a
# harness-defect, not a toolchain limitation.
if [ ! -f "$ROOT/.haxelib/reflaxe/.dev" ] || [ ! -f "$ROOT/.haxelib/boring/.dev" ]; then
	printf 'worktree .haxelib dev pointers missing; run the README setup first\n'
	exit 2
fi
export HAXELIB_PATH="${HAXELIB_PATH:-$ROOT/.haxelib}"

if ! mkdir -p out/alias-transfer-boundary/runs; then
	printf 'evidence parent creation failed\n'
	exit 1
fi
if ! RUN="$(mktemp -d out/alias-transfer-boundary/runs/atb-XXXXXXXX)"; then
	printf 'run directory allocation failed\n'
	exit 1
fi
RUN="$(cd "$RUN" && pwd)"

# The declared stage list is per-run state: it lives in the run directory,
# starts empty, and is never persisted into the fixture tree.
EXPECTED="$RUN/expected-stages.txt"
: >"$EXPECTED"
STAGES="$RUN/stages"
mkdir -p "$STAGES"

log() {
	printf '%s\n' "$1"
}

TAB="$(printf '\t')"
STATUS="$RUN/status.tsv"
printf 'stage%sexpected%sobserved%sproducer\n' "$TAB" "$TAB" "$TAB" >"$STATUS"
VERDICT=success
DIFFERENCES=0
UNREACHED=0
IDENTITY_FAILURES=0

expect_stage() {
	printf '%s\n' "$1" >>"$EXPECTED"
}

record() {
	local name=$1 expected=$2 observed=$3
	local producer=${4:-"-"}
	printf '%s%s%s%s%s%s%s\n' "$name" "$TAB" "$expected" "$TAB" "$observed" "$TAB" "$producer" >>"$STATUS"
	log "$name expected=$expected observed=$observed producer=$producer"
}

not_reached() {
	local producer=$1 observed=$2
	shift 2
	local name
	for name in "$@"; do
		record "$name" not-reached "producer-$producer-status-$observed" "$producer"
		UNREACHED=$((UNREACHED + 1))
	done
}

# stage <name> <expected> <command...>; records argv, cwd, separated
# streams and exit status; returns the producer status.
stage() {
	local name=$1 expected=$2
	shift 2
	local dir="$STAGES/$name"
	mkdir -p "$dir"
	{
		printf 'cwd %s\nargv' "$ROOT"
		printf ' %q' "$@"
		printf '\n'
	} >"$dir/argv"
	"$@" >"$dir/stdout" 2>"$dir/stderr"
	local observed=$?
	printf '%s\n' "$observed" >"$dir/status"
	record "$name" "$expected" "$observed" "$name"
	return "$observed"
}

# shape_lines <file>: count the labeled shape lines (5 expected).
shape_lines() {
	grep -c '^field=\|^fieldNull=\|^fieldRebind=\|^relay=\|^relayFresh=' "$1" 2>/dev/null || true
}

# identity_step <label> <command...>: one captured identity command.
identity_step() {
	local label=$1
	shift
	local dir="$RUN/identity/$label"
	mkdir -p "$dir"
	{
		printf 'cwd %s\nargv' "$ROOT"
		printf ' %q' "$@"
		printf '\n'
	} >"$dir/argv"
	"$@" >"$dir/stdout" 2>"$dir/stderr"
	local observed=$?
	printf '%s\n' "$observed" >"$dir/status"
	expect_stage "identity-$label"
	record "identity-$label" zero "$observed" identity
	if [ "$observed" != "0" ]; then
		printf 'identity step failed: %s status=%s\n' "$label" "$observed" >>"$RUN/identity-failures.txt"
		IDENTITY_FAILURES=$((IDENTITY_FAILURES + 1))
	fi
}

input_manifest() {
	local output=$1 listing="$RUN/input-files.list"
	{
		find packages/compiler tests/haxe/alias-transfer-boundary tests/support -type f -print0 \
			| sort -z >"$listing"
	} || return 1
	xargs -0 sha256sum <"$listing" >"$output" || return 1
}

# record_hash <stage> <role> <path>: a failed digest is a harness defect.
record_hash() {
	local stage=$1 role=$2 path=$3
	local line
	if [ ! -e "$path" ]; then
		printf 'hash of absent path stage=%s role=%s path=%s\n' "$stage" "$role" "$path" >>"$RUN/hash-failures.txt"
		VERDICT=harness-defect
		return 1
	fi
	if ! line="$(sha256sum "$path" 2>&1)"; then
		printf 'hash failed stage=%s role=%s path=%s detail=%s\n' "$stage" "$role" "$path" "$line" \
			>>"$RUN/hash-failures.txt"
		VERDICT=harness-defect
		return 1
	fi
	printf '%s %s %s\n' "$stage" "$role" "$line" >>"$RUN/hashes.txt"
	return 0
}

# tree_manifest <generated tree> <manifest output>: digests every generated
# file; a pipeline failure propagates and cannot certify artifact identity.
tree_manifest() {
	local tree=$1 manifest=$2
	if [ ! -d "$tree" ]; then
		printf 'missing tree %s\n' "$tree" >"$manifest"
		VERDICT=harness-defect
		return 1
	fi
	local list="$manifest.files"
	if ! find "$tree" -type f -print0 | sort -z >"$list"; then
		printf 'file listing failed for %s\n' "$tree" >"$manifest"
		VERDICT=harness-defect
		return 1
	fi
	if ! xargs -0 sha256sum <"$list" >"$manifest" 2>"$manifest.err"; then
		printf 'digest failed for %s\n' "$tree" >"$manifest"
		printf '%s\n' "$(cat "$manifest.err")" >>"$RUN/hash-failures.txt"
		VERDICT=harness-defect
		return 1
	fi
	return 0
}

# compare <stage> <run stdout file> <expected file>: a matching diff exits
# 0 (identical); a value difference exits 1 and is a recorded observation.
compare() {
	local name=$1 run_stdout=$2 expected=$3
	local dir="$STAGES/$name"
	mkdir -p "$dir"
	{
		printf 'cwd %s\nargv' "$ROOT"
		printf ' %q' "diff" "-u" "$expected" "$run_stdout"
		printf '\n'
	} >"$dir/argv"
	diff -u "$expected" "$run_stdout" >"$dir/stdout" 2>"$dir/stderr"
	local observed=$?
	printf '%s\n' "$observed" >"$dir/status"
	record "$name" identical "$observed" "$name"
	if [ "$observed" = "0" ]; then
		printf '%s matched the authored expected lines\n' "$name" >>"$RUN/compare-notes.txt"
	else
		printf '%s differs from the authored expected lines:\n' "$name" >>"$RUN/compare-notes.txt"
		sed 's/^/    /' "$dir/stdout" >>"$RUN/compare-notes.txt"
		DIFFERENCES=$((DIFFERENCES + 1))
	fi
}

# -------------------------------------------- Swift toolchain resolution
# The devShell `swiftc` is a wrapper that sets up its FHS environment
# through bubblewrap; this container rejects the bwrap uid map for an
# unprivileged user, so the wrapper fails. When the wrapper cannot run, fall
# back to the raw store toolchain with the FHS rootfs libraries and the CRT
# objects symlinked into the link working directory (ld.gold opens the
# bare-name CRT inputs relative to the CWD). The resolved toolchain and the
# reason are recorded in $RUN/swift-toolchain.txt.
SWIFTC_WRAPPER="$(command -v swiftc || true)"
SWIFTC=""
SWIFT_MODE=""
FHS_ROOTFS=""
GLIBC_LIB=""
GCCRT_DIR=""
LIBGCCS_DIR=""
SWIFT_LD=""
if [ -n "$SWIFTC_WRAPPER" ] \
	&& timeout 60 "$SWIFTC_WRAPPER" --version >"$RUN/swiftc-wrapper-probe.stdout" 2>"$RUN/swiftc-wrapper-probe.stderr"; then
	SWIFTC="$SWIFTC_WRAPPER"
	SWIFT_MODE=wrapper
else
	SWIFTROOT="$(grep -o '/nix/store/[^"]*-swift-toolchain-[^"]*' "$SWIFTC_WRAPPER" 2>/dev/null | head -1 | sed 's#/usr/bin/swiftc$##' || true)"
	FHSSCRIPT="$(grep -o '/nix/store/[^"]*-swift-[0-9.]*-fhs/bin/[a-z0-9.-]*' "$SWIFTC_WRAPPER" 2>/dev/null | head -1 || true)"
	if [ -n "$SWIFTROOT" ] && [ -x "$SWIFTROOT/usr/bin/swiftc" ] \
		&& [ -n "$FHSSCRIPT" ] && [ -f "$FHSSCRIPT" ]; then
		FHS_ROOTFS="$(grep -oE '/nix/store/[a-z0-9]+-swift-[0-9.]+-fhs-fhsenv-rootfs' "$FHSSCRIPT" | head -1 || true)"
		if [ -n "$FHS_ROOTFS" ] && [ -d "$FHS_ROOTFS" ]; then
			GLIBC_LIB="$(dirname "$(readlink -f "$FHS_ROOTFS/usr/lib64/Scrt1.o" 2>/dev/null || true)" 2>/dev/null || true)"
			if [ -n "$GLIBC_LIB" ] && [ -f "$GLIBC_LIB/crtn.o" ]; then
				GCCRT_DIR="$(gcc -print-libgcc-file-name 2>/dev/null | sed 's#/[^/]*$##' || true)"
				[ -n "$GCCRT_DIR" ] && [ -f "$GCCRT_DIR/crtbeginS.o" ] || GCCRT_DIR=""
				LIBGCCS_DIR="$(gcc -print-file-name=libgcc_s.so.1 2>/dev/null | sed 's#/[^/]*$##' || true)"
				[ -n "$LIBGCCS_DIR" ] && [ -f "$LIBGCCS_DIR/libgcc_s.so.1" ] || LIBGCCS_DIR=""
				if [ -n "$GCCRT_DIR" ] && [ -n "$LIBGCCS_DIR" ]; then
					SWIFTC="$SWIFTROOT/usr/bin/swiftc"
					SWIFT_MODE=raw
					SWIFT_LD="$FHS_ROOTFS/usr/lib64:$FHS_ROOTFS/lib64:/usr/lib64:/usr/lib"
				fi
			fi
		fi
	fi
fi
if [ "$SWIFT_MODE" = "raw" ]; then
	mkdir -p "$RUN/swift/shim"
	for f in Scrt1.o crti.o crtn.o; do ln -sf "$GLIBC_LIB/$f" "$RUN/swift/shim/$f"; done
	for f in crtbeginS.o crtendS.o; do ln -sf "$GCCRT_DIR/$f" "$RUN/swift/shim/$f"; done
fi
{
	printf 'wrapper %s\n' "$SWIFTC_WRAPPER"
	printf 'mode %s\n' "${SWIFT_MODE:-unavailable}"
	[ -n "$SWIFTC" ] && printf 'swiftc %s\n' "$SWIFTC"
	printf 'fhs-rootfs %s\n' "${FHS_ROOTFS:-}"
	printf 'glibc-lib %s\n' "${GLIBC_LIB:-}"
	printf 'gccrt %s\n' "${GCCRT_DIR:-}"
	printf 'libgccs %s\n' "${LIBGCCS_DIR:-}"
} >"$RUN/swift-toolchain.txt"
if [ "$SWIFT_MODE" != "wrapper" ]; then
	{
		printf 'the devShell swiftc wrapper sets up its FHS environment through\n'
		printf 'bubblewrap, which this container rejects (uid map permission);\n'
		printf 'resolved mode: %s\n' "${SWIFT_MODE:-unavailable}"
		sed 's/^/wrapper stderr: /' "$RUN/swiftc-wrapper-probe.stderr" 2>/dev/null
	} >>"$RUN/swift-toolchain.txt"
fi

# ------------------------------------------------------------------ identity
identity_step utc date -u +%Y-%m-%dT%H:%M:%SZ
printf 'worktree %s\nbranch %s\n' "$ROOT" "$(git branch --show-current 2>/dev/null || printf unknown)" >>"$RUN/identity.txt"
identity_step base git rev-parse HEAD
identity_step changed git status --porcelain
identity_step haxe-version haxe --version
identity_step bun-version bun --version
if [ -n "$SWIFTC" ]; then
	if [ "$SWIFT_MODE" = "raw" ]; then
		identity_step swiftc-version bash -c "LD_LIBRARY_PATH='$SWIFT_LD' timeout 60 $SWIFTC --version"
	else
		identity_step swiftc-version timeout 60 "$SWIFTC" --version
	fi
else
	identity_step swiftc-version bash -c 'printf "swift toolchain unusable in this environment\\n" >&2; exit 1'
fi
identity_step kotlinc-version kotlinc -version
identity_step rustc-version rustc --version
identity_step cargo-version cargo --version
identity_step dart-version dart --version
identity_step java-version java -version
identity_step resolved-boring-library haxelib path boring
identity_step authored-source-hashes sha256sum \
	tests/support/stage-check.sh \
	tests/haxe/alias-transfer-boundary/run.sh \
	tests/haxe/alias-transfer-boundary/oracle.hxml \
	tests/haxe/alias-transfer-boundary/expected.txt \
	tests/haxe/alias-transfer-boundary/gen/ts.hxml \
	tests/haxe/alias-transfer-boundary/gen/kotlin.hxml \
	tests/haxe/alias-transfer-boundary/gen/rust.hxml \
	tests/haxe/alias-transfer-boundary/gen/swift.hxml \
	tests/haxe/alias-transfer-boundary/gen/dart.hxml \
	tests/haxe/alias-transfer-boundary/atb/ContainerAliasOracle.hx \
	tests/haxe/alias-transfer-boundary/atb/NullableHolder.hx \
	tests/haxe/alias-transfer-boundary/native/main.js \
	tests/haxe/alias-transfer-boundary/native/Main.kt \
	tests/haxe/alias-transfer-boundary/native/harness.rs \
	tests/haxe/alias-transfer-boundary/native/native-main.swift \
	tests/haxe/alias-transfer-boundary/native/main.dart

expect_stage input-hashes-before
expect_stage input-hashes-after
if input_manifest "$RUN/input-hashes-before.txt"; then
	record input-hashes-before zero 0 input-manifest
else
	record input-hashes-before zero 1 input-manifest
	VERDICT=harness-defect
	IDENTITY_FAILURES=$((IDENTITY_FAILURES + 1))
fi
if [ "$IDENTITY_FAILURES" != "0" ]; then
	VERDICT=harness-defect
fi

# --------------------------------------------------------------- Haxe oracle
expect_stage haxe-oracle-compile
expect_stage haxe-oracle-run
expect_stage haxe-oracle-expect
st=0
stage haxe-oracle-compile data timeout 900 haxe tests/haxe/alias-transfer-boundary/oracle.hxml \
	-js "$RUN/oracle/oracle.js"
st=$?
if [ "$st" != "0" ]; then
	VERDICT=failed
fi
record_hash haxe-oracle-compile input-hxml tests/haxe/alias-transfer-boundary/oracle.hxml

st=0
stage haxe-oracle-run zero bash -c 'cd '"$RUN"'/oracle && timeout 120 bun oracle.js'
st=$?
if [ "$st" != "0" ]; then
	VERDICT=failed
else
	lines=$(shape_lines "$STAGES/haxe-oracle-run/stdout")
	if [ "$lines" != "5" ]; then
		printf 'oracle run emitted %s shape lines of 5\n' "$lines" >>"$RUN/shape-notes.txt"
		VERDICT=harness-defect
	fi
fi

st=0
stage haxe-oracle-expect identical diff -u tests/haxe/alias-transfer-boundary/expected.txt "$STAGES/haxe-oracle-run/stdout"
st=$?
if [ "$st" != "0" ]; then
	VERDICT=failed
fi

# ------------------------------------------------------------------ targets
# target_target <name>: per-stage pipeline with dependency tracking.
TARGET_FAILURES=0

run_target() {
	local target=$1
	local gen=$RUN/$target/gen
	local gen_tests=$RUN/$target/gen-tests
	local hxml=tests/haxe/alias-transfer-boundary/gen/$target.hxml
	local dir=$STAGES/gen-$target
	record_hash gen-$target input-hxml "$hxml"

	st=0
	stage gen-$target data timeout 900 haxe "$hxml" \
		-D "$target-output=$gen" \
		-D "$target-test-output=$gen_tests"
	st=$?
	if [ "$st" != "0" ]; then
		VERDICT=failed
		TARGET_FAILURES=$((TARGET_FAILURES + 1))
		not_reached gen-$target "$st" compile-$target run-$target compare-$target
		return
	fi
	tree_manifest "$gen" "$RUN/$target-tree.sha256"

	case "$target" in
	ts)
		stage compile-ts data bash -c "cd $gen && cp $HERE/native/main.js alias-transfer-run.js && sha256sum alias-transfer-run.js >harness.sha256 && timeout 300 bun build alias-transfer-run.js --outfile=run-bundle.js"
		;;
	kotlin)
		stage compile-kotlin data bash -c "cd $gen && cp $HERE/native/Main.kt AliasTransferRun.kt && sha256sum AliasTransferRun.kt >harness.sha256 && timeout 1800 kotlinc AliasTransferRun.kt \$(find atb runtime std -name '*.kt' -not -path '*runtime/test*') -include-runtime -d run.jar"
		;;
	rust)
		stage compile-rust data bash -c "cd $gen && mkdir -p src && cp $HERE/native/harness.rs src/main.rs && sha256sum src/main.rs >harness.sha256 && timeout 1800 cargo build --offline"
		;;
	swift)
		if [ -z "$SWIFTC" ]; then
			printf 'swift: toolchain unusable in this environment; recorded as a target toolchain limitation\n' >>"$RUN/toolchain-limits.txt"
			not_reached swiftc-missing 1 compile-swift run-swift compare-swift
			return
		fi
		if [ "$SWIFT_MODE" = "raw" ]; then
			stage compile-swift data bash -c "cd $gen && cp $HERE/native/native-main.swift native-main.swift && sha256sum native-main.swift >harness.sha256 && cd $RUN/swift/shim && LD_LIBRARY_PATH='$SWIFT_LD' timeout 1800 $SWIFTC -o $gen/run-bin $gen/Runtime.swift \$(find $gen/std $gen/atb -name '*.swift') $gen/native-main.swift -Xcc -I$FHS_ROOTFS/usr/include -L$FHS_ROOTFS/usr/lib64 -L$GCCRT_DIR -L$LIBGCCS_DIR -L$GLIBC_LIB"
		else
			stage compile-swift data bash -c "cd $gen && cp $HERE/native/native-main.swift native-main.swift && sha256sum native-main.swift >harness.sha256 && timeout 1800 $SWIFTC -o run-bin Runtime.swift \$(find std atb -name '*.swift') native-main.swift"
		fi
		;;
	dart)
		stage compile-dart data bash -c "cd $gen && mkdir -p lib/atb && cp $HERE/native/main.dart lib/atb/zz_run.dart && sha256sum lib/atb/zz_run.dart >harness.sha256 && timeout 900 dart pub get && timeout 1800 dart compile exe lib/atb/zz_run.dart -o run.exe"
		;;
	esac
	st=$?
	if [ "$st" != "0" ]; then
		VERDICT=failed
		TARGET_FAILURES=$((TARGET_FAILURES + 1))
		not_reached compile-$target "$st" run-$target compare-$target
		return
	fi

	case "$target" in
	ts)
		stage run-ts zero bash -c "cd $gen && timeout 120 bun run-bundle.js"
		;;
	kotlin)
		stage run-kotlin zero bash -c "timeout 300 java -cp $gen/run.jar AliasTransferRunKt"
		;;
	rust)
		stage run-rust zero bash -c "cd $gen && timeout 120 ./target/debug/generated"
		;;
	swift)
		stage run-swift zero bash -c "cd $gen && timeout 300 ./run-bin"
		;;
	dart)
		stage run-dart zero bash -c "cd $gen && timeout 300 ./run.exe"
		;;
	esac
	st=$?
	if [ "$st" != "0" ]; then
		VERDICT=failed
		TARGET_FAILURES=$((TARGET_FAILURES + 1))
		not_reached run-$target "$st" compare-$target
		return
	fi
	lines=$(shape_lines "$STAGES/run-$target/stdout")
	if [ "$lines" != "5" ]; then
		printf '%s run emitted %s shape lines of 5\n' "$target" "$lines" >>"$RUN/shape-notes.txt"
		VERDICT=harness-defect
		return
	fi

	compare compare-$target "$STAGES/run-$target/stdout" tests/haxe/alias-transfer-boundary/expected.txt
}

for target in ts kotlin rust swift dart; do
	expect_stage gen-$target
	expect_stage compile-$target
	expect_stage run-$target
	expect_stage compare-$target
	run_target "$target"
done

# ------------------------------------------------------------ closing checks
if input_manifest "$RUN/input-hashes-after.txt" \
	&& cmp -s "$RUN/input-hashes-before.txt" "$RUN/input-hashes-after.txt"; then
	record input-hashes-after zero 0 input-manifest
else
	record input-hashes-after zero 1 input-manifest
	VERDICT=harness-defect
fi

stage_check "$STATUS" "$EXPECTED" "$RUN/membership-findings.txt"
member=$?
if [ "$member" = "0" ]; then
	record membership zero 0 stage-check
else
	record membership zero 1 stage-check
	VERDICT=harness-defect
fi

# ------------------------------------------------------------------ summary
if [ "$DIFFERENCES" != "0" ] && [ "$VERDICT" = "success" ]; then
	VERDICT=observed-differences
fi
{
	printf 'run directory %s\n' "$RUN"
	printf 'verdict %s\n' "$VERDICT"
	printf 'differences %s\n' "$DIFFERENCES"
	printf 'not-reached %s\n' "$UNREACHED"
	printf 'target-failures %s\n' "$TARGET_FAILURES"
	printf '\n'
	cat "$STATUS"
} >"$RUN/summary.txt"
cat "$RUN/summary.txt"
