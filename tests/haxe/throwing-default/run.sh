#!/usr/bin/env bash
# Staged evidence runner for the throwing-default observation fixture
# (board t-mum0wts5-jh3m: failure domain of throwable calls in default arguments).
#
# One invocation allocates one fresh attempt directory under
# out/throwing-default/ and never rewrites an earlier one. Stages run
# inside the invoking pinned `nix develop` environment and record
# shell-quoted argv, cwd, separated streams, and exit status under
# $RUN/stages/<id>/.
#
# Observation semantics (this is a measurement task; the target
# stages record readings; no target reading itself fails the run):
#   - Admission comes first (B/D cross-review requirement): the
#     default-position probe must be rejected with the V16 named error
#     and the coalescing-throwing probe must be source-accepted. Either
#     flipping marks the run failed: the task premise no longer holds.
#   - The Haxe JS oracle (plain Haxe, no Intercept) anchors the
#     stage-1 semantics; a broken oracle anchor is a failure.
#   - Rust and Swift each record: generation, the generated fixture
#     file (the failure-domain evidence), a tree manifest, native
#     compile, native run, compare. Authored expectations pinned at
#     base e8648488: Swift reproduces the oracle lines; Rust panics
#     (exit 101) at the unwrap_or_else closure on the throwing
#     omission shape and truncates its output -- the failure leaves
#     the declared Result domain, so the lowered try region (a Result
#     match) cannot absorb it. A target stage deviating from its
#     authored expectation is an observed-difference, retained as
#     evidence.
#   - Built binaries are placed under /tmp (kept out of the evidence
#     tree); the generated trees themselves stay in the evidence
#     directory and are hashed.
#
# Verdict vocabulary:
#   success                every expectation held: admission as read,
#                           oracle anchor intact, Swift matched the
#                           oracle, Rust panicked as authored
#   observed-differences   admission and oracle held and at least one
#                           target stage deviated from its authored
#                           expectation
#   failed                 the admission flipped or the oracle anchor
#                           broke
#   harness-defect         setup, identity, or hashing failure
#
# Only failed and harness-defect exit nonzero; the others are retained
# evidence. Run through the boring devShell:
#   nix develop -c bash tests/haxe/throwing-default/run.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
cd "$ROOT" || exit 1
if [ "${IN_NIX_SHELL:-}" = "" ]; then
	printf 'run.sh: run inside the pinned nix develop environment\n' >&2
	exit 1
fi
if [ ! -f AGENT.md ] || [ ! -f flake.nix ]; then
	printf 'run.sh: worktree root misresolved: %s\n' "$ROOT" >&2
	exit 1
fi
for f in tests/haxe/throwing-default/oracle.hxml \
	tests/haxe/throwing-default/expected.txt \
	tests/haxe/throwing-default/gen/rust.hxml \
	tests/haxe/throwing-default/gen/swift.hxml \
	tests/haxe/throwing-default/throwdef/ThrowingDefaultOps.hx \
	tests/haxe/throwing-default/probes/PDefaultPosition.hx \
	tests/haxe/throwing-default/probes/PCoalescingThrowing.hx \
	tests/haxe/throwing-default/native/harness.rs \
	tests/haxe/throwing-default/native/native-main.swift; do
	[ -f "$f" ] || { printf 'fixture input missing: %s\n' "$f"; exit 1; }
done

# ------------------------------------------------------------- evidence
mkdir -p out/throwing-default || { printf 'evidence root creation failed\n' >&2; exit 1; }
EVIDENCE_ROOT="$(cd out/throwing-default && pwd)"
ATT_ID="att-$(date -u +%Y%m%dT%H%M%SZ)"
RUN="$EVIDENCE_ROOT/$ATT_ID"
n=2
while [ -e "$RUN" ]; do
	RUN="$EVIDENCE_ROOT/$ATT_ID-$n"
	n=$((n + 1))
