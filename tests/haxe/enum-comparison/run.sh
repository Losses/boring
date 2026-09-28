#!/usr/bin/env bash
# Durable runner for the enum comparison fixtures.
#
# One invocation allocates one fresh run directory and never rewrites or
# removes an earlier one. Every stage records its lossless NUL-separated
# argv, its working directory, separate standard output and standard error,
# and its numeric status; no status is derived from log text. A stage runs
# only when its producer stage exited zero in the same attempt; every
# dependent stage of a failed producer receives an explicit not-reached row
# naming that producer. A selected list of compiler sources, standard library
# sources, and authored fixture files is hashed before the first stage and
# after the last one, and the two digest files must agree, so a runtime result
# traces to one fixed input set. The list is a selection and stops short of
# the complete compiler source closure.
#
# The runner records three value classes. A mechanical expectation comes
# from a rule the cited specifications state directly, and every mechanical
# expectation here comes from the specification 16 declaration-order rule and
# its agreement-with-record-equality requirement. A finding is one observed
# disagreement, carrying the rule it bears on when one is cited and carrying
# no rule citation where no rule states the case. A not-reached row names its
# producer. The runner asserts no payload ordering, no comparator equality
# rule, no general payload-enum equality, and no source rejection beyond the
# one diagnostic the key gate already reports.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
cd "$ROOT" || exit 1
# One pinned-environment boundary: the documented entry is
# `nix develop -c bash tests/haxe/enum-comparison/run.sh`, and no
# stage nests a second Nix call.
if [ "${IN_NIX_SHELL:-}" = "" ]; then
	printf 'run this runner through: nix develop -c bash tests/haxe/enum-comparison/run.sh\n'
	exit 1
fi
# shellcheck disable=SC1091
. "$ROOT/tests/support/stage-check.sh"

EVIDENCE=out/enum-comparison
ALLOC_PARENT="$EVIDENCE/runs"
mkdir -p "$ALLOC_PARENT" || exit 1
if ! RUN="$(mktemp -d "$ALLOC_PARENT/enum-comparison-XXXXXX")"; then
	printf 'run directory allocation failed\n'
	exit 1
fi
COMMANDS="$RUN/commands"
mkdir -p "$COMMANDS" || exit 1

TAB="$(printf '\t')"
STATUS="$RUN/status.tsv"
printf 'stage%sexpected%sobserved%sproducer\n' "$TAB" "$TAB" "$TAB" >"$STATUS"
DIAGNOSTICS="$RUN/diagnostics.txt"
printf 'stage%sexpected-diagnostic%sfound\n' "$TAB" "$TAB" >"$DIAGNOSTICS"
VALUES="$RUN/values.txt"
printf 'stage%skey%sobserved\n' "$TAB" "$TAB" >"$VALUES"
FINDINGS="$RUN/findings.txt"
: >"$FINDINGS"
EXPECTED_FILE="$RUN/expected-stages.txt"
: >"$EXPECTED_FILE"
VERDICT=recorded
ANY_UNREACHED=0
DEFECTS=0

log() {
	printf '%s\n' "$1"
}

defect() {
	printf '%s\n' "$1" >>"$FINDINGS"
	DEFECTS=$((DEFECTS + 1))
	log "harness defect: $1"
}

expect_stage() {
	printf '%s\n' "$1" >>"$EXPECTED_FILE"
}

record() {
	printf '%s%s%s%s%s%s%s\n' "$1" "$TAB" "$2" "$TAB" "$3" "$TAB" "$4" >>"$STATUS"
	log "$1 expected=$2 observed=$3 producer=$4"
}

