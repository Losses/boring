#!/usr/bin/env bash
# Durable replay runner for the place fixtures.
#
# One invocation allocates one fresh run directory with mktemp -d and never
# deletes or rewrites another directory. Every stage records shell-quoted
# argv, its interpreter and working directory, raw stdout and stderr, its
# exit status, and the sha256 of the inputs and outputs it produced.
# A stage runs only when its producer stage in the same attempt exited zero;
# every downstream stage of a failed producer receives an explicit
# not-reached row naming that producer. Each Rust variant owns its own
# directory, so no artifact of one variant can be executed as another.
# Expected source rejections and the deliberate program failure must carry
# their expected diagnostic or operation marker; an unrelated failure is a
# harness defect and fails the run.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
cd "$ROOT" || exit 1
# One pinned-environment boundary: the documented entry is
# `nix develop -c bash tests/haxe/place/run.sh`, and every stage
# runs inside that environment. An unpinned invocation exits with the entry
# command, so no toolchain result is recorded from an unknown environment.
if [ "${IN_NIX_SHELL:-}" = "" ]; then
	printf 'run this runner through: nix develop -c bash tests/haxe/place/run.sh\n'
	exit 1
fi
# shellcheck disable=SC1091
. "$HERE/../../support/stage-check.sh"
EVIDENCE=out/place
ALLOC_PARENT="$EVIDENCE/runs"
mkdir -p "$ALLOC_PARENT" || exit 1
if ! RUN="$(mktemp -d "$ALLOC_PARENT/place-XXXXXX")"; then
	printf 'run directory allocation failed\n'
	exit 1
fi

STATUS="$RUN/status.tsv"
TAB="$(printf '\t')"
printf 'stage%sexpected%sobserved%sproducer\n' "$TAB" "$TAB" "$TAB" >"$STATUS"
DIAGNOSTICS="$RUN/diagnostics.txt"
printf 'stage%sexpected-diagnostic%sfound\n' "$TAB" "$TAB" >"$DIAGNOSTICS"
EXPECTED_FILE="$RUN/expected-stages.txt"
: >"$EXPECTED_FILE"
VERDICT=recorded
ANY_UNREACHED=0
IDENTITY_FAILURES=0

# expect_stage <stage>
# Declares a required stage independently of what the run records.
expect_stage() {
	printf '%s\n' "$1" >>"$EXPECTED_FILE"
}

log() {
	printf '%s\n' "$1"
}

record() {
	printf '%s%s%s%s%s%s%s\n' "$1" "$TAB" "$2" "$TAB" "$3" "$TAB" "$4" >>"$STATUS"
	log "$1 expected=$2 observed=$3 producer=$4"
}

# attempt <stage> <expected> <command...>
# Runs the command in the invoking pinned environment. The documented entry
# is `nix develop -c bash tests/haxe/place/run.sh`, so the Nix
# boundary sits at that one entry and no stage nests a second Nix call.
attempt() {
	local stage=$1 expected=$2
	shift 2
	{
		printf 'interpreter bash inside the invoking nix develop environment\n'
		printf 'cwd %s\n' "$ROOT"
		printf 'argv'
		printf ' %q' "$@"
		printf '\n'
	} >"$RUN/$stage.argv"
	"$@" >"$RUN/$stage.stdout" 2>"$RUN/$stage.stderr"
	local observed=$?
	record "$stage" "$expected" "$observed" "$stage"
	return "$observed"
}

# mark_unreached <producer> <observed status> <dependent stage...>
mark_unreached() {
	local producer=$1 observed=$2
	shift 2
	local stage
	for stage in "$@"; do
		record "$stage" not-reached "producer-$producer-status-$observed" "$producer"
	done
}

