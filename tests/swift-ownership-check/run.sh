#!/usr/bin/env bash
# The macOS execution half of blocks B and C: ARC-visible CF values, borrowed
# pointers, the class-reference cache, and CF container construction.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"

OUT=${1:-out/swift-ownership-check/run}
rm -rf "$OUT"
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

echo "--- haxe: $(haxe --version 2>&1 | head -1)"
echo "--- swiftc: $(swiftc --version 2>&1 | head -1)"

compile_and_run() {
  local hxml=$1
  local gen=$2
  local tests=$3
  local main=$4
  local binary=$5
  local log=$6
  haxe "$hxml" -D swift-output="$gen" -D swift-test-output="$tests"
  local sources=()
  while IFS= read -r file; do
    sources+=("$file")
  done < <(find "$gen" -name '*.swift' | sort)
  sources+=("$main")
  mkdir -p "$OUT/bin"
  if ! swiftc -swift-version 5 -o "$OUT/bin/$binary" "${sources[@]}" >"$OUT/$binary-compile.log" 2>&1; then
    echo "--- swiftc failed for $binary; compiler output follows" >&2
    cat "$OUT/$binary-compile.log" >&2
    exit 1
  fi
  cat "$OUT/$binary-compile.log"
  if ! "$OUT/bin/$binary" >"$log" 2>&1; then
    echo "--- $binary failed; runner output follows" >&2
    cat "$log" >&2
    exit 1
  fi
  cat "$log"
}

compile_and_run tests/swift-ownership-check/check.hxml "$OUT/gen" "$OUT/tests" \
  tests/swift-ownership-check/OwnershipMain.swift ownership-check "$OUT/run.log"
grep -q '^b1 mapped=true data=4 number=42 numberOk=true array=1 arrayText=true dictText=true font=yes line=yes' "$OUT/run.log"
grep -Eq '^b2 runGlyphs=[1-9] changed=[1-9]' "$OUT/run.log"
grep -q '^b3 cached=true after=null' "$OUT/run.log"

compile_and_run tests/swift-ownership-check/check-c.hxml "$OUT/c-gen" "$OUT/c-tests" \
  tests/swift-ownership-check/CContainerMain.swift container-check "$OUT/c-run.log"
grep -q '^c1 family=true' "$OUT/c-run.log"
grep -q '^c2 font=true' "$OUT/c-run.log"
grep -q '^c3 font=true' "$OUT/c-run.log"
grep -q '^c4 count=2 order=true' "$OUT/c-run.log"