# Confirms one saved argv file decodes back into exactly the arguments that
# were recorded, in order and without change.
argv_decodes() {
	local path="$1"
	shift
	local count="$#"
	local decoded=()
	local index=0
	mapfile -d '' decoded <"$path"
	if [ "${#decoded[@]}" -ne "$count" ]; then
		printf 'argv record %s holds %s arguments, expected %s\n' "$path" "${#decoded[@]}" "$count" >&2
		return 1
	fi
	for argument in "$@"; do
		if [ "${decoded[$index]}" != "$argument" ]; then
			printf 'argv record %s does not decode at position %s\n' "$path" "$index" >&2
			return 1
		fi
		index=$((index + 1))
	done
	return 0
}

# attempt <stage> <expected> <command...>
# Runs one stage in the invoking pinned environment and records its argv,
# cwd, streams, and numeric status. A decoding failure is recorded as
# status 125 and is a harness defect.
attempt() {
	local stage=$1 expected=$2
	shift 2
	printf '%s\0' "$@" >"$COMMANDS/$stage.argv"
	printf '%s\n' "$ROOT" >"$COMMANDS/$stage.cwd"
	{
		printf 'interpreter bash inside the invoking nix develop environment\n'
		printf 'cwd %s\n' "$ROOT"
		printf 'argv'
		printf ' %q' "$@"
		printf '\n'
	} >"$COMMANDS/$stage.argv.text"
	if ! argv_decodes "$COMMANDS/$stage.argv" "$@"; then
		printf '125\n' >"$COMMANDS/$stage.status"
		defect "$stage argv record does not decode"
		record "$stage" "$expected" 125 "$stage"
		return 125
	fi
	"$@" >"$COMMANDS/$stage.stdout" 2>"$COMMANDS/$stage.stderr"
	local observed=$?
	printf '%s\n' "$observed" >"$COMMANDS/$stage.status"
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
	if grep -qF -- "$fragment" "$COMMANDS/$stage.stderr"; then
		printf '%s%s%s%syes\n' "$stage" "$TAB" "$fragment" "$TAB" >>"$DIAGNOSTICS"
		return 0
	fi
	printf '%s%s%s%sNO\n' "$stage" "$TAB" "$fragment" "$TAB" >>"$DIAGNOSTICS"
	defect "$stage did not report the expected diagnostic: $fragment"
	return 1
}

# value_of <stage> <key>
# Reads one `key=value` line from a stage stdout. An absent line exits
# nonzero, which the caller turns into a harness defect.
value_of() {
	local stage=$1 key=$2
	awk -v key="$key" 'index($0, key "=") == 1 { sub(/^[^=]*=/, ""); print; found = 1 } END { if (!found) exit 1 }' \
		"$COMMANDS/$stage.stdout"
}

# require_value <stage> <key> <expected>
# Records one observed value and, when it disagrees with a mechanically
# derived expectation, records a harness defect. Every expectation passed here
# is derived from the specification 16 declaration-order rule.
require_value() {
	local stage=$1 key=$2 expected=$3
	local observed
	if ! observed="$(value_of "$stage" "$key")"; then
		defect "$stage printed no $key line"
		return 1
	fi
	printf '%s%s%s%s%s\n' "$stage" "$TAB" "$key" "$TAB" "$observed" >>"$VALUES"
	if [ "$observed" != "$expected" ]; then
		defect "$stage $key observed=$observed expected=$expected"
	fi
	return 0
}

# note_value <stage> <key>
# Records one observed value the runner asserts no expectation for.
note_value() {
	local stage=$1 key=$2
	local observed
	if ! observed="$(value_of "$stage" "$key")"; then
		defect "$stage printed no $key line"
		return 1
	fi
	printf '%s%s%s%s%s\n' "$stage" "$TAB" "$key" "$TAB" "$observed" >>"$VALUES"
	return 0
}

