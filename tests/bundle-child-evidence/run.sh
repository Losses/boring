#!/usr/bin/env bash
# Durable focused runner for the child execution evidence of feature 59.
#
# One invocation allocates one fresh evidence directory and never reuses or
# removes an earlier one, so every attempt including a failed one is retained.
# Each command writes its own argv, cwd, separate standard output and standard
# error, and a numeric status file; nothing derives a status from log text.
# Identity and source-hash capture failures stop the run before any check.
#
# Invoke inside the pinned toolchain from the repository root:
#   nix develop -c bash tests/bundle-child-evidence/run.sh
set -u

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" || exit 2
cd "$root" || exit 2

base=out/f1-child-evidence
mkdir -p "$base" || exit 2

stamp="$(date +%Y%m%d-%H%M%S)"
run_dir="$(mktemp -d "$base/run-${stamp}-XXXXXX")" || {
	echo "cannot allocate a fresh evidence directory under $base" >&2
	exit 2
}
commands="$run_dir/commands"
mkdir -p "$commands" || exit 2

# Confirms one saved argv file decodes back into exactly the arguments that
# were recorded, in order and without change.
argv_decodes() {
	local path="$1"
	shift
	local count="$#"
	local decoded=()
	local index=0
	mapfile -d '' decoded < "$path"
	if [ "${#decoded[@]}" -ne "$count" ]; then
		echo "argv record $path holds ${#decoded[@]} arguments, expected $count" >&2
		return 1
	fi
	for argument in "$@"; do
		if [ "${decoded[$index]}" != "$argument" ]; then
			echo "argv record $path does not decode into the actual argument array at position $index" >&2
			return 1
		fi
		index=$((index + 1))
	done
	return 0
}

# Identity and input hashes. Each identity command records its own streams and
# numeric status, so a failure here is a value and stops the run before any
# check executes; the identity body holds no command substitution to lose one.
# argv files use the same lossless NUL-separated form as the gate commands.
identity_dir="$run_dir/identity"
mkdir -p "$identity_dir" || exit 2

record_identity() {
	name="$1"
	shift
	printf '%s\0' "$@" > "$identity_dir/$name.argv"
	printf '%s\n' "$root" > "$identity_dir/$name.cwd"
	if ! argv_decodes "$identity_dir/$name.argv" "$@"; then
		printf '125\n' > "$identity_dir/$name.status"
		return 0
	fi
	"$@" > "$identity_dir/$name.stdout" 2> "$identity_dir/$name.stderr"
	status=$?
	printf '%s\n' "$status" > "$identity_dir/$name.status"
	return 0
}

record_identity haxe-version haxe --version
record_identity bun-version bun --version
record_identity git-head git rev-parse HEAD
record_identity git-status git status --short
record_identity source-hashes sha256sum \
	tools/bundle/Driver.hx \
	tools/bundle/ChildEvidence.hx \
	docs/specs/features/59-bundle-driver.md \
	tests/bundle-child-evidence/bundle-child-evidence.test.ts \
	tests/bundle-child-evidence/probe/EvidenceProbe.hx \
	tests/bundle-child-evidence/probe/probe.hxml \
	tests/bundle-child-evidence/fixtures/child.ts \
	tests/bundle-child-evidence/fixtures/project/fixture-src/FixtureMain.hx \
	tests/bundle-child-evidence/fixtures/project/fixture-src/DeprecationSource.hx \
	tests/bundle-child-evidence/fixtures/project/fixture-src/FixtureMacro.hx \
	tests/bundle-child-evidence/tsconfig.json \
	tests/bundle-child-evidence/run.sh

{
	echo "cwd: $root"
	echo "evidence directory: $run_dir"
	for name in haxe-version bun-version git-head git-status source-hashes; do
		echo "--- $name exit $(cat "$identity_dir/$name.status")"
		cat "$identity_dir/$name.stdout"
		cat "$identity_dir/$name.stderr"
	done
} > "$run_dir/identity.txt"

identity_status=0
for name in haxe-version bun-version git-head git-status source-hashes; do
	status="$(cat "$identity_dir/$name.status")"
	if [ "$status" -ne 0 ]; then
		identity_status="$status"
		echo "identity command $name failed with status $status" >&2
	fi
done
printf '%s\n' "$identity_status" > "$run_dir/identity.status"
if [ "$identity_status" -ne 0 ]; then
	echo "identity or source-hash capture failed; see $run_dir/identity.txt" >&2
	exit "$identity_status"
fi

# Runs one command with its argv, cwd, separate streams, and numeric status
# recorded beside it. The status is stored as a value and read as a value.
#
# The argv file holds the arguments NUL-separated. That is lossless for every
# argument an exec can carry: an argument may be empty, hold newlines, tabs or
# a NUL-free binary fragment, and the separator cannot appear inside one. The
# saved file is read back into an array and compared against the real argument
# array before the command runs, so a record that fails to decode is reported
# as a failure and never kept as evidence. Read it with `tr '\0' '\n'` for
# display, or split on NUL to recover the exact array.
record_command() {
	name="$1"
	shift
	printf '%s\0' "$@" > "$commands/$name.argv"
	printf '%s\n' "$root" > "$commands/$name.cwd"
	if ! argv_decodes "$commands/$name.argv" "$@"; then
		printf '125\n' > "$commands/$name.status"
		return 0
	fi
	"$@" > "$commands/$name.stdout" 2> "$commands/$name.stderr"
	status=$?
	printf '%s\n' "$status" > "$commands/$name.status"
	return 0
}

# One recorded command whose arguments are hard to represent, so the lossless
# form is exercised on every run: an empty argument, an argument holding
# newlines, and one holding repeated spaces.
record_command argv-roundtrip bash -c 'for argument in "$@"; do printf "[%s]\n" "$argument"; done' argv "" "line one
line two" "spaced  value"

record_command focused-tests bun test tests/bundle-child-evidence/
record_command typecheck ./node_modules/.bin/tsc -p tests/bundle-child-evidence/tsconfig.json
record_command lint bun run lint
record_command docs bun tools/doc-style/check.ts

overall=0
for name in argv-roundtrip focused-tests typecheck lint docs; do
	status="$(cat "$commands/$name.status")"
	echo "$name: exit $status"
	if [ "$status" -ne 0 ]; then
		overall=1
		echo "--- $name stderr (tail)"
		tail -n 20 "$commands/$name.stderr"
	fi
done

{
	echo "evidence directory: $run_dir"
	for name in argv-roundtrip focused-tests typecheck lint docs; do
		echo "$name exit $(cat "$commands/$name.status")"
	done
} > "$run_dir/summary.txt"

echo "evidence directory: $run_dir"
echo "overall exit=$overall"
exit "$overall"
