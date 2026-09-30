#!/usr/bin/env bash
# Runtime single-evaluation probe for the promoted (statement-position) enum
# switch shape, on the pinned candidate tree e1c65975.
#
# This is the runtime counterpart of the structural observation recorded by
# dc-enum-switch-gen (task t-mum05sop-cbtu): that fixture showed the promoted
# shape generates on all five targets with the subject read once into a
# synthetic local, but it never compiled or ran anything, so "single
# evaluation" was a reading of the generated text, not a measurement.
#
# Observation only: this runner never edits the compiler. It generates the
# fixture with the pinned Haxe, compiles each generated program with that
# target's real compiler, runs it, and compares the printed observation with an
# authored expectation. Every stage writes its NUL-separated argv, its working
# directory, separate raw stdout and stderr, and a numeric exit status; no
# verdict is derived from log text. A stage runs only when its producer exited
# zero, and every dependent stage of a failed producer receives an explicit
# not-reached row naming that producer.
#
# Mutating the *generated* tree is part of the measurement, not of the
# deliverable: the negative control duplicates one evaluation of the subject
# expression inside a single promoted switch, which is exactly the hazard the
# positive assertion must be able to see. The mutation is written into the run
# directory only and is reported with before/after digests.
#
# Swift is attempted and expected to be blocked in this environment (the
# pinned swiftc wrapper needs user namespaces); that stage is recorded as
# environment-not-reached and never silently skipped.
#
# Invoke from the worktree root inside the pinned toolchain:
#   nix develop -c bash tests/haxe/dc-promoted-eval/run.sh
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
cd "$ROOT" || exit 2
if [ "$ROOT" != "$(pwd)" ] || [ ! -f "$ROOT/flake.nix" ]; then
	printf 'the worktree root was not resolved: %s\n' "$ROOT"
	exit 2
fi
if [ "${IN_NIX_SHELL:-}" = "" ]; then
	printf 'run this runner through: nix develop -c bash tests/haxe/dc-promoted-eval/run.sh\n'
	exit 2
fi

PE_ROOT="${PE_EVIDENCE_ROOT:-$(cd "$ROOT/../.." && pwd)/out/promoted-eval}"
mkdir -p "$PE_ROOT" || exit 2
RUN="$(mktemp -d "$PE_ROOT/pe-XXXXXX")" || exit 2
# dc-warn is a fuse.rclone mount without an execute bit, so a Rust harness built
# under $RUN cannot be executed at all (exit 126). The Rust link products are
# therefore built in a temporary directory on an executable filesystem, and the
# binaries are copied into the run directory afterwards for retention only.
RUST_BUILD="$(mktemp -d "${TMPDIR:-/tmp}/promoted-eval-rust-XXXXXX")" || exit 2
ST="$RUN/stages"
LOGS="$RUN/logs"
BUILD="$RUN/build"
mkdir -p "$ST" "$LOGS" "$BUILD" "$RUN/snippets" || exit 2

TAB="$(printf '\t')"
STATUS="$RUN/status.tsv"
EXPECTED="$RUN/expected-stages.txt"
FINDINGS="$RUN/findings.txt"
OBS="$RUN/runtime-observations.tsv"
MUT="$RUN/mutations.tsv"
: >"$STATUS"
: >"$EXPECTED"
: >"$FINDINGS"
: >"$MUT"
printf 'stage%stag%sexpected%sobserved%sexit\n' "$TAB" "$TAB" "$TAB" "$TAB" >"$OBS"

# VERDICT is the health of this run (whether every declared stage executed and
# whether the fixture inputs held still). ASSERTION is the runtime claim the run
# is meant to measure. They are deliberately separate: an environment-blocked
# stage such as the Swift toolchain is not a harness defect, and a confirmed
# assertion does not hide a generation failure.
VERDICT=complete
ASSERTION=undetermined
POSITIVE_OBSERVED=0
CONTROL_OBSERVED=0
STAGE_NO=0
LAST_DIR=""
LAST_RC=0

log() { printf '%s\n' "$1"; }

verdict_rank() {
	case "$1" in
	complete) printf '0' ;;
	generation-failed) printf '1' ;;
	harness-defect) printf '2' ;;
	*) printf '0' ;;
	esac
}

assertion_rank() {
	case "$1" in
	undetermined) printf '0' ;;
	single-evaluation-confirmed) printf '1' ;;
	multiple-evaluation) printf '2' ;;
	*) printf '0' ;;
	esac
}

