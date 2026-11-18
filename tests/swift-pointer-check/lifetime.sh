#!/usr/bin/env bash
# Record the two Buffer<T> lifetime mistakes. A missing free is a silent
# leak and a double free is silent undefined behavior; the script never gates
# on the outcome.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"

OUT=${1:-out/swift-pointer-check/lifetime}
rm -rf "$OUT"
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

haxe tests/swift-pointer-check/check-lifetime.hxml \
  -D swift-output="$OUT/gen" \
  -D swift-test-output="$OUT/tests"

sources=()
while IFS= read -r file; do
  sources+=("$file")
done < <(find "$OUT/gen" -name '*.swift' | sort)
sources+=("tests/swift-pointer-check/BufferLifetimeMain.swift")
mkdir -p "$OUT/bin"
swiftc -swift-version 5 -o "$OUT/bin/lifetime" "${sources[@]}" >"$OUT/compile.log" 2>&1

set +e
"$OUT/bin/lifetime" leak >"$OUT/leak.log" 2>&1
leakRc=$?
"$OUT/bin/lifetime" double >"$OUT/double.log" 2>&1
doubleRc=$?
set -e
echo "leak_exit=$leakRc"
cat "$OUT/leak.log"
echo "double_free_exit=$doubleRc"
cat "$OUT/double.log"
