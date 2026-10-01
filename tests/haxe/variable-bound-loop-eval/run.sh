#!/usr/bin/env bash
# Runner for the variable-bound counted loop evaluation audit fixture.
#
# It re-confirms the Haxe 4.3.7 JS oracle (haxe oracle.hxml, then node) and
# then drives the five cross targets through the same three-stage chain:
# generation (haxe gen/<t>.hxml), native compilation, and execution of the
# native invocation driver. Each target's driver calls the three generated
# probe functions once each and prints the three returned bound-read counts
# as one line, `local=<a> length=<b> control=<c>`, the same payload the
# oracle's trace prints.
#
# The fixture source (vble/Probe.hx) is compiled unmodified: its main() calls
# trace(...), and on the cross targets that call resolves to the fixture-local
# no-op shadow of haxe.Log (see shadow/haxe/Log.hx and REPORT.md). The shadow
# changes no counted expression; the native driver is the only printer of the
# observation line.
#
# Every stage records its argv, working directory, stdout, stderr, and raw
# exit code under $RUN/stages/NN-<name>/ (no pipes around the measured
# command). Target-level generation, compilation, or run failures are
# observations, not defects: they are recorded with the failed producer and
# the downstream stages are marked not-reached. The runner exits non-zero
# only on harness defects (oracle mismatch, input drift, a declared stage
# with no row, or a run that produced no parseable observation).
#
# Evidence lives inside the worktree under out/ (gitignored):
#   $ROOT/out/variable-bound-loop-eval/runs/<utc-stamp>/
set -u

HERE="$(cd "$(dirname "$0")" && pwd)" || exit 2
ROOT="$(cd "$HERE/../../.." && pwd)" || exit 2
cd "$ROOT" || exit 2

# --- Pinned toolchain paths ----------------------------------------------------
# Found and version-checked by the identity stages; the search evidence (which
# <tool>, ls /nix/store | grep -i <tool>) is recorded in REPORT.md.
TQ_ROOT="$(cd "$ROOT/../../.." && pwd)"
HAXE_BIN=/nix/store/98pb92k7pi6g5cifmg872jn18kghaxw5-haxe-4.3.7/bin
RUST_BIN=/nix/store/agfrkw7lvckq29w4dp0i3jfrhxjmgv3q-rust-default-1.98.0/bin
NODE_BIN=/nix/store/vd788darzi6n1k2zrj5x3kqgg03kbz93-nodejs-official-22.23.3/bin
DART_BIN=/nix/store/vsv6nwqv7g9vdkyj2paxa9g8vki0svvy-dart-3.13.3/bin
KOTLIN_BIN=/nix/store/rqx09a40a82di944xi6ydjyzx632av28-kotlin-2.4.10/bin
JAVA_BIN=/run/current-system/sw/bin
SWIFTC="$TQ_ROOT/p09-chainA-work/swift-shim-bin/swiftc"
TSC="$TQ_ROOT/boring/node_modules/.bin/tsc"
export PATH="$HAXE_BIN:$RUST_BIN:$NODE_BIN:$DART_BIN:$KOTLIN_BIN:$JAVA_BIN:$PATH"

# --- Run directory -------------------------------------------------------------
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
RUN="$ROOT/out/variable-bound-loop-eval/runs/$STAMP"
ST="$RUN/stages"
STATUS="$RUN/stages.tsv"
OBS="$RUN/observations.tsv"
FINDINGS="$RUN/findings.txt"
EXPECTED_STAGES="$RUN/expected-stages.txt"
TAB="$(printf '\t')"

mkdir -p "$ST" || exit 2
: >"$STATUS"; : >"$OBS"; : >"$FINDINGS"; : >"$EXPECTED_STAGES"

STAGE_NO=0
LAST_DIR=
LAST_RC=
VERDICT=ok

# Verdicts rank like the dc-promoted-eval runner: a higher-ranked verdict
# replaces a lower one, so a harness defect is never overwritten by a
# target-level observation such as a rejected generation.
verdict_rank() {
	case "$1" in
		ok) printf '0' ;;
		target-diverges) printf '1' ;;
		generation-failed) printf '2' ;;
		harness-defect) printf '3' ;;
		*) printf '4' ;;
	esac
}

