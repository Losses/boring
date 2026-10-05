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

# Compiler provenance: which bytes the `boring` haxelib resolves for this
# toolchain. The haxelib build used by the dev shell resolves its repository
# from the nearest `.haxelib` directory walked up from the working directory
# (the dev shell exports HAXELIB_PATH), so the repository it names is exactly
# what the gate below binds: a wrong HAXELIB_PATH that still resolves (a
# sibling checkout's or a store source's `.haxelib`) would let the checks
# compile with another tree's compiler. The command is recorded through the
# shared layer with argv, cwd, streams and numeric status, so the record is
# reproducible rather than inferred from log text.
rr_identity_stream haxelib-path-boring -- haxelib path boring || { echo "recording failed: haxelib-path-boring" >&2; exit 2; }
# The path line immediately before "-D boring=" is the library this haxelib
# build resolved; fall back to the first absolute line when that marker is
# absent. Every candidate line stays in the recorded output for audit.
boring_resolved="$(awk '/^-D boring=/{print prev; exit} {prev=$0}' "$identity_dir/haxelib-path-boring.sha256" 2> /dev/null || true)"
if [ -z "$boring_resolved" ]; then
	boring_resolved="$(grep -E '^/' "$identity_dir/haxelib-path-boring.sha256" 2> /dev/null | head -n 1 || true)"
fi
boring_real=""
if [ -n "$boring_resolved" ] && [ -e "$boring_resolved" ]; then
	boring_real="$(readlink -f "$boring_resolved")"
fi
root_real="$(readlink -f "$root")"
haxe_bin_real="$(readlink -f "$haxe_path" 2> /dev/null || true)"
boring_under_root="no"
case "$boring_real" in
	"$root_real" | "$root_real"/*) boring_under_root="yes" ;;
esac
{
	echo "compiler provenance"
	echo "HAXELIB_PATH: ${HAXELIB_PATH:-unset}"
	echo "haxelib path boring (raw): $boring_resolved"
	echo "boring-resolved-path (realpath): ${boring_real:-none}"
	echo "checkout root (realpath): $root_real"
	echo "boring resolved under root: $boring_under_root"
	echo "haxe binary: ${haxe_bin_real:-none}"
	[ -n "$haxe_bin_real" ] && sha256sum "$haxe_bin_real"
	echo "haxe version: $(sed -n '1p' "$identity_dir/haxe.version" 2> /dev/null)"
	[ -f "$root_real/haxelib.json" ] && sha256sum "$root_real/haxelib.json"
	if [ -n "$boring_real" ] && [ -f "$boring_real/Intercept.hx" ]; then
		sha256sum "$boring_real/Intercept.hx"
	fi
	echo "compiler bytes under ${boring_real:-none}:"
	if [ -n "$boring_real" ] && [ -d "$boring_real" ]; then
		find "$boring_real" -type f -print0 | sort -z | xargs -0 -r sha256sum
	fi
	echo "end compiler provenance"
} > "$run_dir/compiler-provenance.txt"

{
	echo "cwd: $root"
	echo "evidence directory: $run_dir"
	for name in haxe bun revision source-hashes haxelib-path-boring; do
		echo "--- $name exit $(cat "$identity_dir/$name.status")"
		cat "$identity_dir/$name.realpath" 2> /dev/null
		cat "$identity_dir/$name.version" 2> /dev/null
		cat "$identity_dir/$name.value" 2> /dev/null
		cat "$identity_dir/$name.verification" 2> /dev/null
		cat "$identity_dir/$name.sha256" 2> /dev/null
		cat "$identity_dir/$name.stderr" 2> /dev/null
	done
	echo "--- compiler-provenance"
	cat "$run_dir/compiler-provenance.txt"
} > "$run_dir/identity.txt"

# The provenance gate runs after identity capture so the resolved path, its
# realpath and the compiler bytes are retained either way; it stops the run
# before any check executes.
if [ "$boring_under_root" != "yes" ]; then
	printf '2\n' > "$run_dir/provenance-gate.status"
	echo "compiler provenance gate failed: haxelib path boring resolves to '${boring_real:-<unresolved>}' which is not under $root_real" >&2
	echo "refusing to run: the boring class path does not belong to this checkout; see $run_dir/compiler-provenance.txt" >&2
	exit 2
fi
printf '0\n' > "$run_dir/provenance-gate.status"

identity_status=0
for name in haxe bun revision source-hashes haxelib-path-boring; do
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

gate="argv-roundtrip focused-tests typecheck lint docs"
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

{
	echo "evidence directory: $run_dir"
	echo "gate:"
	for name in $gate; do
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
