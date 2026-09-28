#!/usr/bin/env bash
set -euo pipefail

output_root=${SWIFT_RUNTIME_CLOSURE_OUTPUT_ROOT:-out/swift-runtime-closure}
mkdir -p "$output_root"
attempt=$(mktemp -d "$output_root/attempt-XXXXXXXX")
ordinary="$attempt/ordinary"
array_only="$attempt/array-only"
scalar_array_only="$attempt/scalar-array-only"
with_tests="$attempt/with-tests"
tests="$attempt/tests"

haxe tests/haxe/swift-runtime-closure/main.hxml -D "swift-output=$ordinary"
haxe tests/haxe/swift-runtime-closure/array-only.hxml -D "swift-output=$array_only"
haxe tests/haxe/swift-runtime-closure/scalar-array-only.hxml -D "swift-output=$scalar_array_only"
haxe tests/haxe/swift-runtime-closure/test.hxml \
  -D "swift-output=$with_tests" \
  -D "swift-test-output=$tests"

swiftc "$ordinary/Runtime.swift" \
  "$ordinary/Main.swift" \
  "$ordinary/std/UStringException.swift" \
  "$ordinary/std/UStringFault.swift" \
  tests/haxe/swift-runtime-closure/native-main.swift \
  -o "$attempt/ordinary-check"
ordinary_result=$("$attempt/ordinary-check")
test "$ordinary_result" = 5
printf 'ordinary read-only view: %s\n' "$ordinary_result"

swiftc "$array_only/Runtime.swift" \
  "$array_only/ArrayOnly.swift" \
  "$array_only/std/UStringException.swift" \
  "$array_only/std/UStringFault.swift" \
  tests/haxe/swift-runtime-closure/native-array-only.swift \
  -o "$attempt/array-only-check"
array_result=$("$attempt/array-only-check")
test "$array_result" = 4
printf 'ordinary Array only: %s\n' "$array_result"

swiftc "$scalar_array_only/ScalarArrayOnly.swift" \
  "$scalar_array_only/Runtime.swift" \
  "$scalar_array_only/std/UStringException.swift" \
  "$scalar_array_only/std/UStringFault.swift" \
  tests/haxe/swift-runtime-closure/native-scalar-array-only.swift \
  -o "$attempt/scalar-array-only-check"
scalar_result=$("$attempt/scalar-array-only-check")
test "$scalar_result" = 7
printf 'scalar array expression: %s\n' "$scalar_result"

test "$(rg -c '^public final class TiqianArray<' "$ordinary/Runtime.swift")" = 1
test "$(rg -c '^public final class ReadOnlyArray<' "$ordinary/Runtime.swift")" = 1
test "$(rg -c '^public final class TiqianArray<' "$array_only/Runtime.swift")" = 1
test "$(rg -c '^public final class ReadOnlyArray<' "$array_only/Runtime.swift")" = 1
test "$(rg -c '^public final class TiqianArray<' "$scalar_array_only/Runtime.swift")" = 1
test "$(rg -c '^public final class ReadOnlyArray<' "$scalar_array_only/Runtime.swift")" = 1
test "$(rg -c '^public final class TiqianArray<' "$with_tests/Runtime.swift")" = 1
test "$(rg -c '^public final class ReadOnlyArray<' "$with_tests/Runtime.swift")" = 1
test_host_count=$(rg -c '^public final class (TiqianArray|ReadOnlyArray)<' "$with_tests/Test.swift" || printf '0')
test "$test_host_count" = 0

swiftc "$with_tests/Runtime.swift" \
  "$with_tests/Test.swift" \
  "$with_tests/Main.swift" \
  "$with_tests/std/UStringException.swift" \
  "$with_tests/std/UStringFault.swift" \
  "$tests/closureFixture/ClosureTests.swift" \
  "$tests/TestMain.swift" \
  -o "$attempt/test-check"
BORING_TEST_RESULTS="$PWD/$attempt/results.jsonl" \
  "$attempt/test-check"
rg -q '"verdict":"pass"' "$attempt/results.jsonl"
printf 'attempt: %s\n' "$attempt"
printf 'test host: passed\n'
