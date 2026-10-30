#!/usr/bin/env bash
# boring pack dry run. Packs the ts and kotlin bundles and lists their
# artifacts. Does not publish anything.
#
# Run from the boring repository root after bun install (the ts pack needs
# the TypeScript compiler from node_modules).
set -u
ROOT="${BORING_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$ROOT"

export BORING_PACKAGE_TSC="${BORING_PACKAGE_TSC:-$ROOT/node_modules/.bin/tsc}"
if [ ! -x "$BORING_PACKAGE_TSC" ]; then
  echo "tsc not found at $BORING_PACKAGE_TSC; run bun install first" >&2
fi

echo "== pack ts =="
boring pack ts || echo "FAIL: ts pack"

echo "== ts artifact =="
ls -la reference/ts/boring-codec-0.1.0.tgz 2>/dev/null || echo "no ts tarball"
tar -tzf reference/ts/boring-codec-0.1.0.tgz 2>/dev/null | head -20

echo "== pack kotlin =="
boring pack kotlin || echo "FAIL: kotlin pack"

echo "== kotlin artifact =="
find reference/kotlin -maxdepth 3 -name '*.jar' -o -maxdepth 3 -name 'pom.xml' 2>/dev/null
