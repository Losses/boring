#!/usr/bin/env bash
# Durable staged evidence runner for the charcodeat observation fixture
# (board t-mum1qvjl-3bss: string-boundary substring and non-nullable
# charCodeAt source domain).
#
# One invocation allocates one fresh attempt directory under
# dc-warn/out/charcodeat/ and never rewrites an earlier one. Stages run
# inside the invoking pinned `nix develop` environment and record
# shell-quoted argv, cwd, separated streams, and exit status under
# $RUN/stages/<id>/ (identity stages under $RUN/identity/<label>/).
#
# Observation semantics (this is a measurement task, not a pass/fail
# gate):
#   - The six source-acceptance probes are compiled standalone against
#     the plain Haxe 4.3.7 toolchain. All six shapes are EXPECTED TO BE
#     SOURCE-ACCEPTED and to run: the pinned 4.3.7 typer performs no
#     strict nullability enforcement (established empirically, including
#     `var c:Int = null`), so the PCodeint shape (out-of-range
#     charCodeAt assigned to a non-nullable Int) is accepted too, and
#     its raw evidence is the ABSENCE of a diagnostic (exit 0, empty
#     stderr). That absence is itself the observation that settles the
#     source domain: the non-nullable Int context is NOT source-rejected.
#     The same PCodeint shape is re-probed through the full generation
#     pipeline (-lib reflaxe -lib boring + Intercept) to record that
#     the pipeline accepts it as well.
#   - The Haxe JS oracle (boring pipeline) anchors the expected values;
#     a broken oracle anchor is the only source-level failure.
#   - Per target (ts kotlin rust swift dart): gen, lowering excerpt,
#     native compile, native run, compare. A generation or native
#     compile failure, a native crash (trap, exception, platform type
#     failure), and a compare difference are all RECORDED OBSERVATIONS
#     with raw streams; the dependent stage is recorded not-reached.
#     Only the oracle anchor breaking, an accepted shape being
#     source-rejected, or the codeint shape being pipeline-rejected
#     marks the run failed.
#   - Built binaries that must be executed (rust target, swift binary)
#     are placed under $TMP_ROOT (the fuse evidence mount does not keep
#     an executable bit); the generated trees themselves stay in the
#     evidence directory and are hashed.
#
# Verdict vocabulary:
#   success                every expectation held: all six shapes
#                           source-accepted, oracle anchor intact, all
#                           five targets reproduced the authored lines
#   observed-differences   every source expectation held and at least
#                           one target stage recorded a pipeline
#                           failure, a crash, or a value difference
#   failed                 the oracle anchor broke, an accepted shape
#                           was source-rejected, or the codeint shape
#                           was pipeline-rejected
#   harness-defect         setup, identity, hashing, or membership
#                           failure
#
# Only failed and harness-defect exit nonzero; the others are retained
# evidence. Run through the boring devShell:
#   XDG_CACHE_HOME=/tmp/charcodeat-nix-cache nix develop -c bash tests/haxe/charcodeat/run.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/../../support/stage-check.sh"
ROOT="$(cd "$HERE/../../.." && pwd)"
cd "$ROOT" || exit 1
if [ "${IN_NIX_SHELL:-}" = "" ]; then
	printf 'run this runner through: nix develop -c bash tests/haxe/charcodeat/run.sh\n'
	exit 1
fi
if [ ! -f AGENT.md ]; then
	printf 'AGENT.md absent at %s; wrong worktree\n' "$ROOT"
	exit 1
fi
for f in tests/support/stage-check.sh \
	tests/haxe/charcodeat/oracle.hxml \
	tests/haxe/charcodeat/expected.txt \
	tests/haxe/charcodeat/charcodeat/CharCodeAtOracle.hx \
	tests/haxe/charcodeat/probes/PSubrev.hx \
	tests/haxe/charcodeat/probes/PSubhigh.hx \
	tests/haxe/charcodeat/probes/PSubneg.hx \
	tests/haxe/charcodeat/probes/PCodenull.hx \
	tests/haxe/charcodeat/probes/PCodeneg.hx \
	tests/haxe/charcodeat/probes/PCodeint.hx \
	tests/haxe/charcodeat/native/main.js \
	tests/haxe/charcodeat/native/Main.kt \
	tests/haxe/charcodeat/native/harness.rs \
	tests/haxe/charcodeat/native/native-main.swift \
	tests/haxe/charcodeat/native/main.dart; do
	[ -f "$f" ] || { printf 'fixture input missing: %s\n' "$f"; exit 1; }
