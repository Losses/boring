#!/usr/bin/env bash
# Durable generation and native runner for the container caller cases.
#
# One invocation allocates one fresh run directory and never rewrites an
# earlier one. Stages run inside the single invoking pinned environment and
# record shell-quoted argv, cwd, separated streams, and exit status.
#
# Verdict vocabulary:
#   harness-defect        setup, identity, hashing, or membership failure
#   observed-failure      a generated tree failed to compile or run natively
#   observed              every attempted native check succeeded
# Qualifier `unexecuted-work` marks stages recorded as not reached or blocked.
# Only harness-defect exits nonzero; observed failures are retained evidence.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/../../../support/stage-check.sh"
ROOT="$(cd "$HERE/../../../.." && pwd)"
cd "$ROOT" || exit 1
if [ "${IN_NIX_SHELL:-}" = "" ]; then
	printf 'run this runner through: nix develop -c bash tests/haxe/source-container-policy/gen/run.sh\n'
	exit 1
fi
if ! mkdir -p out/source-container-policy; then
	printf 'evidence parent creation failed\n'
	exit 1
fi
if ! RUN="$(mktemp -d out/source-container-policy/gen-XXXXXX)"; then
	printf 'run directory allocation failed\n'
	exit 1
fi
RUN="$(cd "$RUN" && pwd)"

log() {
	printf '%s\n' "$1"
}

TAB="$(printf '\t')"
STATUS="$RUN/status.tsv"
printf 'stage%sexpected%sobserved%sproducer\n' "$TAB" "$TAB" "$TAB" >"$STATUS"
EXPECTED="$RUN/expected-stages.txt"
: >"$EXPECTED"
DIAGNOSTICS="$RUN/diagnostics.txt"
printf 'stage%sexpected-diagnostic%sfound\n' "$TAB" "$TAB" >"$DIAGNOSTICS"
VERDICT=observed
UNEXECUTED=0
NATIVE_FAILURES=0
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
		UNEXECUTED=$((UNEXECUTED + 1))
	done
}

# stage <name> <expected> <command...>; returns the producer status so the
# caller captures the real status and never the negation's zero.
stage() {
	local name=$1 expected=$2
	shift 2
	{
		printf 'interpreter bash inside the invoking nix develop environment\n'
		printf 'cwd %s\n' "$ROOT"
		printf 'argv'
		printf ' %q' "$@"
		printf '\n'
	} >"$RUN/$name.argv"
	"$@" >"$RUN/$name.stdout" 2>"$RUN/$name.stderr"
	local observed=$?
	record "$name" "$expected" "$observed" "$name"
	return "$observed"
}

expect_diagnostic() {
	local stage=$1 fragment=$2
	if grep -qF -- "$fragment" "$RUN/$stage.stderr"; then
		printf '%s%s%s%syes\n' "$stage" "$TAB" "$fragment" "$TAB" >>"$DIAGNOSTICS"
		return 0
	fi
	printf '%s%s%s%sNO\n' "$stage" "$TAB" "$fragment" "$TAB" >>"$DIAGNOSTICS"
	return 1
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
		find packages/compiler tests/haxe/source-container-policy -type f -print0
		printf '%s\0' README.md tests/support/stage-check.sh
	} | sort -z >"$listing" || return 1
	xargs -0 sha256sum <"$listing" >"$output" || return 1
}