expect_diagnostic() {
	local stage=$1 fragment=$2
	if grep -qF -- "$fragment" "$RUN/$stage.stderr"; then
		printf '%s%s%s%syes\n' "$stage" "$TAB" "$fragment" "$TAB" >>"$DIAGNOSTICS"
		return 0
	fi
	printf '%s%s%s%sNO\n' "$stage" "$TAB" "$fragment" "$TAB" >>"$DIAGNOSTICS"
	VERDICT=harness-defect
	log "$stage did not report the expected diagnostic: $fragment"
	return 1
}

# hash_file <stage> <role> <path>
# Records one digest line, or an explicit failure. A failed digest is a
# harness defect: the stage data stays, and the verdict cannot be success.
hash_file() {
	local stage=$1 role=$2 path=$3
	local line
	if ! line="$(sha256sum "$path" 2>&1)"; then
		printf 'hash failed stage=%s role=%s path=%s detail=%s\n' "$stage" "$role" "$path" "$line" \
			>>"$RUN/hash-failures.txt"
		VERDICT=harness-defect
		log "hash failed for $stage $role $path"
		return 1
	fi
	printf '%s %s %s\n' "$stage" "$role" "$line" >>"$RUN/hashes.txt"
	return 0
}

# identity_step <label> <command...>
# Runs one identity capture command, appends its output, and counts a
# nonzero status as an identity failure. Nonempty output is not success.
identity_step() {
	local label=$1
	shift
	printf '%s\n' "$label" >>"$RUN/identity.txt"
	if ! "$@" >>"$RUN/identity.txt" 2>&1; then
		printf 'identity step failed: %s\n' "$label" >>"$RUN/identity-failures.txt"
		IDENTITY_FAILURES=$((IDENTITY_FAILURES + 1))
		return 1
	fi
	return 0
}