IDENTITY_INPUTS=(
	tests/haxe/enum-comparison/run.sh
	tests/support/stage-check.sh
	tests/haxe/enum-comparison/ts-gen.hxml
	tests/haxe/enum-comparison/rust-gen.hxml
	tests/haxe/enum-comparison/kotlin-gen.hxml
	tests/haxe/enum-comparison/swift-gen.hxml
	tests/haxe/enum-comparison/dart-gen.hxml
	tests/haxe/enum-comparison/reject-rust-gen.hxml
	tests/haxe/enum-comparison/harness/observe.ts
	tests/haxe/enum-comparison/harness/harness.rs
	tests/haxe/enum-comparison/enumcomparison/EnumComparisonSubject.hx
	tests/haxe/enum-comparison/enumcomparison/rejected/RejectPayloadEnumKey.hx
	samples/std/SortedMap.hx
	samples/std/RecordEq.hx
	samples/std/RecordShape.hx
	packages/compiler/PolicyQueries.hx
	packages/compiler/ComparatorPlan.hx
	packages/compiler/runtime/SortedTable.hx
	packages/compiler/reflaxe/ts/tscompiler/TsDecl.hx
	packages/compiler/reflaxe/ts/tscompiler/TsExpr.hx
	packages/compiler/reflaxe/rust/rustcompiler/RustDecl.hx
	packages/compiler/reflaxe/rust/rustcompiler/RustExpr.hx
	packages/compiler/reflaxe/kotlin/kotlincompiler/KotlinDecl.hx
	packages/compiler/reflaxe/kotlin/kotlincompiler/KotlinExpr.hx
	packages/compiler/reflaxe/swift/swiftcompiler/SwiftDecl.hx
	packages/compiler/reflaxe/swift/swiftcompiler/SwiftExpr.hx
	packages/compiler/reflaxe/dart/dartcompiler/DartDecl.hx
	packages/compiler/reflaxe/dart/dartcompiler/DartExpr.hx
	docs/specs/stdlib/16-dataclass-sorted-keys.md
	docs/specs/stdlib/07-sorted-keyed-tables.md
	docs/specs/features/01-enums-and-pattern-matching.md
	docs/specs/features/27-class-members-and-records.md
	docs/specs/features/28-enum-value-queries.md
)

# input_digest <output file>
# Hashes the selected compiler, standard library, and fixture inputs listed in
# IDENTITY_INPUTS. The two digest files must agree, so a stage result traces to
# one input set. The list covers the files this investigation read and the
# emitters it cites; it is not the complete compiler source closure.
input_digest() {
	sha256sum "${IDENTITY_INPUTS[@]}" >"$1" 2>"$1.err"
}

# record_identity <name> <command...>
# Records the loaded compiler provenance with the same shape as a stage: one
# argv file, one cwd file, separate streams, and one numeric status. A failed
# identity command stops the run before any stage executes, so no result is
# attributed to an unknown toolchain.
record_identity() {
	local name=$1
	shift
	printf '%s\0' "$@" >"$RUN/identity-$name.argv"
	printf '%s\n' "$ROOT" >"$RUN/identity-$name.cwd"
	if ! argv_decodes "$RUN/identity-$name.argv" "$@"; then
		printf '125\n' >"$RUN/identity-$name.status"
		return 0
	fi
	"$@" >"$RUN/identity-$name.stdout" 2>"$RUN/identity-$name.stderr"
	local observed=$?
	printf '%s\n' "$observed" >"$RUN/identity-$name.status"
	return 0
}

identity_status=0
check_identity() {
	local name=$1
	local status
	status="$(cat "$RUN/identity-$name.status")"
	if [ "$status" != "0" ]; then
		printf 'identity command %s failed with status %s\n' "$name" "$status" >>"$FINDINGS"
		identity_status="$status"
	fi
}

record_identity haxe-version haxe --version
record_identity rustc-version rustc --version
record_identity bun-version bun --version
record_identity reflaxe-pin haxelib list
record_identity generator-head git rev-parse HEAD
record_identity generator-worktree git rev-parse --show-toplevel
record_identity generator-state git status --porcelain
for name in haxe-version rustc-version bun-version reflaxe-pin generator-head generator-worktree generator-state; do
	check_identity "$name"