done
mkdir -p "$RUN/stages" || { printf 'run directory allocation failed\n' >&2; exit 1; }
RUN="$(cd "$RUN" && pwd)"

# Built binaries live outside the evidence tree.
TMP_ROOT="/tmp/throwing-default/$ATT_ID"
mkdir -p "$TMP_ROOT/swift" "$TMP_ROOT/rust-target" || { printf 'tmp root allocation failed\n' >&2; exit 1; }

EXPECT="$RUN/expected-stages.txt"
: >"$EXPECT"
STAGES="$RUN/stages"

log() {
	printf '%s\n' "$1"
}
TAB="$(printf '\t')"
STATUS="$RUN/status.tsv"
printf 'stage%sexpected%sobserved\n' "$TAB" "$TAB" >"$STATUS"
VERDICT=success
DIFFERENCES=0
OBSERVATIONS=0
UNREACHED=0
IDENTITY_FAILURES=0

expect_stage() {
	printf '%s\n' "$1" >>"$EXPECT"
}

record() {
	printf '%s%s%s%s%s\n' "$1" "$TAB" "$2" "$TAB" "$3" >>"$STATUS"
}

not_reached() {
	local producer=$1 observed=$2
	shift 2
	for name in "$@"; do
		record "$name" "not-reached" "producer-$producer-status-$observed"
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
	record "$name" "$expected" "$observed"
	return "$observed"
}

identity_step() {
	local label=$1
	shift
	local dir="$STAGES/identity-$label"
	mkdir -p "$dir"
	"$@" >"$dir/stdout" 2>"$dir/stderr"
	local observed=$?
	printf '%s\n' "$observed" >"$dir/status"
	if [ "$observed" != "0" ]; then
		IDENTITY_FAILURES=$((IDENTITY_FAILURES + 1))
	fi
}

# tree_manifest <generated tree> <manifest output>: digests every
# generated file; a pipeline failure propagates.
tree_manifest() {
	if [ ! -d "$1" ]; then
		return 1
	fi
	( cd "$1" && find . -type f -print0 | sort -z | xargs -0 sha256sum ) >"$2"
}

# -------------------------------------------- Swift toolchain resolution
# The devShell `swiftc` is a wrapper that sets up its FHS environment
# through bubblewrap; environments that reject the bwrap uid map fall
# back to the raw store toolchain with the FHS rootfs libraries and the
# CRT objects COPIED into the link working directory (ld.gold opens the
# bare-name CRT inputs relative to the CWD).
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
		printf 'bubblewrap, which this environment rejects; resolved mode: %s\n' "${SWIFT_MODE:-unavailable}"
		sed 's/^/wrapper stderr: /' "$RUN/swiftc-wrapper-probe.stderr" 2>/dev/null
	} >>"$RUN/swift-toolchain.txt"
fi

# ------------------------------------------------------------------ identity
identity_step utc date -u +%Y-%m-%dT%H:%M:%SZ
printf 'worktree %s\nbranch %s\nrevision %s\n' "$ROOT" "$(git branch --show-current 2>/dev/null || printf unknown)" "$(git rev-parse HEAD 2>/dev/null || printf unknown)" >"$RUN/identity.txt"
printf 'evidence root %s\ntmp root %s\n' "$RUN" "$TMP_ROOT" >>"$RUN/identity.txt"
identity_step base git rev-parse HEAD
identity_step changed git status --porcelain --untracked-files=no
identity_step haxe-version haxe --version
identity_step bun-version bun --version
identity_step rustc-version rustc --version
identity_step cargo-version cargo --version
if [ -n "$SWIFTC" ]; then
	if [ "$SWIFT_MODE" = "raw" ]; then
		identity_step swiftc-version bash -c "LD_LIBRARY_PATH='$SWIFT_LD' timeout 60 $SWIFTC --version"
	else
		identity_step swiftc-version timeout 60 "$SWIFTC" --version
	fi
