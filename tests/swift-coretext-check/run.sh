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
# The test runs from a work directory under OUT, so every path reused after
# that cd has to be absolute.
OUT=$(cd "$OUT" && pwd)

echo "--- haxe: $(haxe --version 2>&1 | head -1)"
echo "--- swiftc: $(swiftc --version 2>&1 | head -1)"
echo "--- generating the Core Text sample"
haxe tests/swift-coretext-check/check.hxml \
  -D swift-output="$OUT/gen" \
  -D swift-test-output="$OUT/gen-tests"

support=$(find "$OUT/gen" "$OUT/gen-tests" -name 'CoreTextMetricsSupport.swift' | sed -n '1p')
if [ -z "$support" ]; then
  echo "--- CoreTextMetricsSupport.swift was not generated" >&2
  find "$OUT" -type f | head -40 >&2
  exit 1
fi
echo "--- generated import and bridges ($support)"
head -2 "$support"
for shape in \
  '^import CoreText$' \
  'String(decoding: name, as: UTF16.self) as CFString' \
  'withCString {' \
  'withUnsafeBufferPointer {' \
  'CTFontUIFontType.system' \
  'CFStringBuiltInEncodings.UTF8.rawValue' \
  'Int(Int32(units.count))'; do
  if ! grep -q "$shape" "$support"; then
    echo "--- missing generated shape: $shape" >&2
    exit 1
  fi
done

sources=()
while IFS= read -r file; do
  sources+=("$file")
done < <(find "$OUT/gen" "$OUT/gen-tests" -name '*.swift' | sort)
echo "--- swiftc sources (${#sources[@]} files)"
printf '    %s\n' "${sources[@]}"
mkdir -p "$OUT/bin"
if ! swiftc -swift-version 5 -o "$OUT/bin/coretext-check" "${sources[@]}" >"$OUT/compile.log" 2>&1; then
  echo "--- swiftc failed; compiler output follows" >&2
  cat "$OUT/compile.log" >&2
  exit 1
fi
cat "$OUT/compile.log"

mkdir -p "$OUT/work"
cd "$OUT/work"
if ! "$OUT/bin/coretext-check" >"$OUT/run.log" 2>&1; then
  echo "--- Core Text test failed; runner output follows" >&2
  cat "$OUT/run.log" >&2
  exit 1
fi
cat "$OUT/run.log"

metrics="$OUT/work/out/swift-coretext-check/metrics.txt"
echo "--- measured Core Text metrics"
cat "$metrics"
grep -Eq '^named ascent=[0-9]' "$metrics"
grep -Eq '^cstring ascent=[0-9]' "$metrics"
grep -Eq '^units ascent=[0-9]' "$metrics"
grep -Eq '^system-ui ascent=[0-9]' "$metrics"