done
if [ "$identity_status" != "0" ]; then
	cat "$FINDINGS"
	log "identity capture failed; no stage ran"
	exit 1
fi

input_digest "$RUN/input-hashes-before.txt"

# Required stages, declared independently of what the runs record.
expect_stage accept-ts-gen
expect_stage accept-rust-gen
expect_stage accept-kotlin-gen
expect_stage accept-swift-gen
expect_stage accept-dart-gen
expect_stage reject-payload-enum-key
expect_stage rustc-lib
expect_stage rustc-harness
expect_stage rust-harness-run
expect_stage ts-harness-run

GEN_DIR="$RUN/ts-gen"
attempt accept-ts-gen zero haxe tests/haxe/enum-comparison/ts-gen.hxml -D "ts-output=$GEN_DIR"
st=$?
if [ "$st" != "0" ]; then
	mark_unreached accept-ts-gen "$st" ts-harness-run
fi

RUST_DIR="$RUN/rust-gen"
attempt accept-rust-gen zero haxe tests/haxe/enum-comparison/rust-gen.hxml -D "rust-output=$RUST_DIR"
st=$?
if [ "$st" != "0" ]; then
	mark_unreached accept-rust-gen "$st" rustc-lib rustc-harness rust-harness-run
fi

# The three remaining trees are generated for inspection only. No stage
# compiles or executes them, so they carry no runtime claim.
attempt accept-kotlin-gen zero haxe tests/haxe/enum-comparison/kotlin-gen.hxml -D "kotlin-output=$RUN/kotlin-gen"
attempt accept-swift-gen zero haxe tests/haxe/enum-comparison/swift-gen.hxml -D "swift-output=$RUN/swift-gen"
attempt accept-dart-gen zero haxe tests/haxe/enum-comparison/dart-gen.hxml -D "dart-output=$RUN/dart-gen" \
	-D "dart-test-output=$RUN/dart-gen-tests"

# The direct payload-enum key must stop with the gate diagnostic.
attempt reject-payload-enum-key source-rejection haxe tests/haxe/enum-comparison/reject-rust-gen.hxml \
	-D "rust-output=$RUN/reject-gen"
st=$?
if [ "$st" = "0" ]; then
	defect "reject-payload-enum-key compiled; the form must be rejected"
else
	expect_diagnostic reject-payload-enum-key 'enums with payloads are not keys'
fi

attempt rustc-lib data rustc --crate-type lib --edition=2024 --crate-name enumgen \
	-o "$RUN/libenumgen.rlib" "$RUST_DIR/lib.rs"
st=$?
if [ "$st" != "0" ]; then
	mark_unreached rustc-lib "$st" rustc-harness rust-harness-run
else
	attempt rustc-harness data rustc --edition=2024 -o "$RUN/rust-harness" \
		tests/haxe/enum-comparison/harness/harness.rs --extern "enumgen=$RUN/libenumgen.rlib"
	st=$?
	if [ "$st" != "0" ]; then
		mark_unreached rustc-harness "$st" rust-harness-run
	else
		attempt rust-harness-run data "$RUN/rust-harness"
	fi
fi

attempt ts-harness-run zero bun tests/haxe/enum-comparison/harness/observe.ts "$GEN_DIR"

# finding_row <target> <kind> <observed> <rule>
# Writes one finding row. A finding records one observed disagreement. The
# rule field carries the rule the observation bears on when a rule states the
# case, and states that no rule is cited when none does. The runner decides
# nothing about which side governs.
finding_row() {
	local target=$1 kind=$2 observed=$3 rule=$4
	printf 'finding%s%s%s%s%s%s%s%s\n' "$TAB" "$target" "$TAB" "$kind" "$TAB" "$observed" "$TAB" "$rule" >>"$FINDINGS"
}