done
for t in ts kotlin rust swift dart; do
	[ -f "tests/haxe/charcodeat/gen/$t.hxml" ] || {
		printf 'gen hxml missing for %s\n' "$t"
		exit 1
	}
done

# ------------------------------------------------------------- evidence
# Evidence root is the workspace dc-warn/out/charcodeat (the worktree
# lives at dc-warn/worktrees/charcodeat, so dc-warn is two levels up).
mkdir -p "$ROOT/../../out/charcodeat" || { printf 'evidence root creation failed\n'; exit 1; }
EVIDENCE_ROOT="$(cd "$ROOT/../../out/charcodeat" && pwd)"
ATT_ID="att-$(date -u +%Y%m%dT%H%M%SZ)"
RUN="$EVIDENCE_ROOT/$ATT_ID"
n=2
while [ -e "$RUN" ]; do
	RUN="$EVIDENCE_ROOT/${ATT_ID}-${n}"
	n=$((n + 1))
done
mkdir -p "$RUN/stages" || { printf 'run directory allocation failed\n'; exit 1; }
RUN="$(cd "$RUN" && pwd)"

# Built binaries that must be executed live outside the fuse evidence
# mount (no executable bit there).
TMP_ROOT="/tmp/charcodeat/$ATT_ID"
mkdir -p "$TMP_ROOT/swift" "$TMP_ROOT/rust-target" || { printf 'tmp root allocation failed\n'; exit 1; }

# Stage input/output directories the producers do not create themselves.
mkdir -p "$RUN/probes" "$RUN/oracle"
for t in ts kotlin rust swift dart; do
	mkdir -p "$RUN/$t/gen" "$RUN/$t/gen-tests"
done

EXPECT="$RUN/expected-stages.txt"
: >"$EXPECT"
STAGES="$RUN/stages"

log() {
	printf '%s\n' "$1"
}

TAB="$(printf '\t')"
STATUS="$RUN/status.tsv"
printf 'stage%sexpected%sobserved%sproducer\n' "$TAB" "$TAB" "$TAB" >"$STATUS"
VERDICT=success
DIFFERENCES=0
OBSERVATIONS=0
UNREACHED=0
IDENTITY_FAILURES=0

expect_stage() {
	printf '%s\n' "$1" >>"$EXPECT"
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

# shape_lines <file>: count the labeled shape lines (6 expected).
shape_lines() {
	grep -c '^subRev=\|^subHigh=\|^subNeg=\|^codeNull=\|^codeNeg=\|^codeInt=' "$1" 2>/dev/null || true
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
		find packages/compiler tests/haxe/charcodeat tests/support -type f -print0 \
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

# tree_manifest <generated tree> <manifest output>: digests every
# generated file; a pipeline failure propagates.
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
		printf '%s\n' "$(cat "$manifest.err" 2>/dev/null)" >>"$RUN/hash-failures.txt"
		VERDICT=harness-defect
		return 1
	fi
	return 0
}

# compare <stage> <run stdout file> <expected file>: a matching diff
# exits 0 (identical); a value difference exits 1 and is a recorded
# observation.
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
		OBSERVATIONS=$((OBSERVATIONS + 1))
	fi
}