set_verdict() { # set_verdict <verdict>
	local new_rank old_rank
	new_rank="$(verdict_rank "$1")"
	old_rank="$(verdict_rank "$VERDICT")"
	if [ "$new_rank" -gt "$old_rank" ]; then
		VERDICT="$1"
	fi
}
note() { printf '%s\n' "$1" >>"$FINDINGS"; }
declare_stage() { grep -qxF "$1" "$EXPECTED_STAGES" 2>/dev/null || printf '%s\n' "$1" >>"$EXPECTED_STAGES"; }
record_row() { printf '%s%s%s%s%s\n' "$1" "$TAB" "$2" "$TAB" "$3" >>"$STATUS"; }
mark_unreached() { local producer="$1" reason="$2" s; shift 2; for s in "$@"; do declare_stage "$s"; record_row "$s" "not-reached" "producer=$producer reason=$reason"; done; }

run_stage() { # run_stage <name> <cmd...>; cwd is always the worktree root
	local name="$1"; shift
	STAGE_NO=$((STAGE_NO + 1))
	local dir="$ST/$(printf '%02d' "$STAGE_NO")-$name"
	mkdir -p "$dir" || return 1
	printf '%s\0' "$@" >"$dir/argv"
	printf '%s\n' "$@" >"$dir/argv.txt"
	printf '%s\n' "$ROOT" >"$dir/cwd"
	"$@" >"$dir/stdout" 2>"$dir/stderr"
	LAST_RC=$?
	printf '%s\n' "$LAST_RC" >"$dir/status"
	record_row "$name" "$LAST_RC" "$dir"
	LAST_DIR="$dir"
	return 0
}

# --- Observation handling --------------------------------------------------------
EXPECTED="local=4 length=3 control=4"
triple_of() { # extract the bound-read triple from an observation line
	sed -n 's/.*local=\([0-9][0-9]*\) length=\([0-9][0-9]*\) control=\([0-9][0-9]*\).*/local=\1 length=\2 control=\3/p' <<<"$1" | head -n 1
}

record_run() { # record_run <target> <run-stage> ; uses LAST_DIR/LAST_RC
	local target="$1" stage="$2"
	local obs triple
	obs="$(head -n 1 "$LAST_DIR/stdout" 2>/dev/null | tr -d '\r')"
	triple="$(triple_of "$obs")"
	if [ "$LAST_RC" != "0" ]; then
		note "run stage $stage for $target exited $LAST_RC; stderr head: $(head -n 3 "$LAST_DIR/stderr" | tr '\n' ' ')"
		printf '%s%s%s%s%s%s%s%s%s\n' "$target" "$TAB" "$stage" "$TAB" "$LAST_RC" "$TAB" "${obs:-<empty-stdout>}" "$TAB" failed >>"$OBS"
	elif [ -n "$triple" ] && [ "$triple" = "$EXPECTED" ]; then
		printf '%s%s%s%s%s%s%s%s%s\n' "$target" "$TAB" "$stage" "$TAB" "$LAST_RC" "$TAB" "$obs" "$TAB" measured-matches-oracle >>"$OBS"
	elif [ -n "$triple" ]; then
		note "RUNTIME DIVERGENCE: $target $stage printed $triple where the oracle reads $EXPECTED (exit $LAST_RC): $obs"
		printf '%s%s%s%s%s%s%s%s%s\n' "$target" "$TAB" "$stage" "$TAB" "$LAST_RC" "$TAB" "$obs" "$TAB" measured-diverges >>"$OBS"
		set_verdict target-diverges
	else
		note "run stage $stage for $target exited 0 but printed no parseable bound-read triple: ${obs:-<empty-stdout>}"
		printf '%s%s%s%s%s%s%s%s%s\n' "$target" "$TAB" "$stage" "$TAB" "$LAST_RC" "$TAB" "${obs:-<empty-stdout>}" "$TAB" no-observation >>"$OBS"
		set_verdict harness-defect
	fi
}

