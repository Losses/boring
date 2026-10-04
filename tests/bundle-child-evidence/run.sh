#!/usr/bin/env bash
# Durable focused runner for the child execution evidence of feature 59.
#
# One invocation allocates one fresh evidence directory and never reuses or
# removes an earlier one, so every attempt including a failed one is retained.
# Status, streams and input identity are recorded by the shared recording layer
# (tools/runner-record/runner-record.sh); nothing derives a status from log
# text, and the layer is the single place that owns the record shape.
#
# The checkout revision is an explicit input. This runner never calls git, so a
# revision cannot be inferred from the environment and silently reported as
# verified. Export BORING_REVISION with the WB-verified revision, and
# BORING_REVISION_STATUS with how it was verified; when it is unset the
# revision record is a failure value and the run stops before any check.
#
# Invoke inside the pinned toolchain from the repository root:
#   BORING_REVISION=<verified> nix develop -c bash tests/bundle-child-evidence/run.sh
set -u

root="$(cd "$(dirname "$BASH_SOURCE")/../.." && pwd)" || exit 2
cd "$root" || exit 2

# shellcheck source=../../tools/runner-record/runner-record.sh
. "$root/tools/runner-record/runner-record.sh" || exit 2

base=out/f1-child-evidence
rr_init child-evidence "$base" || exit 2
run_dir="$RR_RUN"
commands="$RR_CMD"
identity_dir="$run_dir/identity"

# Identity and input hashes. Tool identities name explicit paths so a PATH
# lookup cannot stand in for identity, and the revision is the explicit
# BORING_REVISION input rather than a repository command. A failure here is a
# value that stops the run before any check executes; the identity body holds
# no command substitution that could lose one.
haxe_path="$(command -v haxe)" || {
	echo "refusing to run: haxe is not on the PATH of this environment" >&2
	exit 2
}
bun_path="$(command -v bun)" || {
	echo "refusing to run: bun is not on the PATH of this environment" >&2
	exit 2
}
rr_identity_tool haxe "$haxe_path" || { echo "recording failed: haxe identity" >&2; exit 2; }
rr_identity_tool bun "$bun_path" || { echo "recording failed: bun identity" >&2; exit 2; }
rr_identity_revision revision || { echo "recording failed: revision" >&2; exit 2; }
rr_identity_files source-hashes \
	packages/driver/src/driver/Main.hx \
	packages/driver/src/driver/ChildEvidence.hx \
	docs/specs/features/59-bundle-driver.md \
	tests/bundle-child-evidence/bundle-child-evidence.test.ts \
	tests/bundle-child-evidence/probe/EvidenceProbe.hx \
	tests/bundle-child-evidence/probe/probe.hxml \
	tests/bundle-child-evidence/fixtures/child.ts \
	tests/bundle-child-evidence/fixtures/project/fixture-src/FixtureMain.hx \
	tests/bundle-child-evidence/fixtures/project/fixture-src/DeprecationSource.hx \
	tests/bundle-child-evidence/fixtures/project/fixture-src/FixtureMacro.hx \
	tests/bundle-child-evidence/tsconfig.json \
	tests/bundle-child-evidence/run.sh || { echo "recording failed: source-hashes" >&2; exit 2; }

{
	echo "cwd: $root"
	echo "evidence directory: $run_dir"
	for name in haxe bun revision source-hashes; do
		echo "--- $name exit $(cat "$identity_dir/$name.status")"
		cat "$identity_dir/$name.realpath" 2> /dev/null
		cat "$identity_dir/$name.version" 2> /dev/null
		cat "$identity_dir/$name.value" 2> /dev/null
		cat "$identity_dir/$name.verification" 2> /dev/null
		cat "$identity_dir/$name.sha256" 2> /dev/null
		cat "$identity_dir/$name.stderr" 2> /dev/null
	done
} > "$run_dir/identity.txt"

identity_status=0
for name in haxe bun revision source-hashes; do
	status="$(cat "$identity_dir/$name.status" 2> /dev/null)" || { echo "missing identity record: $name" >&2; exit 2; }
	if [ "$status" -ne 0 ]; then
		identity_status="$status"
		echo "identity record $name failed with status $status" >&2
	fi
done
printf '%s\n' "$identity_status" > "$run_dir/identity.status"
if [ "$identity_status" -ne 0 ]; then
	echo "identity or source-hash capture failed; see $run_dir/identity.txt" >&2
	exit "$identity_status"
fi

# The gate set is the same five commands the base runner recorded, with the
# same meanings; the shared layer owns their record shape.
rr_record_cmd argv-roundtrip -- bash -c 'for argument in "$@"; do printf "[%s]\n" "$argument"; done' argv "" "line one
line two" "spaced  value" || { echo "recording failed: argv-roundtrip" >&2; exit 2; }
rr_record_cmd focused-tests -- bun test tests/bundle-child-evidence/ || { echo "recording failed: focused-tests" >&2; exit 2; }
rr_record_cmd typecheck -- ./node_modules/.bin/tsc -p tests/bundle-child-evidence/tsconfig.json || { echo "recording failed: typecheck" >&2; exit 2; }
rr_record_cmd lint -- bun run lint || { echo "recording failed: lint" >&2; exit 2; }
rr_record_cmd docs -- bun tools/doc-style/check.ts || { echo "recording failed: docs" >&2; exit 2; }

# Diagnostics are recorded for context only. They are not part of the gate set
# and never change the gate verdict.
rr_record_cmd repo-typecheck -- bun run typecheck || { echo "recording failed: repo-typecheck" >&2; exit 2; }
rr_record_cmd focused-lint -- ./node_modules/.bin/eslint tests/bundle-child-evidence/ || { echo "recording failed: focused-lint" >&2; exit 2; }

gate="argv-roundtrip focused-tests typecheck lint docs"
diagnostics="repo-typecheck focused-lint"
overall=0
for name in $gate; do
	status="$(cat "$commands/$name.status" 2> /dev/null)" || { echo "missing gate record: $name" >&2; exit 2; }
	echo "$name: exit $status"
	if [ "$status" -ne 0 ]; then
		overall=1
		echo "--- $name stderr (tail)"
		tail -n 20 "$commands/$name.stderr"
	fi
done
for name in $diagnostics; do
	echo "$name (diagnostic, outside the gate): exit $(cat "$commands/$name.status" 2> /dev/null || echo missing)"
done

{
	echo "evidence directory: $run_dir"
	echo "gate:"
	for name in $gate; do
		echo "  $name exit $(cat "$commands/$name.status")"
	done
	echo "diagnostics (outside the gate):"
	for name in $diagnostics; do
		echo "  $name exit $(cat "$commands/$name.status")"
	done
} > "$run_dir/summary.txt"

set +e
rr_finish > /dev/null
record_status=$?
set -e
if [ "$record_status" -ge 2 ]; then
	echo "refusing to report success: the run record could not be written" >&2
	overall=1
fi
# The in-process verdict must agree with the persistent summary.
persisted="$(cat "$run_dir/run.status" 2> /dev/null || echo 1)"
if [ "$persisted" -ne 0 ]; then
	overall=1
fi
echo "evidence directory: $run_dir"
echo "overall exit=$overall"
exit "$overall"
