#!/usr/bin/env bash
# The permanent macOS half of the Swift C interop check (task t-mwlbw8vp-frrq).
#
# Generates the Core Text sample, asserts the shapes the three mechanisms must
# emit, compiles the whole generated tree against the real macOS SDK, and runs
# the test so the measured ascent/descent come from real Core Text. The CI
# macos job runs this on every push and pull request; run it by hand with
#   bash tests/swift-coretext-check/run.sh [output-dir]
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"

OUT=${1:-out/swift-coretext-check/run}
rm -rf "$OUT"
mkdir -p "$OUT"

haxe tests/swift-coretext-check/check.hxml \
  -D swift-output="$OUT/gen" \
  -D swift-test-output="$OUT/gen-tests"

support=$(find "$OUT/gen" "$OUT/gen-tests" -name 'CoreTextMetricsSupport.swift' | head -1)
echo "--- generated shapes ($support)"
grep -q '^import CoreText$' "$support"
grep -q 'String(decoding: name, as: UTF16.self) as CFString' "$support"
grep -q 'withCString {' "$support"
grep -q 'withUnsafeBufferPointer {' "$support"
grep -q 'CTFontUIFontType.system' "$support"
grep -q 'CFStringBuiltInEncodings.UTF8.rawValue' "$support"
grep -q 'Int(Int32(units.count))' "$support"

# One Swift module: every generated file plus the test tree, exactly as the
# emitter lays it out.
mkdir -p "$OUT/bin"
swiftc -swift-version 5 -o "$OUT/bin/coretext-check" \
  $(find "$OUT/gen" "$OUT/gen-tests" -name '*.swift')

mkdir -p "$OUT/work"
cd "$OUT/work"
"$OUT/bin/coretext-check"

metrics="$OUT/work/out/swift-coretext-check/metrics.txt"
echo "--- measured Core Text metrics"
cat "$metrics"
grep -Eq '^named ascent=[0-9]' "$metrics"
grep -Eq '^cstring ascent=[0-9]' "$metrics"
grep -Eq '^units ascent=[0-9]' "$metrics"
grep -Eq '^system-ui ascent=[0-9]' "$metrics"
