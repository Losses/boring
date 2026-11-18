#!/usr/bin/env bash
# The macOS execution half of block A (task t-mwlhbhvg-n22u): out parameters
# (T* and T**), temporary C buffers, and the generated pointer spellings.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"

OUT=${1:-out/swift-pointer-check/run}
rm -rf "$OUT"
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

echo "--- haxe: $(haxe --version 2>&1 | head -1)"
echo "--- swiftc: $(swiftc --version 2>&1 | head -1)"
echo "--- generating the pointer fixtures"
haxe tests/swift-pointer-check/check.hxml \
  -D swift-output="$OUT/gen" \
  -D swift-test-output="$OUT/tests"

sources=()
while IFS= read -r file; do
  sources+=("$file")
done < <(find "$OUT/gen" -name '*.swift' | sort)
sources+=("tests/swift-pointer-check/A1Main.swift")
echo "--- swiftc sources (${#sources[@]} files)"
mkdir -p "$OUT/bin"
if ! swiftc -swift-version 5 -o "$OUT/bin/pointer-check" "${sources[@]}" >"$OUT/compile.log" 2>&1; then
  echo "--- swiftc failed; compiler output follows" >&2
  cat "$OUT/compile.log" >&2
  exit 1
fi
cat "$OUT/compile.log"

if ! "$OUT/bin/pointer-check" >"$OUT/run.log" 2>&1; then
  echo "--- pointer test failed; runner output follows" >&2
  cat "$OUT/run.log" >&2
  exit 1
fi
cat "$OUT/run.log"

grep -Eq '^a1 ascent=[0-9]' "$OUT/run.log"
grep -q 'stable=true' "$OUT/run.log"
grep -Eq '^a1 tstar2 count=1 runGlyphs=[1-9]' "$OUT/run.log"
grep -Eq '^a2 glyphs=[1-9]' "$OUT/run.log"
grep -q 'ordered=true' "$OUT/run.log"
grep -q '^a3 ok=true same=9' "$OUT/run.log"
grep -q '^a4 mapped=true nonEmpty=5' "$OUT/run.log"
grep -Eq '^a5 changed=[1-9]' "$OUT/run.log"
