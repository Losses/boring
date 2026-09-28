#!/usr/bin/env bash
# Runs the classifier fixture and records its evidence under a fresh
# per-invocation directory out/classifier/run-<stamp>-<suffix>/.
# The directory is allocated with mktemp, which creates it exclusively and
# atomically; an existing directory is never reused or overwritten, and the
# historical top-level evidence files are left untouched. Two stages run
# separately: the macro probe (source typing observation) and the ordinary
# compile (source acceptance). The retained files carry the exact commands,
# cwd, separate streams, process statuses, toolchain identity, and sha256 of
# the fixture and compiler-helper source inputs. Internal helper exceptions
# are separated from process/setup status. No credentials are printed.
# Invoke inside the pinned toolchain:
#   nix develop -c bash tests/haxe/classifier/run.sh
set -u

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)" || exit 2
cd "$root"

base=out/classifier
mkdir -p "$base" || { echo "cannot create $base" >&2; exit 2; }

stamp="$(date +%Y%m%d-%H%M%S)"
run_dir="$(mktemp -d "$base/run-${stamp}-XXXXXX")" || {
	echo "failed to allocate a fresh evidence directory under $base" >&2
	exit 2
}

# Toolchain identity and input hashes. A failure here means the evidence
# cannot identify the candidate that produced the results, so the run fails
# before any stage runs.
(
	set -e
	echo "haxe version: $(haxe --version 2>&1)"
	echo "haxelib list:"
	haxelib list 2>&1
	echo "git head: $(git rev-parse HEAD 2>&1)"
	echo "git status:"
	git status --short 2>&1
	echo "cwd: $root"
	echo "evidence dir: $run_dir"
	echo "input hashes (sha256):"
	sha256sum \
		tests/haxe/classifier/ClassifierProbe.hx \
		tests/haxe/classifier/classifier/Fixtures.hx \
		tests/haxe/classifier/classifier/RO.hx \
		tests/haxe/classifier/classifier/Recursive.hx \
		tests/haxe/classifier/classifier/CompileEntry.hx \
		tests/haxe/classifier/altpack/ReadOnlyArray.hx \
		tests/haxe/classifier/altpackalias/ReadOnlyArray.hx \
		tests/haxe/classifier/classifier.hxml \
		tests/haxe/classifier/classifier-compile.hxml \
		tests/haxe/classifier/run.sh \
		packages/compiler/StaticFieldHelper.hx \
		packages/compiler/ComparatorPlan.hx \
		packages/compiler/PolicyQueries.hx \
		packages/compiler/reflaxe/swift/swiftcompiler/SwiftArrayBoundary.hx \
		packages/compiler/reflaxe/swift/swiftcompiler/SwiftType.hx
) > "$run_dir/environment.txt" 2>&1
env_status=$?
if [ "$env_status" -ne 0 ]; then
	echo "identity or input-hash capture failed (status $env_status); see $run_dir/environment.txt" >&2
	exit "$env_status"
fi

# Stage 1: the macro probe, a source typing observation.
haxe tests/haxe/classifier/classifier.hxml \
	> "$run_dir/probe-stdout.txt" 2> "$run_dir/probe-stderr.txt"
probe_status=$?

# Internal helper exceptions, retained separately from process/setup status.
grep -n "raised:" "$run_dir/probe-stdout.txt" > "$run_dir/helper-exceptions.txt" 2>/dev/null || true

# Stage 2: the ordinary compile, a source acceptance record emitted into
# this run directory.
haxe tests/haxe/classifier/classifier-compile.hxml \
	-js "$run_dir/compile-entry.js" \
	> "$run_dir/compile-stdout.txt" 2> "$run_dir/compile-stderr.txt"
compile_status=$?

echo "$probe_status" > "$run_dir/probe-status.txt"
echo "$compile_status" > "$run_dir/compile-status.txt"
{
	echo "probe command: haxe tests/haxe/classifier/classifier.hxml"
	echo "compile command: haxe tests/haxe/classifier/classifier-compile.hxml -js $run_dir/compile-entry.js"
	echo "cwd: $root"
	echo "probe exit status: $probe_status"
	echo "compile exit status: $compile_status"
	echo "probe stdout bytes: $(wc -c < "$run_dir/probe-stdout.txt")"
	echo "probe stderr bytes: $(wc -c < "$run_dir/probe-stderr.txt")"
	echo "compile stdout bytes: $(wc -c < "$run_dir/compile-stdout.txt")"
	echo "compile stderr bytes: $(wc -c < "$run_dir/compile-stderr.txt")"
} > "$run_dir/run-command.txt"

overall=$probe_status
if [ "$compile_status" -ne 0 ]; then
	overall=1
fi
if [ "$overall" -ne 0 ]; then
	echo "evidence dir: $run_dir" >&2
	echo "probe exit=$probe_status compile exit=$compile_status" >&2
	exit "$overall"
fi
echo "evidence dir: $run_dir"
echo "probe exit=$probe_status compile exit=$compile_status"
exit 0