# Value rows. The ordering expectations below come from the specification 16
# declaration-order rule (docs/specs/stdlib/16-dataclass-sorted-keys.md:41),
# which extends to parameterized constructors: two values of one constructor
# are equivalent under that order, and the constructor declared first compares
# before the one declared after it. The disputed rows are recorded with
# note_value and classified below.
classify_run() {
	local stage=$1 target=$2
	require_value "$stage" compareKeyValue1KeyValue1Again 0
	require_value "$stage" compareKeyValue1KeyBlank -1
	require_value "$stage" mapDistinctTags 'size=2;at0=first;at1=second'
	require_value "$stage" eqDistinctTags false
	note_value "$stage" eqSamePayload
	note_value "$stage" compareKeyValue1KeyValue2
	note_value "$stage" eqDistinctPayload
	note_value "$stage" mapDistinctPayload
	note_value "$stage" mapSamePayload

	local compare distinct_payload same_payload table
	compare="$(value_of "$stage" compareKeyValue1KeyValue2)"
	distinct_payload="$(value_of "$stage" eqDistinctPayload)"
	same_payload="$(value_of "$stage" eqSamePayload)"
	table="$(value_of "$stage" mapDistinctPayload)"

	if [ "$compare" = "0" ] && [ "$distinct_payload" = "false" ]; then
		finding_row "$target" compare-zero-with-unequal-records \
			"compareKeyValue1KeyValue2=$compare eqDistinctPayload=$distinct_payload" \
			'docs/specs/stdlib/16-dataclass-sorted-keys.md: two records compare equal exactly when their generated equals returns true'
	fi
	if [ "$same_payload" = "false" ]; then
		finding_row "$target" same-payload-reads-unequal \
			"eqSamePayload=$same_payload" \
			'no rule cited: general payload-enum equality is unresolved; the parameterless amendment of docs/specs/features/01-enums-and-pattern-matching.md does not reach this payload enum'
	fi
	if [ "${table%%;*}" = "size=1" ]; then
		finding_row "$target" two-payload-keys-one-slot \
			"mapDistinctPayload=$table" \
			'observed comparator equivalence: the two keys occupied one table slot; whether the payload distinction must survive as a key distinction is unresolved'
	fi
}

if [ -x "$RUN/rust-harness" ] && [ "$(cat "$COMMANDS/rust-harness-run.status" 2>/dev/null)" = "0" ]; then
	classify_run rust-harness-run rust
fi
if [ "$(cat "$COMMANDS/ts-harness-run.status" 2>/dev/null)" = "0" ]; then
	classify_run ts-harness-run ts
fi

# The fixed input set must not move between the first and the last stage.
input_digest "$RUN/input-hashes-after.txt"
HASH_STATE=matched
if ! cmp -s "$RUN/input-hashes-before.txt" "$RUN/input-hashes-after.txt"; then
	HASH_STATE=changed
	defect "input hashes changed during the run"
	diff "$RUN/input-hashes-before.txt" "$RUN/input-hashes-after.txt" >>"$RUN/input-hashes.diff" || true
fi

# Loaded compiler provenance, collected once per attempt.
{
	printf 'worktree %s\n' "$ROOT"
	for name in haxe-version rustc-version bun-version reflaxe-pin generator-head generator-worktree generator-state; do
		printf -- '--- %s exit %s\n' "$name" "$(cat "$RUN/identity-$name.status")"
		cat "$RUN/identity-$name.stdout"
		cat "$RUN/identity-$name.stderr"
	done
	printf -- '--- selected input digests %s (%s entries; a selection, short of the compiler source closure)\n' "$HASH_STATE" "$(wc -l <"$RUN/input-hashes-before.txt")"
	cat "$RUN/input-hashes-before.txt"
} >"$RUN/identity.txt"