mark_target_unreached() { # mark_target_unreached <target> <producer> <reason> <run-stage>
	local target="$1" producer="$2" reason="$3" stage="$4"
	note "target $target: run stage $stage not reached (producer $producer: $reason)"
	printf '%s%s%s%s%s%s%s%s%s\n' "$target" "$TAB" "$stage" "$TAB" not-reached "$TAB" "-" "$TAB" "producer=$producer reason=$reason" >>"$OBS"
}

# --- Toolchain identity ----------------------------------------------------------
declare -a EXPECTED_ALL=(
	identity-tools identity-toolpaths input-hashes-before oracle-gen oracle-run
	gen-ts gen-kotlin gen-rust gen-swift gen-dart
	ts-typecheck ts-emit ts-run
	kotlin-build kotlin-run
	rust-lib rust-harness rust-run
	swift-lib swift-harness swift-run
	dart-run input-hashes-after
)

run_stage identity-tools bash -c '
	printf "haxe %s\n" "$(haxe --version 2>&1 | head -n 1)"
	printf "haxelib %s\n" "$(haxelib version 2>&1 | head -n 1)"
	printf "rustc %s\n" "$(rustc --version 2>&1)"
	printf "node %s\n" "$(node --version 2>&1)"
	printf "dart %s\n" "$(dart --version 2>&1 | head -n 1)"
	printf "kotlinc %s\n" "$(kotlinc -version 2>&1 | head -n 1)"
	printf "java %s\n" "$(java -version 2>&1 | head -n 1)"
	printf "tsc %s\n" "$("$1" --version 2>&1 | head -n 1)"
	printf "swiftc-shim %s\n" "$(head -n 1 "$2" 2>/dev/null)"
' bash "$TSC" "$SWIFTC"
if [ "$LAST_RC" != "0" ]; then
	note "identity-tools failed (exit $LAST_RC): at least one pinned tool is missing or broken"
	set_verdict harness-defect
fi

run_stage identity-toolpaths bash -c '
	printf "worktree %s\n" "$1"
	printf "haxe %s\n" "$(command -v haxe)"
	printf "haxelib %s\n" "$(command -v haxelib)"
	printf "rustc %s\n" "$(command -v rustc)"
	printf "node %s\n" "$(command -v node)"
	printf "dart %s\n" "$(command -v dart)"
	printf "kotlinc %s\n" "$(command -v kotlinc)"
	printf "java %s\n" "$(command -v java)"
	printf "tsc %s\n" "$2"
	printf "tsc-real %s\n" "$(readlink -f "$2")"
	printf "tsc-sha256 %s\n" "$(sha256sum "$2" | cut -d" " -f1)"
	printf "swiftc %s\n" "$3"
	printf "haxelib-config-dir %s\n" "$4"
	printf -- "- haxelib path reflaxe boring:\n"
	haxelib path reflaxe boring 2>&1
	printf -- "- haxelib dev markers:\n"
	for m in "$4"/reflaxe/.dev "$4"/boring/.dev; do
		printf "  %s: %s\n" "$m" "$(tr "\n" " " <"$m" 2>/dev/null || printf "<missing>")"
	done
' bash "$ROOT" "$TSC" "$SWIFTC" "$TQ_ROOT/.haxelib"

# --- Authored-input digests ------------------------------------------------------
# Everything the generation consumes: the fixture, the locally-referenced trees
# (std-shadow, samples, packages/compiler), and the two library resolutions the
# haxelib dev markers point at (reflaxe in the nix store, boring in the
# sibling worktree) plus the format package the boring lib pulls in.
INPUT_MANIFEST="$RUN/input-files.txt"
INPUT_ROOTS=(
	"$HERE"
	"$ROOT/packages/compiler"
	"$ROOT/samples"
	/nix/store/ch901mw058pjvr3nyxgwxps31vc46wmm-source/src
	"$TQ_ROOT/.haxelib/format/3,8,0"
)
: >"$INPUT_MANIFEST"
for r in "${INPUT_ROOTS[@]}"; do
	[ -e "$r" ] || { note "input root $r is missing"; set_verdict harness-defect; }
	find "$r" -type f 2>/dev/null >>"$INPUT_MANIFEST"