# -------------------------------------------- Swift toolchain resolution
# The devShell `swiftc` is a wrapper that sets up its FHS environment
# through bubblewrap; this container rejects the bwrap uid map for an
# unprivileged user, so the wrapper fails. When the wrapper cannot run,
# fall back to the raw store toolchain with the FHS rootfs libraries and
# the CRT objects COPIED (the evidence mount keeps no symlinks) into the
# link working directory (ld.gold opens the bare-name CRT inputs
# relative to the CWD).
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
	mkdir -p "$TMP_ROOT/swift-shim"
	for f in Scrt1.o crti.o crtn.o; do cp -f "$GLIBC_LIB/$f" "$TMP_ROOT/swift-shim/$f"; done
	for f in crtbeginS.o crtendS.o; do cp -f "$GCCRT_DIR/$f" "$TMP_ROOT/swift-shim/$f"; done
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
printf 'worktree %s\nbranch %s\nrevision %s\n' "$ROOT" "$(git branch --show-current 2>/dev/null || printf unknown)" "$(git rev-parse HEAD 2>/dev/null || printf unknown)" >>"$RUN/identity.txt"
printf 'evidence root %s\ntmp root %s\n' "$EVIDENCE_ROOT" "$TMP_ROOT" >>"$RUN/identity.txt"
identity_step base git rev-parse HEAD
identity_step changed git status --porcelain --untracked-files=no
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
	tests/haxe/charcodeat/run.sh \
	tests/haxe/charcodeat/oracle.hxml \
	tests/haxe/charcodeat/expected.txt \
	tests/haxe/charcodeat/gen/ts.hxml \
	tests/haxe/charcodeat/gen/kotlin.hxml \
	tests/haxe/charcodeat/gen/rust.hxml \
	tests/haxe/charcodeat/gen/swift.hxml \
	tests/haxe/charcodeat/gen/dart.hxml \
	tests/haxe/charcodeat/charcodeat/CharCodeAtOracle.hx \
	tests/haxe/charcodeat/probes/PSubrev.hx \
	tests/haxe/charcodeat/probes/PSubhigh.hx \
	tests/haxe/charcodeat/probes/PSubneg.hx \
	tests/haxe/charcodeat/probes/PCodenull.hx \
	tests/haxe/charcodeat/probes/PCodeneg.hx \
	tests/haxe/charcodeat/probes/PCodeint.hx \
	tests/haxe/charcodeat/native/main.js \
	tests/haxe/charcodeat/native/Main.kt \
	tests/haxe/charcodeat/native/harness.rs \
	tests/haxe/charcodeat/native/native-main.swift \
	tests/haxe/charcodeat/native/main.dart

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

# ------------------------------------------------------- source-acceptance
# Six standalone probes against the plain Haxe 4.3.7 toolchain. All
# six shapes are expected to be source-accepted (the pinned 4.3.7
# typer performs no strict nullability enforcement), so each probe
# must compile (exit 0, and for the codeint shape: empty stderr) and
# run.
ACCEPTED_PROBES="subrev subhigh subneg codenull codeneg codeint"
for p in $ACCEPTED_PROBES; do
	cls="P$(printf '%s' "${p:0:1}" | tr a-z A-Z)${p:1}"
	expect_stage "probe-$p-compile"
	expect_stage "probe-$p-run"
	st=0
	stage "probe-$p-compile" zero timeout 300 haxe -main "$cls" -cp samples -cp tests/haxe/charcodeat/probes -js "$RUN/probes/$p.js"
	st=$?
	if [ "$st" != "0" ]; then
		printf 'accepted shape %s was source-rejected; raw diagnostic in stages/probe-%s-compile\n' "$p" "$p" >>"$RUN/source-notes.txt"
		not_reached "probe-$p-compile" "$st" "probe-$p-run"
		VERDICT=failed
		continue
	fi
	record_hash "probe-$p-compile" input-hx "tests/haxe/charcodeat/probes/${cls}.hx"
	st=0
	stage "probe-$p-run" zero bash -c "cd $RUN/probes && timeout 60 bun $p.js"
	st=$?
	if [ "$st" != "0" ]; then
		printf 'accepted shape %s compiled but did not run cleanly\n' "$p" >>"$RUN/source-notes.txt"
		VERDICT=failed
	fi
done

# The plain-toolchain PCodeint probe is covered by the accepted-probe
# loop above (compile zero + run zero). Its raw evidence -- an empty
# stderr with exit 0 -- is the source-domain observation: the
# non-nullable Int context is source-accepted by the pinned typer.
# The pipeline-level re-probe records the same acceptance under the
# full generation pipeline.
expect_stage "probe-codeint-boring-compile"
st=0
stage "probe-codeint-boring-compile" zero timeout 900 haxe \
	-lib reflaxe -lib boring -cp packages/compiler -cp samples \
	-cp tests/haxe/charcodeat -cp tests/haxe/charcodeat/probes \
	--macro "Intercept.run(['samples', 'tests/haxe/charcodeat', 'tests/haxe/charcodeat/probes'])" \
	-main PCodeint -js "$RUN/probes/codeint-boring.js"
st=$?
if [ "$st" != "0" ]; then
	printf 'codeint shape was pipeline-REJECTED (unexpected for the pinned toolchain); raw diagnostic in stages/probe-codeint-boring-compile\n' >>"$RUN/source-notes.txt"
	VERDICT=failed
fi

# --------------------------------------------------------------- Haxe oracle
expect_stage haxe-oracle-compile
expect_stage haxe-oracle-run
expect_stage haxe-oracle-expect
st=0
stage haxe-oracle-compile data timeout 900 haxe tests/haxe/charcodeat/oracle.hxml \
	-js "$RUN/oracle/oracle.js"
