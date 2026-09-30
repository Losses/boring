#!/usr/bin/env bash
# Reproducible driver for the PIT-281 payload-key discriminating controls
# (task t-mune0a1j-vmt1, row test/wire-payload-key-controls).
#
# The four fixtures in tests/haxe/payload-key/ were committed with the fix
# (ae0657e7) but had no committed command driving them, so the declaration-
# order discriminating power ("both pk and pkrev generate and cargo-check
# clean") was not reproducible from the repository. This runner drives all
# three generation controls in one invocation:
#
#   pk         gen/rust.hxml          -> pk/PayloadKeyProbe.hx
#   pkrev      gen/rust-rev.hxml      -> pkrev/PayloadKeyProbe.hx (order mirror)
#   faultnames gen/rust-faultnames.hxml -> pkf/FaultNameProbe.hx (rename control)
#
# Each probe is generated into its own tree (a combined tree would cross-
# register the sibling module's identically-named E1/E2 structs and fail
# cargo with E0308, so separate trees are required) and cargo-builds the
# generated tree. Every stage records its raw stdout/stderr and a direct
# exit code (never through a pipe); diagnostics are counted by shape
# `^error(\[E[0-9]+\])?:` so rustc's --explain hint lines are not double-
# counted.
#
# Invoke from the worktree root inside the pinned devShell:
#   nix develop -c bash tests/haxe/payload-key/run.sh
#
# The devShell shellHook bootstraps .haxelib (git-ignored) fresh in $PWD, so
# this also runs from a clean `git archive` export of the repository.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
cd "$ROOT" || exit 2
if [ "$ROOT" != "$(pwd)" ] || [ ! -f "$ROOT/flake.nix" ]; then
	printf 'the worktree root was not resolved: %s\n' "$ROOT"
	exit 2
fi
if [ "${IN_NIX_SHELL:-}" = "" ]; then
	printf 'run this runner through: nix develop -c bash tests/haxe/payload-key/run.sh\n'
	exit 2
fi

# Evidence root: default to out/payload-key under the workspace, overridable.
PK_ROOT="${PK_EVIDENCE_ROOT:-$(cd "$ROOT/../.." && pwd)/out/payload-key}"
mkdir -p "$PK_ROOT" || exit 2
RUN="$(mktemp -d "$PK_ROOT/pk-XXXXXX")" || exit 2
ST="$RUN/stages"
LOGS="$RUN/logs"
mkdir -p "$ST" "$LOGS" || exit 2

TAB="$(printf '\t')"
STATUS="$RUN/status.tsv"
: >"$STATUS"
printf 'stage%stag%sexpected%sobserved%sexit\n' "$TAB" "$TAB" "$TAB" "$TAB" >"$STATUS"

VERDICT=complete
STAGE_NO=0

log() { printf '%s\n' "$1"; }

record() { # record <stage> <status> <note>
	printf '%s%s%s%s%s\n' "$1" "$TAB" "$2" "$TAB" "$3" >>"$STATUS"
}

# run_stage <name> <cmd...>   cwd is always the worktree root
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

# error_count <dir> : diagnostics counted by shape, not by bare 'error'.
# grep -c prints "0" and exits 1 when nothing matches; `|| true` keeps that
# single "0" without printing a second one.
error_count() {
	grep -cE '^error(\[E[0-9]+\])?:' "$1/stderr" 2>/dev/null || true
}

# gen_and_check <label> <hxml> <outdir> <cargo-target>
# Generates the probe into its own tree and cargo-builds it, recording the
# direct rc of each command and the shape-counted error total.
gen_and_check() {
	local label="$1" hxml="$2" outdir="$3" target="$4"
	local genrc cargocrc errs
	run_stage "gen-$label" haxe "$hxml" -D "rust-output=$outdir"
	genrc="$?"
	if [ "$genrc" != "0" ]; then
		record "cargo-$label" "not-reached" "producer=gen-$label"
		VERDICT=generation-failed
		return 1
	fi
	run_stage "cargo-$label" bash -c "cd '$outdir' && CARGO_TARGET_DIR='$target' cargo build --offline"
	cargocrc="$?"
	errs="$(error_count "$ST/$(printf '%02d' "$STAGE_NO")-cargo-$label")"
	printf 'gen-%s rc=%s cargo-%s rc=%s errors=%s\n' "$label" "$genrc" "$label" "$cargocrc" "$errs"
	if [ "$cargocrc" != "0" ] || [ "$errs" != "0" ]; then
		VERDICT=generation-failed
		return 1
	fi
	return 0
}

# --- Tool identity ------------------------------------------------------------
run_stage identity-rev git rev-parse HEAD
run_stage identity-haxe haxe --version
run_stage identity-cargo cargo --version

# --- The three discriminating controls ----------------------------------------
# pk and pkrev must live in separate trees: a combined tree cross-registers
# the sibling module's identically-named E1/E2 structs (E0308).
gen_and_check pk      "$HERE/gen/rust.hxml"           "$RUN/gen-pk"      "$RUN/cargo-target-pk"
gen_and_check pkrev   "$HERE/gen/rust-rev.hxml"       "$RUN/gen-pkrev"   "$RUN/cargo-target-pkrev"
gen_and_check faultnames "$HERE/gen/rust-faultnames.hxml" "$RUN/gen-faultnames" "$RUN/cargo-target-faultnames"

# --- Summary ------------------------------------------------------------------
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