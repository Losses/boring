#!/usr/bin/env bash
# Roots-manifest consistency guard for boring's own project file.
#
# Boring's own bundle entry point is boring.json: each bundle takes its module
# roots from a named source set and its remaining arguments from haxeArgs.
# tools/roots-guard/check-roots-guard.sh still reads HXML, so this wrapper
# materializes that view from the project file into a throwaway directory and
# then runs the guard against it. The materialized files are never read by
# generation, so they cannot drift: every gate run rebuilds them.
#
# Usage: check-project-roots.sh [out-dir]
#   out-dir   directory to materialize into (default: a fresh temporary
#             directory that is removed afterwards). Pass a directory to
#             inspect the materialized view after a failure.
#
# Exit: 0 = PASS, 1 = FAILED, 2 = usage error.
set -u

here="$(cd "$(dirname "$0")" && pwd)"

dir=""
if [ "$#" -gt 0 ]; then
    dir="$1"
    shift
fi
if [ -z "$dir" ]; then
    dir="$(mktemp -d "${TMPDIR:-/tmp}/roots-guard-examples.XXXXXX")" || exit 2
    cleanup() { rm -rf "$dir"; }
    trap cleanup EXIT
fi

if ! bun "$here/materialize-project-roots.ts" "$dir"; then
    echo "roots guard: FAILED (could not materialize the project roots)"
    exit 1
fi

bash "$here/check-roots-guard.sh" "$dir" "$@"
status="$?"
exit "$status"