else
	identity_step swiftc-version bash -c 'printf "swift toolchain unusable in this environment\n" >&2; exit 1'
fi
identity_step resolved-boring-library haxelib path boring
identity_step authored-source-hashes sha256sum \
	tests/haxe/throwing-default/run.sh \
	tests/haxe/throwing-default/oracle.hxml \
	tests/haxe/throwing-default/expected.txt \
	tests/haxe/throwing-default/gen/rust.hxml \
	tests/haxe/throwing-default/gen/swift.hxml \
	tests/haxe/throwing-default/throwdef/ThrowingDefaultOps.hx \
	tests/haxe/throwing-default/probes/PDefaultPosition.hx \
	tests/haxe/throwing-default/probes/PCoalescingThrowing.hx \
	tests/haxe/throwing-default/native/harness.rs \
	tests/haxe/throwing-default/native/native-main.swift
if [ "$IDENTITY_FAILURES" != "0" ]; then
	VERDICT=harness-defect
fi

# ------------------------------------------------------- admission control
# Probe A: a call in default position must be rejected with the V16
# named error. Acceptance flips the task premise (failed); a different
# rejection text is an observed difference.
expect_stage admit-default-position
mkdir -p "$RUN/probes"
stage admit-default-position 1 haxe -lib reflaxe -lib boring \
	-cp packages/compiler -cp samples -cp tests/haxe/throwing-default/probes \
	-main PDefaultPosition -js "$RUN/probes/default-position.js" \
	--macro "Intercept.run(['tests/haxe/throwing-default/probes'])"
admitA=$?
if [ "$admitA" = "0" ]; then
	VERDICT=failed
	log 'admission A flipped: default-position call was accepted'
elif ! grep -q 'default argument values accept compile-time constants only' \
	"$STAGES/admit-default-position/stderr" "$STAGES/admit-default-position/stdout" 2>/dev/null; then
	DIFFERENCES=$((DIFFERENCES + 1))
	log 'admission A rejected without the V16 named error; recorded as a difference'
fi

# Probe B: a throwing call inside a coalescing default must be
# source-accepted. Rejection flips the task premise.
expect_stage admit-coalescing-throwing
stage admit-coalescing-throwing 0 haxe -lib reflaxe -lib boring \
	-cp packages/compiler -cp samples -cp tests/haxe/throwing-default/probes \
	-main PCoalescingThrowing -js "$RUN/probes/coalescing-throwing.js" \
	--macro "Intercept.run(['tests/haxe/throwing-default/probes'])"
admitB=$?
if [ "$admitB" != "0" ]; then
	VERDICT=failed
	log 'admission B flipped: coalescing-throwing source was rejected'
fi

# --------------------------------------------------------------- Haxe oracle
expect_stage haxe-oracle-compile
expect_stage haxe-oracle-run
expect_stage haxe-oracle-expect
mkdir -p "$RUN/oracle"
stage haxe-oracle-compile 0 haxe tests/haxe/throwing-default/oracle.hxml \
	-js "$RUN/oracle/oracle.js"
if [ $? != "0" ]; then
	VERDICT=failed
fi

stage haxe-oracle-run 0 bash -c "cd $RUN/oracle && timeout 120 bun oracle.js"
if [ $? != "0" ]; then
	VERDICT=failed
fi

stage haxe-oracle-expect 0 diff -u tests/haxe/throwing-default/expected.txt "$STAGES/haxe-oracle-run/stdout"
if [ $? != "0" ]; then
	VERDICT=failed
fi