# Verdict computation: exact stage membership, expected outcomes, diagnostic
# identity, and the fixed input set. summary.txt is written once afterwards.
MEMBERSHIP="$RUN/membership-findings.txt"
stage_check "$STATUS" "$EXPECTED_FILE" "$MEMBERSHIP" || VERDICT=harness-defect
cp "$MEMBERSHIP" "$FINDINGS.new"
grep -v '^$' "$FINDINGS" >>"$FINDINGS.new" || true
mv "$FINDINGS.new" "$FINDINGS"

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
	source-rejection)
		if [ "$observed" = "0" ]; then
			printf 'expected rejection compiled %s\n' "$stage" >>"$FINDINGS"
			VERDICT=harness-defect
		fi
		;;
	not-reached)
		ANY_UNREACHED=1
		printf 'stage %s not reached through %s (%s)\n' "$stage" "$producer" "$observed" >>"$FINDINGS"
		;;
	data)
		if [ "$observed" = "0" ]; then
			:
		else
			printf 'unexpected data failure %s (%s)\n' "$stage" "$observed" >>"$FINDINGS"
			VERDICT=harness-defect
		fi
		;;
	esac
done <"$STATUS"

if [ "$DEFECTS" != "0" ]; then
	VERDICT=harness-defect
fi

# A finding row carries five fields: the marker, the target, the finding kind,
# the observed values, and the rule the values bear on. A row with another
# field count, an empty field, or a continuation line from a reused format
# string is a runner defect, since it can no longer be read back.
while IFS= read -r line; do
	case "$line" in
	finding*)
		fields="$(printf '%s' "$line" | awk -F '\t' '{print NF}')"
		second="$(printf '%s' "$line" | awk -F '\t' '{print $2}')"
		third="$(printf '%s' "$line" | awk -F '\t' '{print $3}')"
		fourth="$(printf '%s' "$line" | awk -F '\t' '{print $4}')"
		fifth="$(printf '%s' "$line" | awk -F '\t' '{print $5}')"
		if [ "$fields" != "5" ] || [ -z "$second" ] || [ -z "$third" ] || [ -z "$fourth" ] || [ -z "$fifth" ]; then
			defect "finding row is not five populated fields ($fields): $line"
		fi
		;;
	esac
done <"$FINDINGS"

FINAL_VERDICT="$VERDICT"
QUALIFIER=""
if [ "$ANY_UNREACHED" != "0" ] && [ "$FINAL_VERDICT" = "recorded" ]; then
	QUALIFIER="recorded-with-not-reached-stages"
fi

{
	printf 'run directory %s\n' "$RUN"
	printf 'worktree %s\n' "$ROOT"
	printf 'head %s\n' "$(git rev-parse HEAD)"
	printf 'haxe %s\n' "$(haxe --version 2>/dev/null)"
	printf 'rustc %s\n' "$(rustc --version 2>/dev/null)"
	printf 'verdict %s\n' "$FINAL_VERDICT"
	[ -z "$QUALIFIER" ] || printf 'verdict qualifier %s\n' "$QUALIFIER"
	printf 'stages declared %s recorded %s\n' "$(wc -l <"$EXPECTED_FILE")" "$(( $(wc -l <"$STATUS") - 1 ))"
	printf 'selected input digests %s (%s entries; a selection, short of the compiler source closure)\n' "$HASH_STATE" "$(wc -l <"$RUN/input-hashes-before.txt")"
	printf 'findings\n'
	cat "$FINDINGS"
	printf 'status rows\n'
	cat "$STATUS"
	printf 'diagnostic checks\n'
	cat "$DIAGNOSTICS"
	printf 'value rows\n'
	cat "$VALUES"
} >"$RUN/summary.txt"

cat "$FINDINGS"
log "run directory $RUN"
log "verdict $FINAL_VERDICT"
[ -z "$QUALIFIER" ] || log "verdict qualifier $QUALIFIER"
if [ "$FINAL_VERDICT" != "recorded" ] && [ "$FINAL_VERDICT" != "recorded-with-not-reached-stages" ]; then
	exit 1
fi
exit 0