st=$?
if [ "$st" != "0" ]; then
	VERDICT=failed
fi
record_hash haxe-oracle-compile input-hxml tests/haxe/charcodeat/oracle.hxml

st=0
stage haxe-oracle-run zero bash -c 'cd '"$RUN"'/oracle && timeout 120 bun oracle.js'
st=$?
if [ "$st" != "0" ]; then
	VERDICT=failed
else
	lines=$(shape_lines "$STAGES/haxe-oracle-run/stdout")
	if [ "$lines" != "6" ]; then
		printf 'oracle run emitted %s shape lines of 6\n' "$lines" >>"$RUN/shape-notes.txt"
		VERDICT=failed
	fi
fi

st=0
stage haxe-oracle-expect identical diff -u tests/haxe/charcodeat/expected.txt "$STAGES/haxe-oracle-run/stdout"
st=$?
if [ "$st" != "0" ]; then
	VERDICT=failed
fi

# ------------------------------------------------------------------ targets
run_target() {
	local target=$1
	local gen=$RUN/$target/gen
	local gen_tests=$RUN/$target/gen-tests
	local hxml=tests/haxe/charcodeat/gen/$target.hxml
	record_hash "gen-$target" input-hxml "$hxml"

	st=0
	stage "gen-$target" data timeout 900 haxe "$hxml" \
		-D "$target-output=$gen" \
		-D "$target-test-output=$gen_tests"
	st=$?
	if [ "$st" != "0" ]; then
		OBSERVATIONS=$((OBSERVATIONS + 1))
		printf '%s generation failed; raw diagnostic in stages/gen-%s\n' "$target" "$target" >>"$RUN/target-notes.txt"
		not_reached "gen-$target" "$st" "lowering-$target" "compile-$target" "run-$target" "compare-$target"
		return
	fi
	tree_manifest "$gen" "$RUN/$target-tree.sha256"

	# The emitted call sites for substring / charCodeAt in the fixture
	# package: evidence for the lowering each target actually carries.
	# The fixture package dir is charcodeat on every target; the dart
	# tree nests it under lib/.
	case "$target" in
	dart) pkgdir="$gen/lib/charcodeat" ;;
	*) pkgdir="$gen/charcodeat" ;;
	esac
	stage "lowering-$target" data bash -c "find $pkgdir -type f -print0 | xargs -0 grep -n -E 'substring|charCodeAt|char_code_at|codeUnitAt|unit_at|substringUnits|substrUnits|unitAtOptional|\.code' 2>/dev/null | head -120"

	case "$target" in
	ts)
		stage "compile-$target" data bash -c "cd $gen && cp $HERE/native/main.js charcodeat-run.js && sha256sum charcodeat-run.js >harness.sha256 && timeout 300 bun build charcodeat-run.js --outfile=run-bundle.js"
		;;
	kotlin)
		stage "compile-$target" data bash -c "cd $gen && cp $HERE/native/Main.kt CharCodeAtRun.kt && sha256sum CharCodeAtRun.kt >harness.sha256 && timeout 1800 kotlinc CharCodeAtRun.kt \$(find charcodeat runtime std -name '*.kt' -not -path '*runtime/test*') -include-runtime -d run.jar"
		;;
	rust)
		stage "compile-$target" data bash -c "cd $gen && mkdir -p src && cp $HERE/native/harness.rs src/main.rs && sha256sum src/main.rs >harness.sha256 && timeout 1800 cargo build --offline --target-dir $TMP_ROOT/rust-target"
		;;
	swift)
		if [ -z "$SWIFTC" ]; then
			printf 'swift: toolchain unusable in this environment; recorded as a target toolchain limitation\n' >>"$RUN/toolchain-limits.txt"
			OBSERVATIONS=$((OBSERVATIONS + 1))
			not_reached "swift-toolchain-unavailable" 1 "lowering-$target" "compile-$target" "run-$target" "compare-$target"
			return
		fi
		if [ "$SWIFT_MODE" = "raw" ]; then
			stage "compile-$target" data bash -c "cd $gen && cp $HERE/native/native-main.swift native-main.swift && sha256sum native-main.swift >harness.sha256 && cd $TMP_ROOT/swift-shim && LD_LIBRARY_PATH='$SWIFT_LD' timeout 1800 $SWIFTC -o $TMP_ROOT/swift/run-bin \$(find $gen -maxdepth 1 -name '*.swift' -type f ! -name 'native-main.swift' ! -name 'Package.swift') \$(find $gen/std $gen/charcodeat -name '*.swift') $gen/native-main.swift -Xcc -I$FHS_ROOTFS/usr/include -L$FHS_ROOTFS/usr/lib64 -L$GCCRT_DIR -L$LIBGCCS_DIR -L$GLIBC_LIB"
		else
			stage "compile-$target" data bash -c "cd $gen && cp $HERE/native/native-main.swift native-main.swift && sha256sum native-main.swift >harness.sha256 && timeout 1800 $SWIFTC -o $TMP_ROOT/swift/run-bin \$(find . -maxdepth 1 -name '*.swift' -type f ! -name 'native-main.swift' ! -name 'Package.swift') \$(find std charcodeat -name '*.swift') native-main.swift"
		fi
		;;
	dart)
		stage "compile-$target" data bash -c "cd $gen && mkdir -p lib/charcodeat && cp $HERE/native/main.dart lib/charcodeat/zz_run.dart && sha256sum lib/charcodeat/zz_run.dart >harness.sha256 && timeout 900 dart pub get"
		;;
	esac
	st=$?
	if [ "$st" != "0" ]; then
		OBSERVATIONS=$((OBSERVATIONS + 1))
		printf '%s native compile failed; raw diagnostic in stages/compile-%s\n' "$target" "$target" >>"$RUN/target-notes.txt"
		not_reached "compile-$target" "$st" "run-$target" "compare-$target"
		return
	fi

	case "$target" in
	ts)
		stage "run-$target" zero bash -c "cd $gen && timeout 120 bun run-bundle.js"
		;;
	kotlin)
		stage "run-$target" zero bash -c "timeout 300 java -cp $gen/run.jar CharCodeAtRunKt"
		;;
	rust)
		stage "run-$target" zero bash -c "cd $TMP_ROOT/rust-target/debug && timeout 120 ./generated"
		;;
	swift)
		stage "run-$target" zero bash -c "cd $TMP_ROOT/swift && timeout 300 ./run-bin"
		;;
	dart)
		stage "run-$target" zero bash -c "cd $gen && timeout 600 dart run lib/charcodeat/zz_run.dart"
		;;
	esac
	st=$?
	if [ "$st" != "0" ]; then
		OBSERVATIONS=$((OBSERVATIONS + 1))
		printf '%s native run exited %s (crash/exception/trap observation); raw streams in stages/run-%s\n' "$target" "$st" "$target" >>"$RUN/target-notes.txt"
		not_reached "run-$target" "$st" "compare-$target"
		return
	fi
	lines=$(shape_lines "$STAGES/run-$target/stdout")
	if [ "$lines" != "6" ]; then
		printf '%s run emitted %s shape lines of 6\n' "$target" "$lines" >>"$RUN/shape-notes.txt"
		OBSERVATIONS=$((OBSERVATIONS + 1))
		not_reached "run-$target" "$lines" "compare-$target"
		return
	fi

	compare "compare-$target" "$STAGES/run-$target/stdout" tests/haxe/charcodeat/expected.txt
}

