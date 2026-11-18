#!/usr/bin/env bash
# The macOS execution half of block B: ARC-visible CF values, the borrowed
# pointer adapters, and the class-reference cache.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"

OUT=${1:-out/swift-ownership-check/run}
rm -rf "$OUT"
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

echo "--- haxe: $(haxe --version 2>&1 | head -1)"
echo "--- swiftc: $(swiftc --version 2>&1 | head -1)"
haxe tests/swift-ownership-check/check.hxml \
  -D swift-output="$OUT/gen" \
  -D swift-test-output="$OUT/tests"

sources=()
while IFS= read -r file; do
  sources+=("$file")
done < <(find "$OUT/gen" -name '*.swift' | sort)
sources+=("tests/swift-ownership-check/OwnershipMain.swift")
mkdir -p "$OUT/bin"
if ! swiftc -swift-version 5 -o "$OUT/bin/ownership-check" "${sources[@]}" >"$OUT/compile.log" 2>&1; then
  echo "--- swiftc failed; compiler output follows" >&2
  cat "$OUT/compile.log" >&2
  exit 1
fi
cat "$OUT/compile.log"

if ! "$OUT/bin/ownership-check" >"$OUT/run.log" 2>&1; then
  echo "--- ownership test failed; runner output follows" >&2
  cat "$OUT/run.log" >&2
  exit 1
fi
cat "$OUT/run.log"

grep -q '^b1 mapped=true data=4 number=42 numberOk=true array=1 arrayText=true dictText=true font=yes line=yes' "$OUT/run.log"
grep -Eq '^b2 runGlyphs=[1-9] changed=[1-9]' "$OUT/run.log"
grep -q '^b3 cached=true after=null' "$OUT/run.log"