identity() {
	identity_step utc date -u +%Y-%m-%dT%H:%M:%SZ
	printf 'worktree %s\n' "$ROOT" >>"$RUN/identity.txt"
	identity_step base git rev-parse HEAD
	identity_step changed git status --porcelain
	identity_step haxe-version haxe --version
	identity_step bun-version bun --version
	identity_step rustc-version rustc --version
	identity_step authored-source-hashes sha256sum tests/support/stage-check.sh \
		tests/haxe/place/*.hxml \
		tests/haxe/place/*.sh tests/haxe/place/native/*.rs \
		tests/haxe/place/place/*.hx tests/haxe/place/place/rejected/*.hx
	if [ "$IDENTITY_FAILURES" != "0" ]; then
		{
			printf 'verdict harness-defect\n'
			printf 'identity failures %s\n' "$IDENTITY_FAILURES"
			cat "$RUN/identity-failures.txt"
			cat "$RUN/identity.txt"
		} >"$RUN/summary.txt"
		log "identity capture failed; see $RUN/identity-failures.txt"
		exit 1
	fi
}

# paired_case <define|none> <label>
# One authored module, one define set, both outputs, one directory per label.
paired_case() {
	local define=$1 label=$2
	local dir="$RUN/case-$label"
	mkdir -p "$dir" || {
		VERDICT=harness-defect
		return 1
	}
	local jscompile="paired-js-compile-$label"
	local jsrun="paired-js-run-$label"
	local rustgen="rust-gen-$label"
	local rustc="rustc-$label"
	local build="harness-build-$label"
	local nativerun="harness-run-$label"
	local defines=()
	[ "$define" != "none" ] && defines=(-D placeSplit -D "place$define")

	local st=0
	attempt "$jscompile" zero haxe tests/haxe/place/paired.hxml \
		"${defines[@]+"${defines[@]}"}" -js "$dir/paired.js"
	st=$?
	if [ "$st" != "0" ]; then
		mark_unreached "$jscompile" "$st" "$jsrun" "$rustgen" "$rustc" "$build" "$nativerun"
		return 1
	fi
	hash_file "$jscompile" input tests/haxe/place/place/PlaceObserveStatic.hx
	hash_file "$jscompile" output "$dir/paired.js"

	attempt "$jsrun" zero bun "$dir/paired.js"
	st=$?
	if [ "$st" != "0" ]; then
		mark_unreached "$jsrun" "$st" "$rustgen" "$rustc" "$build" "$nativerun"
		return 1
	fi
	hash_file "$jsrun" input "$dir/paired.js"

	attempt "$rustgen" data haxe tests/haxe/place/rust-gen.hxml \
		"${defines[@]+"${defines[@]}"}" -D "rust-output=$dir/rust-gen"
	st=$?
	if [ "$st" != "0" ]; then
		mark_unreached "$rustgen" "$st" "$rustc" "$build" "$nativerun"
		return 1
	fi
	hash_file "$rustgen" output "$dir/rust-gen/place/place_observe_static.rs"

	attempt "$rustc" data rustc --crate-type lib --edition=2024 \
		--crate-name placegen -o "$dir/libplacegen.rlib" "$dir/rust-gen/lib.rs"
	st=$?
	if [ "$st" != "0" ]; then
		mark_unreached "$rustc" "$st" "$build" "$nativerun"
		return 1
	fi
	hash_file "$rustc" input "$dir/rust-gen/lib.rs"
	hash_file "$rustc" output "$dir/libplacegen.rlib"

	attempt "$build" data rustc --edition=2024 -o "$dir/harness" \
		tests/haxe/place/native/harness.rs --extern "placegen=$dir/libplacegen.rlib"
	st=$?
	if [ "$st" != "0" ]; then
		mark_unreached "$build" "$st" "$nativerun"
		return 1
	fi
	hash_file "$build" input tests/haxe/place/native/harness.rs
	hash_file "$build" output "$dir/harness"

	attempt "$nativerun" data "$dir/harness"
	hash_file "$nativerun" input "$dir/harness"
	return 0
}

identity

# Required stages, declared independently of what the runs record.
case_stages() {
	local label=$1
	expect_stage "paired-js-compile-$label"
	expect_stage "paired-js-run-$label"
	expect_stage "rust-gen-$label"
	expect_stage "rustc-$label"
	expect_stage "harness-build-$label"
	expect_stage "harness-run-$label"
}
case_stages all
expect_stage readfault-compile
expect_stage readfault-run
expect_stage reject-getter-assign
expect_stage reject-final-field-assign
expect_stage reject-readonly-element
expect_stage reject-final-local
for case in R1 R2 R3 R5 R5rec R6; do
	case_stages "$case"
done

# Whole-module pair with no case defines.
paired_case none all

# Deliberate program failure: the null element read. The run must reach its
# marker and then fail inside the authored store operation.
mkdir -p "$RUN/case-readfault" || exit 1
st=0
attempt readfault-compile zero haxe tests/haxe/place/readfault.hxml \
	-js "$RUN/case-readfault/readfault.js"
st=$?
if [ "$st" != "0" ]; then
	mark_unreached readfault-compile "$st" readfault-run
	VERDICT=harness-defect
else
	hash_file readfault-compile output "$RUN/case-readfault/readfault.js"
	attempt readfault-run program-failure bun "$RUN/case-readfault/readfault.js"
	st=$?
	hash_file readfault-run input "$RUN/case-readfault/readfault.js"
	if [ "$st" = "0" ]; then
		VERDICT=harness-defect
		log "readfault-run exited zero; the authored store did not fail"
	elif grep -qF 'before read' "$RUN/readfault-run.stdout" && grep -qF 'TypeError' "$RUN/readfault-run.stderr"; then
		log "readfault-run reached its marker and failed inside the authored store"
	else
		VERDICT=harness-defect
		log "readfault-run failed before its marker or with an unrelated error"
	fi
fi

# Expected source rejections; each must carry its own diagnostic text.
reject() {
	local stage=$1 main=$2 fragment=$3
	local extra=()
	[ "$main" != "place.rejected.RejectFinalFieldAssign" ] && extra=(-cp samples)
	st=0
	attempt "$stage" source-rejection haxe -cp tests/haxe/place \
		"${extra[@]+"${extra[@]}"}" -main "$main" -js "$RUN/$stage.js"
	st=$?
	if [ "$st" = "0" ]; then
		VERDICT=harness-defect
		log "$stage compiled; the form must be rejected"
		return
	fi
	expect_diagnostic "$stage" "$fragment"
}
reject reject-getter-assign place.rejected.RejectGetterAssign \
	'This expression cannot be accessed for writing'
reject reject-final-field-assign place.rejected.RejectFinalFieldAssign \
	'This expression cannot be accessed for writing'
reject reject-readonly-element place.rejected.RejectReadOnlyElementStore \
	'No @:arrayAccess function'
reject reject-final-local place.rejected.RejectFinalLocalAssign \
	'Cannot assign to final'

# Per-case pairs with matching defines on both sides.
for case in R1 R2 R3 R5 R5rec R6; do
	paired_case "$case" "$case"
done

# Verdict computation: exact stage membership, expected outcomes, diagnostic
# identity. summary.txt is written once afterwards, so the retained summary
# always carries the final computed verdict.
FINDINGS="$RUN/findings.txt"
MEMBERSHIP="$RUN/membership-findings.txt"

stage_check "$STATUS" "$EXPECTED_FILE" "$MEMBERSHIP" || VERDICT=harness-defect
cp "$MEMBERSHIP" "$FINDINGS"

while IFS="$TAB" read -r stage expected observed producer; do
	[ "$stage" = "stage" ] && continue
	[ -z "$stage" ] && continue
	case "$expected" in
	zero)
		if [ "$observed" != "0" ]; then
			printf 'unexpected failure %s (%s)\n' "$stage" "$observed" >>"$FINDINGS"
			VERDICT=harness-defect
		fi
		;;
	not-reached)
		ANY_UNREACHED=1
		printf 'stage %s not reached through %s (%s)\n' "$stage" "$producer" "$observed" >>"$FINDINGS"
		;;
	esac
done <"$STATUS"

for failure in "$RUN/identity-failures.txt" "$RUN/hash-failures.txt"; do
	if [ -f "$failure" ]; then
		while IFS= read -r line; do
			printf '%s\n' "$line" >>"$FINDINGS"
		done <"$failure"
	fi
done

FINAL_VERDICT="$VERDICT"
QUALIFIER=""
if [ "$ANY_UNREACHED" != "0" ] && [ "$FINAL_VERDICT" = "recorded" ]; then
	QUALIFIER="recorded-with-not-reached-stages"
fi

{
	printf 'run directory %s\n' "$RUN"
	printf 'verdict %s\n' "$FINAL_VERDICT"
	[ -z "$QUALIFIER" ] || printf 'verdict qualifier %s\n' "$QUALIFIER"
	printf 'stages declared %s recorded %s\n' "$(wc -l <"$EXPECTED_FILE")" "$(( $(wc -l <"$STATUS") - 1 ))"
	printf 'findings\n'
	cat "$FINDINGS"
	printf 'status rows\n'
	cat "$STATUS"
	printf 'diagnostic checks\n'
	cat "$DIAGNOSTICS"
} >"$RUN/summary.txt"

cat "$FINDINGS"
log "run directory $RUN"
log "verdict $FINAL_VERDICT"
[ -z "$QUALIFIER" ] || log "verdict qualifier $QUALIFIER"
if [ "$FINAL_VERDICT" != "recorded" ] && [ "$FINAL_VERDICT" != "recorded-with-not-reached-stages" ]; then
	exit 1
fi
if [ "$FINAL_VERDICT" = "recorded-with-not-reached-stages" ]; then
	log "verdict qualifier retained: some stages were not reached"
fi
exit 0