done
LC_ALL=C sort -o "$INPUT_MANIFEST" "$INPUT_MANIFEST"

run_stage input-hashes-before bash -c 'xargs -d "\n" sha256sum < "$1" > "$2"' bash "$INPUT_MANIFEST" "$RUN/input-hashes-before.sha256"
if [ "$LAST_RC" != "0" ]; then
	note "cannot digest the authored inputs before the attempt"
	set_verdict harness-defect
fi

# --- Oracle ----------------------------------------------------------------------
run_stage oracle-gen haxe "$HERE/oracle.hxml"
if [ "$LAST_RC" != "0" ]; then
	note "the Haxe JS oracle generation failed (exit $LAST_RC); the reference reading cannot be re-confirmed"
	set_verdict harness-defect
fi

run_stage oracle-run node /tmp/vble-oracle.js
oracle_obs="$(head -n 1 "$LAST_DIR/stdout" 2>/dev/null | tr -d '\r')"
oracle_triple="$(triple_of "$oracle_obs")"
if [ "$oracle_triple" != "$EXPECTED" ]; then
	note "oracle re-run did not reproduce the authored reading: ${oracle_obs:-<empty-stdout>}"
	set_verdict harness-defect
else
	printf 'oracle re-confirmed: %s\n' "$oracle_obs" >"$RUN/oracle.txt"
fi

# --- Generation -------------------------------------------------------------------
for t in ts kotlin rust swift dart; do
	run_stage "gen-$t" haxe "$HERE/gen/$t.hxml" -D "$t-output=$RUN/$t-gen" -D "$t-test-output=$RUN/$t-gen-tests"
	if [ "$LAST_RC" != "0" ]; then
		note "generation for $t was rejected (exit $LAST_RC); stderr head: $(grep -E '^error' "$LAST_DIR/stderr" | head -n 3 | tr '\n' ' ')"
		set_verdict generation-failed
	fi
done