for target in ts kotlin rust swift dart; do
	expect_stage "gen-$target"
	expect_stage "lowering-$target"
	expect_stage "compile-$target"
	expect_stage "run-$target"
	expect_stage "compare-$target"
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

stage_check "$STATUS" "$EXPECT" "$RUN/membership-findings.txt"
member=$?
if [ "$member" = "0" ]; then
	record membership zero 0 stage-check
else
	record membership zero 1 stage-check
	VERDICT=harness-defect
fi

# ------------------------------------------------------------------ summary
if [ "$VERDICT" = "success" ] && { [ "$DIFFERENCES" != "0" ] || [ "$OBSERVATIONS" != "0" ]; }; then
	VERDICT=observed-differences
fi
{
	printf 'run directory %s\n' "$RUN"
	printf 'evidence root %s\n' "$EVIDENCE_ROOT"
	printf 'attempt id %s\n' "$ATT_ID"
	printf 'tmp root %s\n' "$TMP_ROOT"
	printf 'verdict %s\n' "$VERDICT"
	printf 'differences %s\n' "$DIFFERENCES"
	printf 'observations %s\n' "$OBSERVATIONS"
	printf 'not-reached %s\n' "$UNREACHED"
	printf '\n'
	cat "$STATUS"
} >"$RUN/summary.txt"
cat "$RUN/summary.txt"

case "$VERDICT" in
	success|observed-differences) exit 0 ;;
	*) exit 1 ;;
esac