# ------------------------------------------------------------------- targets
run_rust() {
	local gen=$RUN/rust/gen
	mkdir -p "$gen"
	expect_stage gen-rust
	expect_stage lowering-rust
	expect_stage compile-rust
	expect_stage run-rust
	expect_stage compare-rust

	stage gen-rust 0 haxe tests/haxe/throwing-default/gen/rust.hxml \
		-D "rust-output=$gen" -D "rust-test-output=$RUN/rust/gen-tests"
	if [ $? != "0" ]; then
		OBSERVATIONS=$((OBSERVATIONS + 1))
		printf 'rust generation failed; raw diagnostic in stages/gen-rust\n' >>"$RUN/target-notes.txt"
		not_reached gen-rust $? lowering-rust compile-rust run-rust compare-rust
		return
	fi
	tree_manifest "$gen" "$RUN/rust-tree.sha256"
	# The generated fixture file is the failure-domain evidence: the
	# signatures, the unwrap_or_else closure, and the region lowering.
	cp "$gen/throwdef/throwing_default_ops.rs" "$RUN/rust-throwing-default-ops.rs"
	stage lowering-rust 0 bash -c "grep -n 'pub fn\|unwrap_or_else\|\.unwrap()\|match (||' '$RUN/rust-throwing-default-ops.rs'"

	stage compile-rust 0 bash -c "cd $gen && mkdir -p src && cp $HERE/native/harness.rs src/main.rs && sha256sum src/main.rs >harness.sha256 && timeout 1800 cargo build --offline --target-dir $TMP_ROOT/rust-target"
	if [ $? != "0" ]; then
		OBSERVATIONS=$((OBSERVATIONS + 1))
		printf 'rust native compile failed; raw diagnostic in stages/compile-rust\n' >>"$RUN/target-notes.txt"
		not_reached compile-rust $? run-rust compare-rust
		return
	fi

	# Authored expectation at base e8648488: the throwing omission shape
	# panics at the unwrap inside the unwrap_or_else closure (exit 101),
	# truncating the output after the first line.
	stage run-rust 101 bash -c "cd $TMP_ROOT/rust-target/debug && timeout 120 ./generated"
	runRc=$?
	if [ "$runRc" != "101" ]; then
		DIFFERENCES=$((DIFFERENCES + 1))
		printf 'rust native run exited %s (authored expectation 101)\n' "$runRc" >>"$RUN/target-notes.txt"
	fi

	# The divergence from the oracle is the observation: the diff must
	# be nonempty. An identical run means the failure domain changed.
	stage compare-rust 1 diff -u tests/haxe/throwing-default/expected.txt "$STAGES/run-rust/stdout"
	cmpRc=$?
	if [ "$cmpRc" = "0" ]; then
		DIFFERENCES=$((DIFFERENCES + 1))
		printf 'rust native run now matches the oracle; the panic divergence is gone\n' >>"$RUN/target-notes.txt"
	fi
}