write_compiler_hxml() {
	local source=$1 output=$2 compiler=$3
	awk -v compiler="$compiler" '
		$0 == "-lib boring" { next }
		$1 == "-cp" && $2 ~ /^packages\/compiler(\/|$)/ {
			sub(/^packages\/compiler/, compiler, $2)
			print "-cp " $2
			next
		}
		{ print }
	' "$source" >"$output"
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

snapshot_manifest() {
	local tree=$1 output=$2
	local listing="$output.files"
	find "$tree" -type f -print0 | sort -z >"$listing" || return 1
	xargs -0 sha256sum <"$listing" >"$output" || return 1
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

# ------------------------------------------------------------------ identity
identity_step utc date -u +%Y-%m-%dT%H:%M:%SZ
printf 'worktree %s\n' "$ROOT" >>"$RUN/identity.txt"
identity_step base git rev-parse HEAD
identity_step changed git status --porcelain
identity_step haxe-version haxe --version
identity_step bun-version bun --version
identity_step rustc-version rustc --version
identity_step kotlinc-version kotlinc -version
identity_step swiftc-version swiftc --version
identity_step dart-version dart --version
identity_step resolved-boring-library haxelib path boring
identity_step authored-source-hashes sha256sum tests/support/stage-check.sh \
	tests/haxe/source-container-policy/gen/*.hxml \
	tests/haxe/source-container-policy/gen/*.sh tests/haxe/source-container-policy/native/*.sh \
	tests/haxe/source-container-policy/native/expected/* tests/haxe/source-container-policy/scp/*.hx \
	tests/haxe/source-container-policy/scp/face/*.hx tests/haxe/source-container-policy/run.hxml
expect_stage input-hashes-before
if input_manifest "$RUN/input-hashes-before.txt"; then
	record input-hashes-before zero 0 input-manifest
else
	record input-hashes-before zero 1 input-manifest
	VERDICT=harness-defect
	IDENTITY_FAILURES=$((IDENTITY_FAILURES + 1))
fi
expect_stage identity-toolchain
record identity-toolchain zero "$IDENTITY_FAILURES" "identity-steps-and-input-hash"
expect_stage identity-compiler-inputs

# ------------------------------------------------------- stage declarations
expect_stage baseline-prepare
expect_stage compiler-snapshot-check
expect_stage routing-candidate
expect_stage routing-baseline
expect_stage probe-compile
expect_stage probe-run
expect_stage input-hashes-after
expect_stage compiler-snapshot-integrity
for target in ts kotlin rust swift dart; do
	expect_stage "gen-candidate-$target"
	expect_stage "gen-baseline-$target"
	expect_stage "diff-raw-$target"
	expect_stage "diff-outputs-$target"
	expect_stage "gen-boundary-candidate-$target"
	expect_stage "gen-boundary-baseline-$target"
	expect_stage "diff-boundary-$target"
	expect_stage "native-compile-candidate-$target"
	expect_stage "native-run-candidate-$target"
	expect_stage "native-expect-candidate-$target"
	expect_stage "native-compile-baseline-$target"
	expect_stage "native-run-baseline-$target"
	expect_stage "native-expect-baseline-$target"
done

if [ "$IDENTITY_FAILURES" != "0" ]; then
	remaining=(identity-compiler-inputs baseline-prepare compiler-snapshot-check routing-candidate routing-baseline probe-compile probe-run)
	for target in ts kotlin rust swift dart; do
		remaining+=("gen-candidate-$target" "gen-baseline-$target" "diff-raw-$target" "diff-outputs-$target" \
			"gen-boundary-candidate-$target" "gen-boundary-baseline-$target" "diff-boundary-$target" \
			"native-compile-candidate-$target" "native-run-candidate-$target" "native-expect-candidate-$target" \
			"native-compile-baseline-$target" "native-run-baseline-$target" "native-expect-baseline-$target")
	done
	remaining+=(input-hashes-after)
	remaining+=(compiler-snapshot-integrity)
	not_reached identity-toolchain "$IDENTITY_FAILURES" "${remaining[@]}"
	VERDICT=harness-defect
	stage_check "$STATUS" "$EXPECTED" "$RUN/membership-findings.txt" || true
	{
		printf 'run directory %s\nverdict harness-defect\n' "$RUN"
		cat "$STATUS"
	} >"$RUN/summary.txt"
	cat "$RUN/summary.txt"
	exit 1
fi
record identity-compiler-inputs data 0 input-hashes-before

# -------------------------------------------------- fixed compiler snapshots
st=0
stage baseline-prepare zero bash -c '
	set -e
	candidate="'"$RUN"'/candidate/packages/compiler"
	baseline="'"$RUN"'/baseline/packages/compiler"
	mkdir -p "$candidate" "$baseline"
	cp -a packages/compiler/. "$candidate"/
	cp -a "$candidate"/. "$baseline"/
	git show c762b8ed:packages/compiler/StaticFieldHelper.hx >"$baseline"/StaticFieldHelper.hx
	rm -f "$baseline"/SourceContainerAnalysis.hx
'
st=$?
if [ "$st" != "0" ]; then
	not_reached baseline-prepare "$st" compiler-snapshot-check routing-candidate routing-baseline \
		probe-compile probe-run
	for target in ts kotlin rust swift dart; do
		not_reached baseline-prepare "$st" "gen-candidate-$target" "gen-baseline-$target" \
			"diff-raw-$target" "diff-outputs-$target" "gen-boundary-candidate-$target" \
			"gen-boundary-baseline-$target" "diff-boundary-$target" \
			"native-compile-candidate-$target" "native-run-candidate-$target" "native-expect-candidate-$target" \
			"native-compile-baseline-$target" "native-run-baseline-$target" "native-expect-baseline-$target"
	done
	after_status=0
	input_manifest "$RUN/input-hashes-after.txt" || after_status=$?
	if [ "$after_status" = "0" ] && cmp -s "$RUN/input-hashes-before.txt" "$RUN/input-hashes-after.txt"; then
		record input-hashes-after data 0 baseline-prepare
	else
		record input-hashes-after data 1 baseline-prepare
		VERDICT=harness-defect
	fi
	not_reached baseline-prepare "$st" compiler-snapshot-integrity
	VERDICT=harness-defect
	stage_check "$STATUS" "$EXPECTED" "$RUN/membership-findings.txt" || true
	{
		printf 'run directory %s\n' "$RUN"
		printf 'verdict %s\n' "$VERDICT"
		printf 'baseline preparation failed; no stage is comparison evidence\n'
		cat "$STATUS"
	} >"$RUN/summary.txt"
	cat "$RUN/baseline-prepare.stderr"
	log "verdict harness-defect (baseline preparation)"
	exit 1
fi
BASE="$RUN/baseline/packages/compiler"
CANDIDATE="$RUN/candidate/packages/compiler"
snapshot_manifest "$CANDIDATE" "$RUN/candidate-snapshot-before.txt" || VERDICT=harness-defect
snapshot_manifest "$BASE" "$RUN/baseline-snapshot-before.txt" || VERDICT=harness-defect
record_hash baseline-prepare candidate-helper "$CANDIDATE/StaticFieldHelper.hx"
record_hash baseline-prepare candidate-analyzer "$CANDIDATE/SourceContainerAnalysis.hx"
record_hash baseline-prepare baseline-helper "$BASE/StaticFieldHelper.hx"

# Baseline entry for the routing check: the compiler class path points at the
# snapshot, so verbose module paths show which tree each generation loads.
write_compiler_hxml "$HERE/ts.hxml" "$RUN/ts-candidate.hxml" "$CANDIDATE"
write_compiler_hxml "$HERE/ts.hxml" "$RUN/ts-baseline.hxml" "$BASE"
record_hash routing-candidate input-hxml "$RUN/ts-candidate.hxml"
record_hash routing-baseline input-hxml "$RUN/ts-baseline.hxml"

# Snapshot relationship: the copy may differ from the original only in the
# two declared files; any other difference is a harness defect.
diff -rq "$CANDIDATE" "$BASE" >"$RUN/compiler-snapshot-diff.txt" 2>&1
record compiler-snapshot-check data "$?" baseline-prepare
record_hash compiler-snapshot-check candidate-helper "$CANDIDATE/StaticFieldHelper.hx"
record_hash compiler-snapshot-check baseline-helper "$BASE/StaticFieldHelper.hx"
record_hash compiler-snapshot-check candidate-analyzer "$CANDIDATE/SourceContainerAnalysis.hx"
if grep -qF "SourceContainerAnalysis.hx" "$RUN/compiler-snapshot-diff.txt" \
	&& grep -qF "StaticFieldHelper.hx" "$RUN/compiler-snapshot-diff.txt" \
	&& [ "$(wc -l <"$RUN/compiler-snapshot-diff.txt")" = "2" ]; then
	log "compiler snapshot differs only in the two declared files"
else
	printf 'compiler snapshot differs beyond the declared files\n' >>"$RUN/compiler-snapshot-diff.txt.unexpected"
	VERDICT=harness-defect
fi

# Routing evidence: verbose module paths show which compiler tree each
# generation actually loads.
stage routing-candidate data haxe -v "$RUN/ts-candidate.hxml" \
	-D ts-output="$RUN/routing-candidate/gen" -D ts-test-output="$RUN/routing-candidate/gen-tests" --no-output
stage routing-baseline data haxe -v "$RUN/ts-baseline.hxml" \
	-D ts-output="$RUN/routing-baseline/gen" -D ts-test-output="$RUN/routing-baseline/gen-tests" --no-output
cat "$RUN/routing-candidate.stdout" "$RUN/routing-candidate.stderr" >"$RUN/routing-candidate.all"
cat "$RUN/routing-baseline.stdout" "$RUN/routing-baseline.stderr" >"$RUN/routing-baseline.all"
{
	printf 'candidate frozen snapshot class paths: '
	grep -c "packages/compiler" "$RUN/routing-candidate.all" || true
	printf 'baseline class paths naming the snapshot compiler: '
	grep -c "baseline/packages/compiler" "$RUN/routing-baseline.all" || true
	printf 'candidate class paths naming the live compiler: '
	grep -c "$ROOT/packages/compiler" "$RUN/routing-candidate.all" || true
} >"$RUN/routing.paths"
if ! grep -qF "$CANDIDATE" "$RUN/routing-candidate.all" \
	|| grep -qF "$ROOT/packages/compiler" "$RUN/routing-candidate.all" \
	|| ! grep -qF "$BASE" "$RUN/routing-baseline.all"; then
	VERDICT=harness-defect
	printf 'verbose routing did not prove snapshot-only class paths\n' >>"$RUN/routing.paths"
fi

# ------------------------------------------------------------- source probe
# The source fact check runs in this attempt with its own exclusive output.
st=0
sed "s#^-cp packages/compiler\$#-cp $CANDIDATE#" tests/haxe/source-container-policy/run.hxml >"$RUN/probe.hxml"
record_hash probe-compile input-hxml "$RUN/probe.hxml"
record_hash probe-compile input tests/haxe/source-container-policy/run.hxml
stage probe-compile zero haxe "$RUN/probe.hxml" -js "$RUN/probe/check.js"
st=$?
if [ "$st" != "0" ]; then
	not_reached probe-compile "$st" probe-run
	VERDICT=harness-defect
else
	record_hash probe-compile output "$RUN/probe/check.js"
fi
if [ -f "$RUN/probe/check.js" ]; then
	st=0
	stage probe-run zero bun "$RUN/probe/check.js"
	st=$?
	if [ "$st" != "0" ]; then
		# A probe mismatch or program failure reports the analyzer and its
		# authored expectations.
		VERDICT=observed-failure
		NATIVE_FAILURES=$((NATIVE_FAILURES + 1))
	fi
fi

# --------------------------------------------------- per target, both sides
for target in ts kotlin rust swift dart; do
	case "$target" in
	ts) display="TypeScript" ;;
	kotlin) display="Kotlin" ;;
	rust) display="Rust" ;;
	swift) display="Swift" ;;
	dart) display="Dart" ;;
	esac
	write_compiler_hxml "$HERE/$target.hxml" "$RUN/$target-candidate.hxml" "$CANDIDATE"
	write_compiler_hxml "$HERE/$target.hxml" "$RUN/$target-baseline.hxml" "$BASE"
	source="$RUN/$target-candidate.hxml"
	boundary_candidate="$RUN/$target-boundary-candidate.hxml"
	sed "s#^scp.CallerCases\$#scp.CallerAliasBoundary#" "$source" >"$boundary_candidate"
	boundary_baseline="$RUN/$target-boundary-baseline.hxml"
	sed "s#^scp.CallerCases\$#scp.CallerAliasBoundary#" "$RUN/$target-baseline.hxml" >"$boundary_baseline"
	record_hash "gen-boundary-candidate-$target" input-hxml "$boundary_candidate"
	record_hash "gen-boundary-baseline-$target" input-hxml "$boundary_baseline"

	candidate_failed=0
	baseline_failed=0

	st=0
	stage "gen-candidate-$target" data haxe "$source" -D "$target-output=$RUN/$target/gen" \
		-D "$target-test-output=$RUN/$target/gen-tests"
	st=$?
	candidate_status=$st
	[ "$st" != "0" ] && candidate_failed=1
	if [ "$st" != "0" ]; then
		VERDICT=observed-failure
		NATIVE_FAILURES=$((NATIVE_FAILURES + 1))
	fi
	record_hash "gen-candidate-$target" input "$source"

	st=0
	stage "gen-baseline-$target" data haxe "$RUN/$target-baseline.hxml" \
		-D "$target-output=$RUN/$target-baseline/gen" \
		-D "$target-test-output=$RUN/$target-baseline/gen-tests"
	st=$?
	baseline_status=$st
	[ "$st" != "0" ] && baseline_failed=1
	if [ "$st" != "0" ]; then
		VERDICT=observed-failure
		NATIVE_FAILURES=$((NATIVE_FAILURES + 1))
	fi
	record_hash "gen-baseline-$target" input-hxml "$RUN/$target-baseline.hxml"

	# Boundary generations use identical authored alias input on both snapshots.
	stage "gen-boundary-candidate-$target" data haxe "$boundary_candidate" \
		-D "$target-output=$RUN/$target-boundary/gen" \
		-D "$target-test-output=$RUN/$target-boundary/gen-tests"
	bc=$?
	stage "gen-boundary-baseline-$target" data haxe "$boundary_baseline" \
		-D "$target-output=$RUN/$target-boundary-baseline/gen" \
		-D "$target-test-output=$RUN/$target-boundary-baseline/gen-tests"
	bb=$?
	if [ "$bc" = "0" ] || ! expect_diagnostic "gen-boundary-candidate-$target" "has no $display lowering"; then
		VERDICT=harness-defect
		printf 'candidate boundary failed to reach expected lowering diagnostic: status=%s\n' "$bc" \
			>>"$RUN/boundary-notes.txt"
	fi
	if [ "$bb" = "0" ] || ! expect_diagnostic "gen-boundary-baseline-$target" "V01 IteratorLoop"; then
		VERDICT=harness-defect
		printf 'baseline boundary failed to establish expected V01 source rejection: status=%s\n' "$bb" \
			>>"$RUN/boundary-notes.txt"
	else
		printf 'baseline boundary stopped at V01 before target lowering on %s\n' "$target" \
			>>"$RUN/boundary-notes.txt"
	fi
	if [ "$bc" = "0" ] && [ "$bb" = "0" ] && [ -d "$RUN/$target-boundary/gen" ] && [ -d "$RUN/$target-boundary-baseline/gen" ]; then
		diff -ru -x '_GeneratedFiles.txt' "$RUN/$target-boundary-baseline/gen" "$RUN/$target-boundary/gen" \
			>"$RUN/diff-boundary-$target.txt" 2>&1
		record "diff-boundary-$target" identical "$?" "gen-boundary-baseline-$target"
	else
		not_reached "gen-boundary-candidate-$target/$bb" "$bc/$bb" "diff-boundary-$target"
	fi

	# Raw difference keeps every byte, including generated metadata that
	# embeds the output directory. The output comparison excludes that one
	# metadata file; both records are kept and neither file is altered.
	if [ "$candidate_failed" != "0" ] || [ "$baseline_failed" != "0" ]; then
		blocker="candidate-status-$candidate_status baseline-status-$baseline_status"
		not_reached "generation-$target" "$blocker" "diff-raw-$target" "diff-outputs-$target"
		[ "$candidate_failed" != "0" ] || tree_manifest "$RUN/$target/gen" "$RUN/tree-candidate-$target.txt"
		[ "$baseline_failed" != "0" ] || tree_manifest "$RUN/$target-baseline/gen" "$RUN/tree-baseline-$target.txt"
	else
		stage "diff-raw-$target" data diff -ru "$RUN/$target-baseline/gen" "$RUN/$target/gen"
		tree_manifest "$RUN/$target/gen" "$RUN/tree-candidate-$target.txt"
		tree_manifest "$RUN/$target-baseline/gen" "$RUN/tree-baseline-$target.txt"
		diff -ru -x '_GeneratedFiles.txt' "$RUN/$target-baseline/gen" "$RUN/$target/gen" \
			>"$RUN/diff-outputs-$target.txt" 2>&1
		record "diff-outputs-$target" identical "$?" "gen-baseline-$target"
		if [ -s "$RUN/diff-outputs-$target.txt" ]; then
			VERDICT=observed-failure
		fi
	fi

	# Native compile and run stages per side, each with its own streams.
	for side in candidate baseline; do
		tree="$RUN/$target/gen"
		[ "$side" = "baseline" ] && tree="$RUN/$target-baseline/gen"
		compile_stage="native-compile-$side-$target"
		run_stage="native-run-$side-$target"
		expect_stage_name="native-expect-$side-$target"
		generation_status=$candidate_status
		[ "$side" = "baseline" ] && generation_status=$baseline_status
		if [ "$generation_status" != "0" ]; then
			not_reached "gen-$side-$target" "$generation_status" "$compile_stage" "$run_stage" "$expect_stage_name"
			continue
		fi

		st=0
		stage "$compile_stage" data bash "$HERE/../native/$target.sh" compile "$tree"
		st=$?
		record_hash "$compile_stage" input-manifest "$tree/../native-inputs.sha256"
		record_hash "$compile_stage" script "$HERE/../native/$target.sh"
		if [ "$st" != "0" ]; then
			# A compile failure of generated output is an observation.
			[ "$VERDICT" = "observed" ] && VERDICT=observed-failure
			NATIVE_FAILURES=$((NATIVE_FAILURES + 1))
			not_reached "$compile_stage" "$st" "$run_stage" "$expect_stage_name"
			continue
		fi
		case "$target" in
			ts) artifact="$tree/run-bundle.js" ;;
			kotlin) artifact="$tree/run.jar" ;;
			rust) artifact="$tree/target/debug/generated" ;;
			swift) artifact="$tree/run-bin" ;;
			dart) artifact="$tree/run.exe" ;;
		esac
		record_hash "$compile_stage" artifact "$artifact"
		# The artifact identity of a native stage is its tree manifest, which
		# digests every generated file the stage compiled.
		st=0
		stage "$run_stage" data bash "$HERE/../native/$target.sh" run "$tree"
		st=$?
		if [ "$st" != "0" ]; then
			[ "$VERDICT" = "observed" ] && VERDICT=observed-failure
			NATIVE_FAILURES=$((NATIVE_FAILURES + 1))
			not_reached "$run_stage" "$st" "$expect_stage_name"
			continue
		fi

		# Independent expectation of the authored operation's output.
		expect_file="$HERE/../native/expected/CallerCases.txt"
		run_output="$RUN/$target/native-output.txt"
		[ "$side" = "baseline" ] && run_output="$RUN/$target-baseline/native-output.txt"
		cp "$RUN/$run_stage.stdout" "$run_output"
		if diff -u "$expect_file" "$run_output" >"$RUN/$expect_stage_name.txt" 2>&1; then
			record "$expect_stage_name" identical 0 "$run_stage"
		else
			record "$expect_stage_name" differs 1 "$run_stage"
			VERDICT=observed-failure
		fi
	done
done

# ------------------------------------------------------------------- verdict
after_status=0
input_manifest "$RUN/input-hashes-after.txt" || after_status=$?
if [ "$after_status" = "0" ] && cmp -s "$RUN/input-hashes-before.txt" "$RUN/input-hashes-after.txt"; then
	record input-hashes-after data 0 input-hashes-before
else
	record input-hashes-after data 1 input-hashes-before
	VERDICT=harness-defect
	diff -u "$RUN/input-hashes-before.txt" "$RUN/input-hashes-after.txt" >"$RUN/input-hash-diff.txt" 2>&1 || true
fi
snapshot_manifest "$CANDIDATE" "$RUN/candidate-snapshot-after.txt" || after_status=1
snapshot_manifest "$BASE" "$RUN/baseline-snapshot-after.txt" || after_status=1
if [ "$after_status" = "0" ] \
	&& cmp -s "$RUN/candidate-snapshot-before.txt" "$RUN/candidate-snapshot-after.txt" \
	&& cmp -s "$RUN/baseline-snapshot-before.txt" "$RUN/baseline-snapshot-after.txt"; then
	record compiler-snapshot-integrity data 0 baseline-prepare
else
	record compiler-snapshot-integrity data 1 baseline-prepare
	VERDICT=harness-defect
fi
MEMBERSHIP="$RUN/membership-findings.txt"
stage_check "$STATUS" "$EXPECTED" "$MEMBERSHIP" || VERDICT=harness-defect

FINDINGS="$RUN/findings.txt"
{
	cat "$MEMBERSHIP"
	[ -f "$RUN/identity-failures.txt" ] && cat "$RUN/identity-failures.txt"
	[ -f "$RUN/hash-failures.txt" ] && cat "$RUN/hash-failures.txt"
	[ -f "$RUN/compiler-snapshot-diff.txt.unexpected" ] && cat "$RUN/compiler-snapshot-diff.txt.unexpected"
} >"$FINDINGS"
[ -s "$FINDINGS" ] && VERDICT=harness-defect

FINAL="$VERDICT"
QUALIFIERS=""
[ "$UNEXECUTED" != "0" ] && QUALIFIERS="unexecuted-work"
[ "$NATIVE_FAILURES" != "0" ] && QUALIFIERS="${QUALIFIERS:+$QUALIFIERS,}native-failures"

{
	printf 'run directory %s\n' "$RUN"
	printf 'verdict %s\n' "$FINAL"
	[ -z "$QUALIFIERS" ] || printf 'verdict qualifiers %s\n' "$QUALIFIERS"
	printf 'stages declared %s recorded %s\n' "$(wc -l <"$EXPECTED")" "$(( $(wc -l <"$STATUS") - 1 ))"
	printf 'findings\n'
	cat "$FINDINGS"
	printf 'status rows\n'
	cat "$STATUS"
	printf 'diagnostic checks\n'
	cat "$DIAGNOSTICS"
	printf 'identity\n'
	cat "$RUN/identity.txt"
	[ -f "$RUN/identity-failures.txt" ] && cat "$RUN/identity-failures.txt"
} >"$RUN/summary.txt"

cat "$FINDINGS"
log "run directory $RUN"
log "verdict $FINAL"
[ -z "$QUALIFIERS" ] || log "verdict qualifiers $QUALIFIERS"
[ "$FINAL" = "harness-defect" ] && exit 1
exit 0