gen_ok() {
	local f
	for f in "$ST"/*-gen-"$1"/status; do
		[ -e "$f" ] || return 1
		[ "$(head -n 1 "$f")" = "0" ] && return 0
		return 1
	done
	return 1
}

# --- TypeScript --------------------------------------------------------------------
TS_GEN="$RUN/ts-gen"
TS_JS="$RUN/ts-js"
if gen_ok ts; then
	run_stage ts-typecheck bash -c '
		cp "$1" "$2" || exit 2
		"$3" --noEmit --strict --target ES2022 --module ES2022 --moduleResolution node --allowImportingTsExtensions "$2"
	' bash "$HERE/native/driver.ts" "$TS_GEN/driver.ts" "$TSC"
	if [ "$LAST_RC" != "0" ]; then
		mark_unreached "ts-typecheck" "exit $LAST_RC" ts-emit ts-run
		mark_target_unreached ts ts-typecheck "exit $LAST_RC" ts-run
	else
		run_stage ts-emit bash -c '
			mkdir -p "$2" || exit 2
			"$3" --strict --target ES2022 --moduleResolution node --allowImportingTsExtensions --rewriteRelativeImportExtensions --outDir "$2" --rootDir "$1" "$1/driver.ts"
		' bash "$TS_GEN" "$TS_JS" "$TSC"
		if [ "$LAST_RC" != "0" ]; then
			mark_unreached "ts-emit" "exit $LAST_RC" ts-run
			mark_target_unreached ts ts-emit "exit $LAST_RC" ts-run
		else
			run_stage ts-run node "$TS_JS/driver.js"
			record_run ts ts-run
		fi
	fi
else
	mark_unreached "gen-ts" "exit $(head -n 1 "$ST"/*-gen-ts/status 2>/dev/null)" ts-typecheck ts-emit ts-run
	mark_target_unreached ts gen-ts "generation rejected" ts-run
fi

# --- Kotlin -------------------------------------------------------------------------
KO_GEN="$RUN/kotlin-gen"
if gen_ok kotlin; then
	run_stage kotlin-build bash -c '
		cp "$1" "$2/Main.kt" || exit 2
		srcs="$(find "$2" -name "*.kt" -not -path "$2/runtime/*" | LC_ALL=C sort)" || exit 2
		[ -n "$srcs" ] || exit 2
		mkdir -p "$3" || exit 2
		kotlinc -Xallow-kotlin-package $srcs -include-runtime -d "$3/probe.jar"
	' bash "$HERE/native/Main.kt" "$KO_GEN" "$RUN/kotlin-build"
	if [ "$LAST_RC" != "0" ]; then
		mark_unreached "kotlin-build" "exit $LAST_RC" kotlin-run
		mark_target_unreached kotlin kotlin-build "exit $LAST_RC" kotlin-run
	else
		run_stage kotlin-run java -cp "$RUN/kotlin-build/probe.jar" MainKt
		record_run kotlin kotlin-run
	fi
else
	mark_unreached "gen-kotlin" "exit $(head -n 1 "$ST"/*-gen-kotlin/status 2>/dev/null)" kotlin-build kotlin-run
	mark_target_unreached kotlin gen-kotlin "generation rejected" kotlin-run
fi

# --- Rust ---------------------------------------------------------------------------
RU_GEN="$RUN/rust-gen"
if gen_ok rust; then
	run_stage rust-lib bash -c '
		rustc --edition=2024 --crate-type lib --crate-name vble -o "$1/lib.rlib" "$1/lib.rs"
	' bash "$RU_GEN"
	if [ "$LAST_RC" != "0" ]; then
		note "rust-lib failed (exit $LAST_RC); rustc errors: $(grep -E '^error(\[E[0-9]+\])?:' "$LAST_DIR/stderr" | head -n 5 | tr '\n' ' ')"
		mark_unreached "rust-lib" "exit $LAST_RC" rust-harness rust-run
		mark_target_unreached rust rust-lib "exit $LAST_RC" rust-run
	else
		run_stage rust-harness bash -c '
			cp "$1" "$2/harness.rs" || exit 2
			rustc --edition=2024 -o "$2/harness-bin" "$2/harness.rs" --extern vble="$2/lib.rlib"
		' bash "$HERE/native/harness.rs" "$RU_GEN"
		if [ "$LAST_RC" != "0" ]; then
			note "rust-harness failed (exit $LAST_RC); rustc errors: $(grep -E '^error(\[E[0-9]+\])?:' "$LAST_DIR/stderr" | head -n 5 | tr '\n' ' ')"
			mark_unreached "rust-harness" "exit $LAST_RC" rust-run
			mark_target_unreached rust rust-harness "exit $LAST_RC" rust-run
		else
			run_stage rust-run "$RU_GEN/harness-bin"
			record_run rust rust-run
		fi
	fi
else
	mark_unreached "gen-rust" "exit $(head -n 1 "$ST"/*-gen-rust/status 2>/dev/null)" rust-lib rust-harness rust-run
	mark_target_unreached rust gen-rust "generation rejected" rust-run
fi

# --- Swift ----------------------------------------------------------------------------
SW_GEN="$RUN/swift-gen"
if gen_ok swift; then
	run_stage swift-lib bash -c '
		srcs="$(find "$2" -name "*.swift" -not -name "Package.swift" | LC_ALL=C sort)" || exit 2
		[ -n "$srcs" ] || exit 2
		mkdir -p "$3" || exit 2
		"$1" -emit-library -emit-module $srcs -module-name VbleProbe -o "$3/libVbleProbe.so"
	' bash "$SWIFTC" "$SW_GEN" "$RUN/swift-build"
	if [ "$LAST_RC" != "0" ]; then
		note "swift-lib failed (exit $LAST_RC); swiftc errors: $(grep -E 'error:' "$LAST_DIR/stderr" | head -n 5 | tr '\n' ' ')"
		mark_unreached "swift-lib" "exit $LAST_RC" swift-harness swift-run
		mark_target_unreached swift swift-lib "exit $LAST_RC" swift-run
	else
		run_stage swift-harness bash -c '
			"$1" "$2" -I "$3" -L "$3" -lVbleProbe -o "$4"
		' bash "$SWIFTC" "$HERE/native/main.swift" "$RUN/swift-build" "$RUN/swift-build/runner"
		if [ "$LAST_RC" != "0" ]; then
			note "swift-harness failed (exit $LAST_RC); swiftc errors: $(grep -E 'error:' "$LAST_DIR/stderr" | head -n 5 | tr '\n' ' ')"
			mark_unreached "swift-harness" "exit $LAST_RC" swift-run
			mark_target_unreached swift swift-harness "exit $LAST_RC" swift-run
		else
			run_stage swift-run "$RUN/swift-build/runner"
			record_run swift swift-run
		fi
	fi
else
	mark_unreached "gen-swift" "exit $(head -n 1 "$ST"/*-gen-swift/status 2>/dev/null)" swift-lib swift-harness swift-run
	mark_target_unreached swift gen-swift "generation rejected" swift-run
fi

# --- Dart -------------------------------------------------------------------------------
DA_GEN="$RUN/dart-gen"
if gen_ok dart; then
	run_stage dart-run bash -c '
		cp "$1" "$2/driver.dart" || exit 2
		dart run "$2/driver.dart"
	' bash "$HERE/native/driver.dart" "$DA_GEN"
	record_run dart dart-run
else
	mark_unreached "gen-dart" "exit $(head -n 1 "$ST"/*-gen-dart/status 2>/dev/null)" dart-run
	mark_target_unreached dart gen-dart "generation rejected" dart-run
fi

# --- Input digests after ----------------------------------------------------------------
run_stage input-hashes-after bash -c 'xargs -d "\n" sha256sum < "$1" > "$2"' bash "$INPUT_MANIFEST" "$RUN/input-hashes-after.sha256"
if [ "$LAST_RC" != "0" ]; then
	note "cannot digest the authored inputs after the attempt"
	set_verdict harness-defect
elif cmp -s "$RUN/input-hashes-before.sha256" "$RUN/input-hashes-after.sha256"; then
	printf 'the authored input trees are unchanged by the run\n' >"$RUN/input-unchanged.txt"
else
	{
		printf 'the authored input trees changed during the run\n'
		diff "$RUN/input-hashes-before.sha256" "$RUN/input-hashes-after.sha256" || true
	} >"$RUN/input-unchanged.txt"
	note "the authored input trees changed during the run; see input-unchanged.txt"
	set_verdict harness-defect
fi

# --- Stage membership ---------------------------------------------------------------------
printf '%s\n' "${EXPECTED_ALL[@]}" | LC_ALL=C sort >"$RUN/declared-stages-sorted.txt"
cut -f1 "$STATUS" | sort >"$RUN/observed-stages.txt"
comm -3 "$RUN/declared-stages-sorted.txt" "$RUN/observed-stages.txt" >"$RUN/stage-diff.txt"
if [ -s "$RUN/stage-diff.txt" ]; then
	note "the recorded stage set differs from the declared set; see stage-diff.txt"
	set_verdict harness-defect
fi
for s in "${EXPECTED_ALL[@]}"; do
	grep -q "^$s$TAB" "$STATUS" || { record_row "$s" "not-reached" "no row was written"; note "declared stage $s never produced a row"; set_verdict harness-defect; }
done

# --- Summary ---------------------------------------------------------------------------------
{
	printf 'run %s\n' "$RUN"
	printf 'worktree %s\n' "$ROOT"
	printf 'oracle %s (expected %s)\n' "$oracle_triple" "$EXPECTED"
	printf '\n'
	printf 'target\tstage\trc\tobservation\tstatus\n'
	cat "$OBS"
	printf '\n'
	printf 'verdict %s\n' "$VERDICT"
} >"$RUN/summary.txt"

# Target-level generation, compilation, and run failures are observations and
# do not fail the runner. A target whose reading diverges from the oracle is
# the audit's data, not a harness defect: it is noted in findings and the
# runner exits 0 so the recorded evidence stays. Only harness defects
# (oracle mismatch, input drift, missing stage, no parseable observation)
# make this script exit non-zero.
if [ "$VERDICT" = "harness-defect" ]; then
	exit 1
fi
printf 'evidence root %s\n' "$RUN"
exit 0