run_swift() {
	local gen=$RUN/swift/gen
	mkdir -p "$gen"
	expect_stage gen-swift
	expect_stage lowering-swift
	expect_stage compile-swift
	expect_stage run-swift
	expect_stage compare-swift

	stage gen-swift 0 haxe tests/haxe/throwing-default/gen/swift.hxml \
		-D "swift-output=$gen" -D "swift-test-output=$RUN/swift/gen-tests"
	if [ $? != "0" ]; then
		OBSERVATIONS=$((OBSERVATIONS + 1))
		printf 'swift generation failed; raw diagnostic in stages/gen-swift\n' >>"$RUN/target-notes.txt"
		not_reached gen-swift $? lowering-swift compile-swift run-swift compare-swift
		return
	fi
	tree_manifest "$gen" "$RUN/swift-tree.sha256"
	cp "$gen/throwdef/ThrowingDefaultOps.swift" "$RUN/swift-ThrowingDefaultOps.swift"
	stage lowering-swift 0 bash -c "grep -n 'func\|try\|throws\|do {\|catch' '$RUN/swift-ThrowingDefaultOps.swift'"

	if [ -z "$SWIFTC" ]; then
		printf 'swift: toolchain unusable in this environment; recorded as a target toolchain limitation\n' >>"$RUN/toolchain-limits.txt"
		OBSERVATIONS=$((OBSERVATIONS + 1))
		not_reached swift-toolchain-unavailable 1 compile-swift run-swift compare-swift
		return
	fi
	if [ "$SWIFT_MODE" = "raw" ]; then
		stage compile-swift 0 bash -c "cd $gen && cp $HERE/native/native-main.swift native-main.swift && sha256sum native-main.swift >harness.sha256 && cd $TMP_ROOT/swift-shim && LD_LIBRARY_PATH='$SWIFT_LD' timeout 1800 $SWIFTC -o $TMP_ROOT/swift/run-bin \$(find $gen -maxdepth 1 -name '*.swift' -type f ! -name 'native-main.swift' ! -name 'Package.swift') \$(find $gen/std $gen/throwdef -name '*.swift') $gen/native-main.swift -Xcc -I$FHS_ROOTFS/usr/include -L$FHS_ROOTFS/usr/lib64 -L$GCCRT_DIR -L$LIBGCCS_DIR -L$GLIBC_LIB"
	else
		stage compile-swift 0 bash -c "cd $gen && cp $HERE/native/native-main.swift native-main.swift && sha256sum native-main.swift >harness.sha256 && timeout 1800 $SWIFTC -o $TMP_ROOT/swift/run-bin \$(find . -maxdepth 1 -name '*.swift' -type f ! -name 'native-main.swift' ! -name 'Package.swift') \$(find std throwdef -name '*.swift') native-main.swift"
	fi
	if [ $? != "0" ]; then
		OBSERVATIONS=$((OBSERVATIONS + 1))
		printf 'swift native compile failed; raw diagnostic in stages/compile-swift\n' >>"$RUN/target-notes.txt"
		not_reached compile-swift $? run-swift compare-swift
		return
	fi
	# The generated-code warning on the redundant `try` marker over the
	# normalized local is a build-phase diagnostic, recorded as data
	# (BUILD-PHASE-DIAGNOSTIC-RULING: a separate matter from the
	# failure-domain observation).
	grep -c "no calls to throwing functions occur within 'try' expression" \
		"$STAGES/compile-swift/stderr" >"$RUN/swift-redundant-try-warning-count.txt" 2>/dev/null || true

	stage run-swift 0 bash -c "cd $TMP_ROOT/swift && LD_LIBRARY_PATH='${BORING_SWIFT_LIBDISPATCH:-}' timeout 300 ./run-bin"
	if [ $? != "0" ]; then
		OBSERVATIONS=$((OBSERVATIONS + 1))
		printf 'swift native run exited nonzero; raw streams in stages/run-swift\n' >>"$RUN/target-notes.txt"
		not_reached run-swift $? compare-swift
		return
	fi

	stage compare-swift 0 diff -u tests/haxe/throwing-default/expected.txt "$STAGES/run-swift/stdout"
	if [ $? != "0" ]; then
		DIFFERENCES=$((DIFFERENCES + 1))
		printf 'swift native run diverged from the oracle; diff in stages/compare-swift\n' >>"$RUN/target-notes.txt"
	fi
}

run_rust
run_swift

# ------------------------------------------------------------------ summary
if [ "$VERDICT" = "success" ] && { [ "$DIFFERENCES" != "0" ] || [ "$OBSERVATIONS" != "0" ]; }; then
	VERDICT=observed-differences
fi
{
	printf 'attempt %s\n' "$ATT_ID"
	printf 'verdict %s\n' "$VERDICT"
	printf 'differences %s\n' "$DIFFERENCES"
	printf 'observations %s\n' "$OBSERVATIONS"
	printf 'unreachable-stages %s\n' "$UNREACHED"
	printf 'identity-failures %s\n' "$IDENTITY_FAILURES"
	printf 'evidence %s\n' "$RUN"
} >"$RUN/summary.txt"
cat "$RUN/summary.txt"

case "$VERDICT" in
success) exit 0 ;;
observed-differences) exit 0 ;;
failed) exit 1 ;;
harness-defect) exit 1 ;;
esac