set_assertion() { # set_assertion <state>
	local new_rank old_rank
	new_rank="$(assertion_rank "$1")"
	old_rank="$(assertion_rank "$ASSERTION")"
	if [ "$new_rank" -gt "$old_rank" ]; then
		ASSERTION="$1"
	fi
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

declare_stage() { # idempotent: a stage may be declared once upfront and again by its producer
	grep -qxF "$1" "$EXPECTED" 2>/dev/null || printf '%s\n' "$1" >>"$EXPECTED"
}

record_row() { # record_row <stage> <status> <note>
	printf '%s%s%s%s%s\n' "$1" "$TAB" "$2" "$TAB" "$3" >>"$STATUS"
}

record_step() { # record_step <stage> <status> <note>  (no argv: an in-runner step)
	STAGE_NO=$((STAGE_NO + 1))
	declare_stage "$1"
	record_row "$1" "$2" "$3"
}

run_stage() { # run_stage <name> <cmd...>   (cwd is always the worktree root)
	local name="$1"
	shift
	STAGE_NO=$((STAGE_NO + 1))
	local dir="$ST/$(printf '%02d' "$STAGE_NO")-$name"
	mkdir -p "$dir" || return 1
	printf '%s\0' "$@" >"$dir/argv"
	printf '%s\n' "$@" >"$dir/argv.txt"
	printf '%s\n' "$ROOT" >"$dir/cwd"
	"$@" >"$dir/stdout" 2>"$dir/stderr"
	local rc=$?
	printf '%s\n' "$rc" >"$dir/status"
	record_row "$name" "$rc" "$dir"
	LAST_DIR="$dir"
	LAST_RC="$rc"
	return 0
}

mark_unreached() { # mark_unreached <producer> <reason> <stage...>
	local producer="$1" reason="$2"
	shift 2
	local s
	for s in "$@"; do
		record_row "$s" "not-reached" "producer=$producer reason=$reason"
	done
}

call_count_of() {
	printf '%s' "$1" | sed -n 's/.*callCount=\([0-9][0-9]*\).*/\1/p' | head -n 1
}

run_case() { # run_case <name> <tag: positive|control> <expected> <cmd...>
	local name="$1" tag="$2" expected="$3"
	shift 3
	run_stage "$name" "$@"
	local observed
	observed="$(head -n 1 "$LAST_DIR/stdout" | tr -d '\r')"
	local exp_calls obs_calls
	exp_calls="$(call_count_of "$expected")"
	obs_calls="$(call_count_of "$observed")"
	printf '%s%s%s%s%s%s%s%s%s\n' "$name" "$TAB" "$tag" "$TAB" "$expected" \
		"$TAB" "${observed:-<empty-stdout>}" "$TAB" "$LAST_RC" >>"$OBS"
	if [ -z "$exp_calls" ]; then
		note "the authored expectation of $name carries no callCount: $expected"
		set_verdict harness-defect
		return 0
	fi
	if [ -z "$obs_calls" ]; then
		note "runtime stage $name produced no callCount observation (exit $LAST_RC): ${observed:-<empty-stdout>}"
		set_verdict harness-defect
		return 0
	fi
	if [ "$tag" = "positive" ]; then
		POSITIVE_OBSERVED=$((POSITIVE_OBSERVED + 1))
		if [ "$obs_calls" = "1" ] && [ "$observed" = "$expected" ]; then
			set_assertion single-evaluation-confirmed
		elif [ "$obs_calls" != "1" ]; then
			note "MULTIPLE EVALUATION: $name observed callCount=$obs_calls where one promoted switch must evaluate its subject once; text: $observed"
			set_assertion multiple-evaluation
		else
			note "$name observed callCount=1 but a different text than authored: $observed (exit $LAST_RC)"
			set_verdict harness-defect
		fi
	else
		CONTROL_OBSERVED=$((CONTROL_OBSERVED + 1))
		if [ "$observed" = "$expected" ]; then
			: # the control reproduced the authored doubled evaluation
		else
			note "ASSERTION INSENSITIVE: control $name observed callCount=$obs_calls instead of the authored $exp_calls ($observed); the positive assertion cannot be trusted"
			set_verdict harness-defect
		fi
	fi
	return 0
}

# mutate <target> <tree-subdir> <relative-file> <call-pattern> <sed-expression>
# Copies the generated tree, inserts exactly one extra evaluation of the
# subject expression immediately after the promoted local's initializer, and
# proves the mutation took hold by counting the subject call before and after.
mutate() {
	local target="$1" tree="$2" rel="$3" pattern="$4" expr="$5"
	local src="$RUN/$tree" dst="$RUN/$tree-mut"
	local stage="mutate-$target"
	STAGE_NO=$((STAGE_NO + 1))
	declare_stage "$stage"
	# A mutation is an in-runner transformation rather than a process, so its
	# stage directory carries the recipe and the target path instead of argv.
	local dir="$ST/$(printf '%02d' "$STAGE_NO")-$stage"
	mkdir -p "$dir"
	printf '%s\n' "$expr" >"$dir/recipe.txt"
	printf '%s\n' "$src/$rel" >"$dir/source-file.txt"
	printf '%s\n' "$dst/$rel" >"$dir/mutated-file.txt"
	if [ ! -f "$src/$rel" ]; then
		printf 'failed\n' >"$dir/status"
		record_row "$stage" "failed" "$dir (missing $src/$rel)"
		note "cannot mutate $target: $src/$rel is missing"
		set_verdict harness-defect
		return 1
	fi
	rm -rf "$dst"
	if ! cp -r "$src" "$dst"; then
		printf 'failed\n' >"$dir/status"
		record_row "$stage" "failed" "$dir (cannot copy $src)"
		set_verdict harness-defect
		return 1
	fi
	local file="$dst/$rel"
	local before after before_sha after_sha
	before="$(grep -cE "$pattern" "$file")"
	before_sha="$(sha256sum "$file" | cut -d' ' -f1)"
	sed -i "$expr" "$file"
	after="$(grep -cE "$pattern" "$file")"
	after_sha="$(sha256sum "$file" | cut -d' ' -f1)"
	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$target" "$tree-mut/$rel" "$pattern" \
		"$before" "$after" "$before_sha" "$after_sha" "$expr" >>"$MUT"
	if [ "$before" != "1" ] || [ "$after" != "2" ] || [ "$before_sha" = "$after_sha" ]; then
		printf 'failed\n' >"$dir/status"
		record_row "$stage" "failed" "$dir (subject-call count $before -> $after)"
		note "the $target mutation did not take hold (subject-call count $before -> $after); the negative control is void"
		set_verdict harness-defect
		return 1
	fi
	printf 'applied\n' >"$dir/status"
	record_row "$stage" "applied" "$dir (subject-call count $before -> $after)"
	return 0
}

# --- Tool resolution -----------------------------------------------------------
# tsc is not on the devShell PATH; the repository's own pinned TypeScript
# dependency (package.json: typescript ^5.9.0) is the compiler this runner
# checks the generated TypeScript with. Its resolved path and digest are
# recorded in the identity stage.
BASE_TSC="/home/losses/Development/tq-workspace/boring/node_modules/.bin/tsc"
TSC="${TSC:-$(command -v tsc 2>/dev/null || printf '%s' "$BASE_TSC")}"
TSC_REAL="$(readlink -f "$TSC" 2>/dev/null || printf '%s' "$TSC")"

# --- Declared stage membership ------------------------------------------------
for s in identity-rev identity-status identity-date identity-haxe identity-tsc identity-node \
	identity-kotlinc identity-java identity-dart identity-rustc identity-swiftc identity-toolpaths \
	input-hashes-before probe \
	gen-ts gen-kotlin gen-dart gen-rust gen-swift \
	ts-driver-copy ts-typecheck ts-emit ts-run-promoted ts-run-source-control \
	mutate-ts ts-typecheck-mut ts-emit-mut ts-run-mut-promoted \
	kotlin-driver-copy kotlin-build-whole kotlin-build kotlin-run-promoted kotlin-run-source-control \
	mutate-kotlin kotlin-build-mut kotlin-run-mut-promoted \
	dart-driver-copy dart-run-promoted dart-run-source-control mutate-dart dart-run-mut-promoted \
	rust-build rust-build-harness rust-run-promoted rust-run-source-control rust-retain \
	mutate-rust rust-build-mut rust-build-harness-mut rust-run-mut-promoted rust-retain-mut \
	swift-build swift-run-promoted \
	snippets input-hashes-after; do
	declare_stage "$s"
done

# --- Identity ------------------------------------------------------------------
run_stage identity-rev git rev-parse HEAD
run_stage identity-status git status --short
run_stage identity-date date -u +%Y-%m-%dT%H:%M:%SZ
run_stage identity-haxe haxe --version
run_stage identity-tsc "$TSC" --version
run_stage identity-node node --version
run_stage identity-kotlinc kotlinc -version
run_stage identity-java java -version
run_stage identity-dart dart --version
run_stage identity-rustc rustc --version
run_stage identity-swiftc swiftc --version
run_stage identity-toolpaths bash -c '
	printf "worktree %s\n" "$PWD"
	printf "haxe %s\n" "$(command -v haxe)"
	printf "tsc %s\n" "$1"
	printf "tsc-real %s\n" "$2"
	printf "tsc-sha256 %s\n" "$(sha256sum "$2" | cut -d" " -f1)"
	printf "node %s\n" "$(command -v node)"
	printf "kotlinc %s\n" "$(command -v kotlinc)"
	printf "java %s\n" "$(command -v java)"
	printf "dart %s\n" "$(command -v dart)"
	printf "rustc %s\n" "$(command -v rustc)"
	printf "swiftc %s\n" "$(command -v swiftc || printf "not found")"
' bash "$TSC" "$TSC_REAL"
{
	printf 'evidence root %s\n' "$PE_ROOT"
	printf 'run directory %s\n' "$RUN"
	printf 'worktree root %s\n' "$ROOT"
	printf 'fixture %s\n' "$HERE"
	printf 'runner %s\n' "$HERE/run.sh"
	printf 'tsc selected %s (real %s)\n' "$TSC" "$TSC_REAL"
} >"$RUN/identity.txt"

# --- Authored-input digests ----------------------------------------------------
INPUT_MANIFEST="$RUN/input-files.txt"
find packages/compiler tests/haxe/dc-promoted-eval -type f -print0 |
	LC_ALL=C sort -z | tr '\0' '\n' >"$INPUT_MANIFEST"

# The digest helper reads the manifest as a newline-separated list; the manifest
# is regenerated identically before and after the attempt, so a file added or
# removed under either input tree shows up as a manifest difference too.
run_stage input-hashes-before bash -c '
	cd "$1" || exit 2
	xargs -d "\n" sha256sum < "$2" > "$3"
' bash "$ROOT" "$INPUT_MANIFEST" "$RUN/input-hashes-before.sha256"
if [ "$LAST_RC" != "0" ]; then
	note "cannot digest the authored inputs before the attempt"
	set_verdict harness-defect
fi

# --- Structural probe ----------------------------------------------------------
run_stage probe haxe "$HERE/probe.hxml"
{
	grep -oE 'METHOD-PROBE owner=[^ ]+ scope=[^ ]+ calls=[0-9]+' "$ST"/*-probe/stdout || true
	grep -oE 'BLOCK-PROBE owner=[^ ]+ .*' "$ST"/*-probe/stdout || true
} >"$RUN/probe-lines.txt"
probe_method_calls() { # probe_method_calls <owner>
	sed -n "s/.*METHOD-PROBE owner=$1 scope=[^ ]* calls=\([0-9]*\).*/\1/p" "$RUN/probe-lines.txt" | head -n 1
}
probe_block_count() { # probe_block_count <owner>
	grep -c "BLOCK-PROBE owner=$1 " "$RUN/probe-lines.txt"
}
probe_block_init_calls() { # probe_block_init_calls <owner> <index>
	grep "BLOCK-PROBE owner=$1 " "$RUN/probe-lines.txt" | sed -n "$2p" | sed -n 's/.*initCalls=\([0-9]*\).*/\1/p'
}
{
	printf 'structural probe assertions\n'
	printf 'EvalProbe.promotedOnce calls=%s (expect 1)\n' "$(probe_method_calls dcpe.EvalProbe.promotedOnce)"
	printf 'EvalProbe.promotedOnce promoted blocks=%s (expect 1)\n' "$(probe_block_count dcpe.EvalProbe.promotedOnce)"
	printf 'EvalProbe.promotedOnce block 1 initCalls=%s (expect 1)\n' "$(probe_block_init_calls dcpe.EvalProbe.promotedOnce 1)"
	printf 'DoubleEvalControl.doubleOnce calls=%s (expect 2)\n' "$(probe_method_calls dcpe.DoubleEvalControl.doubleOnce)"
	printf 'DoubleEvalControl.doubleOnce promoted blocks=%s (expect 2)\n' "$(probe_block_count dcpe.DoubleEvalControl.doubleOnce)"
	printf 'DoubleEvalControl.doubleOnce block 1 initCalls=%s (expect 1)\n' "$(probe_block_init_calls dcpe.DoubleEvalControl.doubleOnce 1)"
	printf 'DoubleEvalControl.doubleOnce block 2 initCalls=%s (expect 1)\n' "$(probe_block_init_calls dcpe.DoubleEvalControl.doubleOnce 2)"
} >"$RUN/probe-assertions.txt"
if [ "$(probe_method_calls dcpe.EvalProbe.promotedOnce)" != "1" ] ||
	[ "$(probe_block_count dcpe.EvalProbe.promotedOnce)" != "1" ] ||
	[ "$(probe_block_init_calls dcpe.EvalProbe.promotedOnce 1)" != "1" ]; then
	note "the typed AST of dcpe.EvalProbe.promotedOnce is not the expected single promoted block"
	set_verdict harness-defect
fi

# --- Generation -----------------------------------------------------------------
GEN_TARGETS="ts kotlin dart rust swift"
for t in $GEN_TARGETS; do
	run_stage "gen-$t" haxe "$HERE/gen/$t.hxml" -D "$t-output=$RUN/$t-gen" -D "$t-test-output=$RUN/$t-gen-tests"
	if [ "$LAST_RC" != "0" ]; then
		note "generation for $t was rejected (exit $LAST_RC); see $(basename "$LAST_DIR")/stderr"
		set_verdict generation-failed
	fi
done

gs() { [ "$(cat "$ST"/*-gen-$1/status 2>/dev/null | head -n 1)" = "0" ]; }

# --- TypeScript -----------------------------------------------------------------
TS_GEN="$RUN/ts-gen"
TS_MUT_GEN="$RUN/ts-gen-mut"
TS_JS="$RUN/ts-js"
TS_MUT_JS="$RUN/ts-js-mut"
if gs ts; then
	run_stage ts-driver-copy cp "$HERE/native/driver.ts" "$TS_GEN/driver.ts"
	sha256sum "$TS_GEN/driver.ts" >>"$RUN/harness-copies.sha256" 2>/dev/null || true
	TSC_COMMON="--strict --target ES2022 --moduleResolution node --allowImportingTsExtensions --rewriteRelativeImportExtensions"
	run_stage ts-typecheck "$TSC" --noEmit --strict --target ES2022 --module ES2022 --moduleResolution node --allowImportingTsExtensions "$TS_GEN/driver.ts"
	if [ "$LAST_RC" != "0" ]; then
		note "tsc rejected the generated TypeScript tree (exit $LAST_RC)"
		set_verdict generation-failed
	fi
	# shellcheck disable=SC2086
	run_stage ts-emit "$TSC" $TSC_COMMON --outDir "$TS_JS" --rootDir "$TS_GEN" "$TS_GEN/driver.ts"
	if [ "$LAST_RC" = "0" ]; then
		run_case ts-run-promoted positive 'case=promoted acc=21 callCount=1' node "$TS_JS/driver.js" promoted
		run_case ts-run-source-control control 'case=double acc=42 callCount=2' node "$TS_JS/driver.js" double
	else
		mark_unreached ts-emit "$LAST_RC" ts-run-promoted ts-run-source-control
		set_verdict generation-failed
	fi
	if mutate ts ts-gen 'dcpe/EvalProbe.ts' 'EvalProbe\.nextKind\(\);' \
		's|^      const _g = EvalProbe.nextKind();$|      const _g = EvalProbe.nextKind();\n      EvalProbe.nextKind();|'; then
		run_stage ts-typecheck-mut "$TSC" --noEmit --strict --target ES2022 --module ES2022 --moduleResolution node --allowImportingTsExtensions "$TS_MUT_GEN/driver.ts"
		if [ "$LAST_RC" != "0" ]; then
			note "tsc rejected the mutated TypeScript tree (exit $LAST_RC); the control is void"
			set_verdict harness-defect
		fi
		# shellcheck disable=SC2086
		run_stage ts-emit-mut "$TSC" $TSC_COMMON --outDir "$TS_MUT_JS" --rootDir "$TS_MUT_GEN" "$TS_MUT_GEN/driver.ts"
		if [ "$LAST_RC" = "0" ]; then
			run_case ts-run-mut-promoted control 'case=promoted acc=21 callCount=2' node "$TS_MUT_JS/driver.js" promoted
		else
			mark_unreached ts-emit-mut "$LAST_RC" ts-run-mut-promoted
			set_verdict harness-defect
		fi
	else
		mark_unreached mutate-ts failed ts-typecheck-mut ts-emit-mut ts-run-mut-promoted
	fi
else
	mark_unreached gen-ts "$(cat "$ST"/*-gen-ts/status 2>/dev/null | head -n 1)" \
		ts-driver-copy ts-typecheck ts-emit ts-run-promoted ts-run-source-control \
		mutate-ts ts-typecheck-mut ts-emit-mut ts-run-mut-promoted
fi

# --- Kotlin ---------------------------------------------------------------------
KOTLIN_GEN="$RUN/kotlin-gen"
KOTLIN_MUT_GEN="$RUN/kotlin-gen-mut"
KOTLIN_JAR="$BUILD/kotlin.jar"
KOTLIN_MUT_JAR="$BUILD/kotlin-mut.jar"
if gs kotlin; then
	run_stage kotlin-driver-copy cp "$HERE/native/Main.kt" "$KOTLIN_GEN/Main.kt"
	sha256sum "$KOTLIN_GEN/Main.kt" >>"$RUN/harness-copies.sha256" 2>/dev/null || true
	find "$KOTLIN_GEN" -name '*.kt' | LC_ALL=C sort >"$RUN/kotlin-sources-all.txt"
	grep -v '/runtime/test/' "$RUN/kotlin-sources-all.txt" >"$RUN/kotlin-sources-build.txt"
	# The emitted test host refers to a runtime symbol the tree does not carry,
	# so the whole-tree compile is recorded as an observation and the library
	# build excludes runtime/test only.
	# shellcheck disable=SC2046
	run_stage kotlin-build-whole kotlinc -Xallow-kotlin-package $(cat "$RUN/kotlin-sources-all.txt") -include-runtime -d "$BUILD/kotlin-whole.jar"
	if [ "$LAST_RC" != "0" ]; then
		note "the emitted Kotlin tree does not compile as a whole; the library build excludes runtime/test (see kotlin-build-whole)"
	fi
	# shellcheck disable=SC2046
	run_stage kotlin-build kotlinc -Xallow-kotlin-package $(cat "$RUN/kotlin-sources-build.txt") -include-runtime -d "$KOTLIN_JAR"
	if [ "$LAST_RC" = "0" ]; then
		run_case kotlin-run-promoted positive 'case=promoted acc=21 callCount=1' java -cp "$KOTLIN_JAR" MainKt promoted
		run_case kotlin-run-source-control control 'case=double acc=42 callCount=2' java -cp "$KOTLIN_JAR" MainKt double
	else
		mark_unreached kotlin-build "$LAST_RC" kotlin-run-promoted kotlin-run-source-control
		set_verdict generation-failed
	fi
	if mutate kotlin kotlin-gen 'dcpe/EvalProbe.kt' 'EvalProbe\.nextKind\(\)' \
		's|^            val _g = EvalProbe.nextKind()$|            val _g = EvalProbe.nextKind()\n            EvalProbe.nextKind()|'; then
		# shellcheck disable=SC2046
		run_stage kotlin-build-mut kotlinc -Xallow-kotlin-package \
			$(grep -v '/runtime/test/' <(find "$KOTLIN_MUT_GEN" -name '*.kt' | LC_ALL=C sort)) -include-runtime -d "$KOTLIN_MUT_JAR"
		if [ "$LAST_RC" = "0" ]; then
			run_case kotlin-run-mut-promoted control 'case=promoted acc=21 callCount=2' java -cp "$KOTLIN_MUT_JAR" MainKt promoted
		else
			mark_unreached kotlin-build-mut "$LAST_RC" kotlin-run-mut-promoted
			set_verdict harness-defect
		fi
	else
		mark_unreached mutate-kotlin failed kotlin-build-mut kotlin-run-mut-promoted
	fi
else
	mark_unreached gen-kotlin "$(cat "$ST"/*-gen-kotlin/status 2>/dev/null | head -n 1)" \
		kotlin-driver-copy kotlin-build-whole kotlin-build kotlin-run-promoted kotlin-run-source-control \
		mutate-kotlin kotlin-build-mut kotlin-run-mut-promoted
fi

# --- Dart -----------------------------------------------------------------------
DART_GEN="$RUN/dart-gen"
if gs dart; then
	run_stage dart-driver-copy cp "$HERE/native/driver.dart" "$DART_GEN/driver.dart"
	sha256sum "$DART_GEN/driver.dart" >>"$RUN/harness-copies.sha256" 2>/dev/null || true
	run_case dart-run-promoted positive 'case=promoted acc=21 callCount=1' dart run "$DART_GEN/driver.dart" promoted
	run_case dart-run-source-control control 'case=double acc=42 callCount=2' dart run "$DART_GEN/driver.dart" double
	if mutate dart dart-gen 'lib/dcpe/eval_probe.dart' 'nextKind\(\);' \
		's|^    final _g = nextKind();$|    final _g = nextKind();\n    nextKind();|'; then
		run_case dart-run-mut-promoted control 'case=promoted acc=21 callCount=2' dart run "$RUN/dart-gen-mut/driver.dart" promoted
	else
		mark_unreached mutate-dart failed dart-run-mut-promoted
	fi
else
	mark_unreached gen-dart "$(cat "$ST"/*-gen-dart/status 2>/dev/null | head -n 1)" \
		dart-driver-copy dart-run-promoted dart-run-source-control mutate-dart dart-run-mut-promoted
fi

# --- Rust -----------------------------------------------------------------------
RUST_GEN="$RUN/rust-gen"
RUST_LIB="$RUST_BUILD/libpe.rlib"
RUST_HARNESS="$RUST_BUILD/harness"
RUST_MUT_LIB="$RUST_BUILD/libpe-mut.rlib"
RUST_MUT_HARNESS="$RUST_BUILD/harness-mut"
if gs rust; then
	run_stage rust-build rustc --edition=2024 --crate-type lib --crate-name pe -o "$RUST_LIB" "$RUST_GEN/lib.rs"
	if [ "$LAST_RC" = "0" ]; then
		run_stage rust-build-harness rustc --edition=2024 -o "$RUST_HARNESS" "$HERE/native/harness.rs" --extern "pe=$RUST_LIB"
		if [ "$LAST_RC" = "0" ]; then
			run_case rust-run-promoted positive 'case=promoted acc=21 callCount=1' "$RUST_HARNESS" promoted
			run_case rust-run-source-control control 'case=double acc=42 callCount=2' "$RUST_HARNESS" double
			run_stage rust-retain cp "$RUST_HARNESS" "$RUST_LIB" "$RUN/"
			sha256sum "$RUST_LIB" "$RUST_HARNESS" >>"$RUN/rust-digests.sha256"
			printf 'rust link products were built in %s and copied into %s for retention\n' \
				"$RUST_BUILD" "$RUN" >"$RUN/rust-build-location.txt"
		else
			mark_unreached rust-build-harness "$LAST_RC" rust-run-promoted rust-run-source-control rust-retain
			set_verdict generation-failed
		fi
	else
		mark_unreached rust-build "$LAST_RC" rust-build-harness rust-run-promoted rust-run-source-control rust-retain
		set_verdict generation-failed
	fi
	if mutate rust rust-gen 'dcpe/eval_probe.rs' 'EvalProbe::eval_probe_next_kind\(\)' \
		's|^            let _g = EvalProbe::eval_probe_next_kind();$|            let _g = EvalProbe::eval_probe_next_kind();\n            EvalProbe::eval_probe_next_kind();|'; then
		run_stage rust-build-mut rustc --edition=2024 --crate-type lib --crate-name pe -o "$RUST_MUT_LIB" "$RUN/rust-gen-mut/lib.rs"
		if [ "$LAST_RC" = "0" ]; then
			run_stage rust-build-harness-mut rustc --edition=2024 -o "$RUST_MUT_HARNESS" "$HERE/native/harness.rs" --extern "pe=$RUST_MUT_LIB"
			if [ "$LAST_RC" = "0" ]; then
				run_case rust-run-mut-promoted control 'case=promoted acc=21 callCount=2' "$RUST_MUT_HARNESS" promoted
				run_stage rust-retain-mut cp "$RUST_MUT_HARNESS" "$RUST_MUT_LIB" "$RUN/"
				sha256sum "$RUST_MUT_LIB" "$RUST_MUT_HARNESS" >>"$RUN/rust-digests.sha256"
			else
				mark_unreached rust-build-harness-mut "$LAST_RC" rust-run-mut-promoted rust-retain-mut
				set_verdict harness-defect
			fi
		else
			mark_unreached rust-build-mut "$LAST_RC" rust-build-harness-mut rust-run-mut-promoted rust-retain-mut
			set_verdict harness-defect
		fi
	else
		mark_unreached mutate-rust failed rust-build-mut rust-build-harness-mut rust-run-mut-promoted rust-retain-mut
	fi
else
	mark_unreached gen-rust "$(cat "$ST"/*-gen-rust/status 2>/dev/null | head -n 1)" \
		rust-build rust-build-harness rust-run-promoted rust-run-source-control rust-retain \
		mutate-rust rust-build-mut rust-build-harness-mut rust-run-mut-promoted rust-retain-mut
fi

# --- Swift (expected to be blocked by the pinned toolchain wrapper) -------------
if gs swift; then
	# Package.swift is the emitted SwiftPM manifest, not a compilable library
	# source, so the library invocation lists only the module sources.
	# shellcheck disable=SC2046
	run_stage swift-build swiftc -emit-library -emit-module \
		$(find "$RUN/swift-gen" -name '*.swift' -not -name 'Package.swift' | LC_ALL=C sort) \
		-module-name PEProbe -o "$BUILD/libPEProbe.so"
	if [ "$LAST_RC" != "0" ]; then
		printf 'swiftc: the pinned wrapper failed before compiling anything (exit %s); see stages/*-swift-build/stderr\n' "$LAST_RC" \
			>>"$RUN/environment-not-reached.txt"
		note "swift-build did not reach the compiler: the pinned swiftc wrapper failed before compiling anything (see stages/*-swift-build/stderr)"
		mark_unreached swift-build "toolchain-blocked" swift-run-promoted
	else
		# The environment let swiftc run, which this environment was not
		# expected to do; no Swift driver was authored or verified here, so the
		# run stays explicitly not measured rather than silently claimed.
		note "swiftc ran, which this environment was not expected to allow; no Swift driver is authored for this fixture, so no Swift runtime observation exists"
		mark_unreached swift-build "no-verified-driver" swift-run-promoted
	fi
else
	mark_unreached gen-swift "$(cat "$ST"/*-gen-swift/status 2>/dev/null | head -n 1)" swift-build swift-run-promoted
fi

run_stage snippets bash "$HERE/snippets.sh" "$RUN"
if [ "$LAST_RC" != "0" ]; then
	note "cannot extract the generated subject snippets (exit $LAST_RC)"
	set_verdict harness-defect
fi

# --- Input digests after ---------------------------------------------------------
run_stage input-hashes-after bash -c '
	cd "$1" || exit 2
	xargs -d "\n" sha256sum < "$2" > "$3"
' bash "$ROOT" "$INPUT_MANIFEST" "$RUN/input-hashes-after.sha256"
after_rc="$LAST_RC"
if [ "$after_rc" != "0" ]; then
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

# --- Stage membership ------------------------------------------------------------
sort "$EXPECTED" -o "$RUN/expected-stages-sorted.txt"
cut -f1 "$STATUS" | sort -o "$RUN/observed-stages.txt"
comm -3 "$RUN/expected-stages-sorted.txt" "$RUN/observed-stages.txt" >"$RUN/stage-diff.txt"
if [ -s "$RUN/stage-diff.txt" ]; then
	note "the recorded stage set differs from the declared set; see stage-diff.txt"
	set_verdict harness-defect
fi
# A declared stage that never ran still keeps an explicit row.
while IFS= read -r s; do
	grep -q "^$s${TAB}" "$STATUS" || record_row "$s" "not-reached" "no row was written"
done <"$RUN/expected-stages-sorted.txt"

# --- Summary ---------------------------------------------------------------------
awk -F"$TAB" '$2 == "not-reached" || $2 == "environment-not-reached" || $2 == "failed" { print $1"\t"$2"\t"$3 }' \
	"$STATUS" >"$RUN/not-reached.tsv"
awk -F"$TAB" '$2 ~ /^[0-9]+$/ && $2 != "0" { print $1"\t"$2 }' "$STATUS" >"$RUN/nonzero-exits.tsv"
: >"$RUN/unexpected-nonzero-exits.txt"
EXPECTED_NONZERO="identity-swiftc kotlin-build-whole swift-build"
while IFS="$TAB" read -r s code; do
	case " $EXPECTED_NONZERO " in
	*" $s "*) : ;;
	*) printf '%s\t%s\n' "$s" "$code" >>"$RUN/unexpected-nonzero-exits.txt" ;;
	esac
