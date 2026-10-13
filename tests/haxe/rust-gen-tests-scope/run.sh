#!/usr/bin/env bash
# Reproducible driver for the P6.6 test-module std.Fs domain diagnostic
# (task t-mv4klg3z-hghs, row arch/p6-6).
#
# A fallible std.Fs.readText call sits INSIDE a test module (@:test class).
# The test module is emitted in-crate (#[cfg(test)]) under the SAME Intercept
# roots as the main scope, so "main scope vs test scope Intercept config" is
# the same single set of roots for Rust -- the only variance is whether
# samples/std is inside that set.
#
# Two arms with divergent expected outcomes:
#
#   out-of-scope  gen/rust-out-of-scope.hxml
#       samples/std is on the classpath (std.Fs resolves and types) but
#       excluded from Intercept scope, so the std.FsError payload enum has
#       no declaration site.  Post-P6.4 generation fails with rc!=0 and the
#       diagnostic "std.FsError domain is not emitted in this compilation
#       scope".  Cargo is not reached.
#
#   in-scope     gen/rust-in-scope.hxml
#       samples/std is in Intercept scope, so the std.FsError payload enum
#       IS emitted even for the test-module call.  Generation succeeds
#       (rc=0) and the generated crate passes cargo check --offline.
#
# Invoke from the worktree root inside the pinned devShell:
#   nix develop -c bash tests/haxe/rust-gen-tests-scope/run.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
cd "$ROOT" || exit 2
if [ "$ROOT" != "$(pwd)" ] || [ ! -f "$ROOT/flake.nix" ]; then
	printf 'the worktree root was not resolved: %s\n' "$ROOT"
	exit 2
fi
if [ "${IN_NIX_SHELL:-}" = "" ]; then
	printf 'run this runner through: nix develop -c bash tests/haxe/rust-gen-tests-scope/run.sh\n'
	exit 2
fi

PK_ROOT="${PK_EVIDENCE_ROOT:-$(cd "$ROOT/../.." && pwd)/out/rust-gen-tests-scope}"
mkdir -p "$PK_ROOT" || exit 2
RUN="$(mktemp -d "$PK_ROOT/rgts-XXXXXX")" || exit 2
ST="$RUN/stages"
LOGS="$RUN/logs"
mkdir -p "$ST" "$LOGS" || exit 2

TAB="$(printf '\t')"
STATUS="$RUN/status.tsv"
: >"$STATUS"
printf 'stage\t%s\t%s\t%s\t%s\n' "$TAB" "$TAB" "$TAB" "$TAB" >"$STATUS"

VERDICT=complete
STAGE_NO=0

log() { printf '%s\n' "$1"; }

record() {
	printf '%s\t%s\t%s\t%s\n' "$1" "$TAB" "$2" "$TAB" "$3" >>"$STATUS"
}

run_stage() {
	local name="$1"
	shift
	STAGE_NO=$((STAGE_NO + 1))
	local dir="$ST/$(printf '%02d' "$STAGE_NO")-$name"
	mkdir -p "$dir" || return 1
	printf '%s\n' "$@" >"$dir/argv.txt"
	printf '%s\n' "$ROOT" >"$dir/cwd"
	"$@" >"$dir/stdout" 2>"$dir/stderr"
	local rc=$?
	printf '%s\n' "$rc" >"$dir/status"
	record "$name" "$rc" "$dir"
	return 0
}

error_count() {
	grep -cE '^error(\[E[0-9]+\])?:' "$1/stderr" 2>/dev/null || true
}

DIAGNOSTIC='std.FsError domain is not emitted in this compilation scope'

# --- Tool identity ----------------------------------------------------------
run_stage identity-rev git rev-parse HEAD
run_stage identity-haxe haxe --version
run_stage identity-cargo cargo --version

# --- Out-of-scope arm (expected failure) -----------------------------------
GEN_OUT="$RUN/gen-out-of-scope"
run_stage gen-out-of-scope \
	haxe "$HERE/gen/rust-out-of-scope.hxml" \
	-D "rust-output=$GEN_OUT"
GENRC="$(cat "$ST/$(printf '%02d' "$STAGE_NO")-gen-out-of-scope/status")"
OUTSCOPE_STDERR="$ST/$(printf '%02d' "$STAGE_NO")-gen-out-of-scope/stderr"
if [ "$GENRC" = "0" ]; then
	log 'gen-out-of-scope: expected non-zero exit code, got 0'
	VERDICT=generation-failed
elif ! grep -qF "$DIAGNOSTIC" "$OUTSCOPE_STDERR"; then
	log 'gen-out-of-scope: missing diagnostic in stderr'
	VERDICT=generation-failed
else
	log 'gen-out-of-scope: diagnostic found, rc='"$GENRC"
	record gen-out-of-scope-check ok ''
fi

# --- In-scope arm (expected success) ---------------------------------------
GEN_IN="$RUN/gen-in-scope"
run_stage gen-in-scope \
	haxe "$HERE/gen/rust-in-scope.hxml" \
	-D "rust-output=$GEN_IN"
GEN_IN_RC="$(cat "$ST/$(printf '%02d' "$STAGE_NO")-gen-in-scope/status")"
printf 'gen-in-scope rc=%s\n' "$GEN_IN_RC"
if [ "$GEN_IN_RC" != "0" ]; then
	record cargo-in-scope not-reached producer=gen-in-scope
	VERDICT=generation-failed
else
	run_stage cargo-in-scope \
		bash -c "cd '$GEN_IN' && cargo check --offline"
	CARGO_RC="$(cat "$ST/$(printf '%02d' "$STAGE_NO")-cargo-in-scope/status")"
	errs="$(error_count "$ST/$(printf '%02d' "$STAGE_NO")-cargo-in-scope")"
	printf 'cargo-in-scope rc=%s errors=%s\n' "$CARGO_RC" "$errs"
	if [ "$CARGO_RC" != "0" ] || [ "$errs" != "0" ]; then
		VERDICT=generation-failed
	fi
fi

# --- Summary ----------------------------------------------------------------
{
	printf 'run directory %s\n' "$RUN"
	printf 'verdict %s\n' "$VERDICT"
	printf '\nstatus rows\n'
	cat "$STATUS"
} >"$RUN/summary.txt"

log "run directory $RUN"
log "verdict $VERDICT"
cat "$STATUS"
[ "$VERDICT" = "complete" ] || exit 1
exit 0