done <"$RUN/nonzero-exits.tsv"
if [ -s "$RUN/unexpected-nonzero-exits.txt" ]; then
	note "stages exited nonzero outside the declared set: $(tr '\n' ' ' <"$RUN/unexpected-nonzero-exits.txt")"
	set_verdict harness-defect
fi
{
	printf 'run directory %s\n' "$RUN"
	printf 'verdict %s\n' "$VERDICT"
	printf 'assertion %s\n' "$ASSERTION"
	printf 'positive observations %s control observations %s\n' "$POSITIVE_OBSERVED" "$CONTROL_OBSERVED"
	printf 'stages declared %s recorded %s\n' "$(wc -l <"$EXPECTED")" "$(wc -l <"$STATUS")"
	printf '\nnot reached or environment-blocked\n'
	cat "$RUN/not-reached.tsv"
	cat "$RUN/environment-not-reached.txt" 2>/dev/null || true
	printf '\nnonzero exits (observations)\n'
	cat "$RUN/nonzero-exits.tsv"
	printf '\nunexpected nonzero exits\n'
	cat "$RUN/unexpected-nonzero-exits.txt"
	printf '\nruntime observations\n'
	cat "$OBS"
	printf '\nfindings\n'
	cat "$FINDINGS"
	printf '\nidentity\n'
	cat "$RUN/identity.txt"
	printf '\nstructural probe assertions\n'
	cat "$RUN/probe-assertions.txt"
	printf '\nmutations\n'
	cat "$MUT"
	printf '\nstatus rows\n'
	cat "$STATUS"
	printf '\ninput trees\n'
	cat "$RUN/input-unchanged.txt"
} >"$RUN/summary.txt"

log "run directory $RUN"
log "verdict $VERDICT"
log "assertion $ASSERTION"
cat "$RUN/runtime-observations.tsv"
log "not reached"
cat "$RUN/not-reached.tsv"
[ "$VERDICT" = "complete" ] || exit 1
exit 0
