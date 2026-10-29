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
static_data_array_only="$attempt/static-data-array-only"
comprehension_only="$attempt/comprehension-only"
empty_default_only="$attempt/empty-default-only"
split_only="$attempt/split-only"
process_args_only="$attempt/process-args-only"
slice_only="$attempt/slice-only"
boundary_only="$attempt/boundary-only"
fs_readdir_only="$attempt/fs-readdir-only"

haxe tests/haxe/swift-runtime-closure/main.hxml -D "swift-output=$ordinary"
haxe tests/haxe/swift-runtime-closure/array-only.hxml -D "swift-output=$array_only"
haxe tests/haxe/swift-runtime-closure/scalar-array-only.hxml -D "swift-output=$scalar_array_only"
haxe tests/haxe/swift-runtime-closure/static-data-array-only.hxml -D "swift-output=$static_data_array_only"
haxe tests/haxe/swift-runtime-closure/test.hxml \
  -D "swift-output=$with_tests" \
  -D "swift-test-output=$tests"
haxe tests/haxe/swift-runtime-closure/comprehension-only.hxml -D "swift-output=$comprehension_only"
haxe tests/haxe/swift-runtime-closure/empty-default-only.hxml -D "swift-output=$empty_default_only"
haxe tests/haxe/swift-runtime-closure/split-only.hxml -D "swift-output=$split_only"
haxe tests/haxe/swift-runtime-closure/process-args-only.hxml -D "swift-output=$process_args_only"
haxe tests/haxe/swift-runtime-closure/slice-only.hxml -D "swift-output=$slice_only"
haxe tests/haxe/swift-runtime-closure/boundary-only.hxml -D "swift-output=$boundary_only"
haxe tests/haxe/swift-runtime-closure/fs-readdir-only.hxml -D "swift-output=$fs_readdir_only"

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

swiftc "$static_data_array_only/Runtime.swift" \
  "$static_data_array_only/StaticDataArrayOnly.swift" \
  "$static_data_array_only/std/UStringException.swift" \
  "$static_data_array_only/std/UStringFault.swift" \
  tests/haxe/swift-runtime-closure/native-static-data-array-only.swift \
  -o "$attempt/static-data-array-only-check"
static_data_array_only_result=$("$attempt/static-data-array-only-check")
test "$static_data_array_only_result" = 65
printf 'ordinary static data Array: %s\n' "$static_data_array_only_result"

swiftc "$comprehension_only/Runtime.swift" \
  "$comprehension_only/ComprehensionOnly.swift" \
  "$comprehension_only/std/UStringException.swift" \
  "$comprehension_only/std/UStringFault.swift" \
  tests/haxe/swift-runtime-closure/native-comprehension-only.swift \
  -o "$attempt/comprehension-only-check"
comprehension_result=$("$attempt/comprehension-only-check")
test "$comprehension_result" = 25
printf 'comprehension fill: %s\n' "$comprehension_result"

swiftc "$empty_default_only/Runtime.swift" \
  "$empty_default_only/EmptyDefaultOnly.swift" \
  "$empty_default_only/std/UStringException.swift" \
  "$empty_default_only/std/UStringFault.swift" \
  tests/haxe/swift-runtime-closure/native-empty-default-only.swift \
  -o "$attempt/empty-default-only-check"
empty_default_result=$("$attempt/empty-default-only-check")
test "$empty_default_result" = 10
printf 'empty default: %s\n' "$empty_default_result"

swiftc "$split_only/Runtime.swift" \
  "$split_only/SplitOnly.swift" \
  "$split_only/std/UStringException.swift" \
  "$split_only/std/UStringFault.swift" \
  tests/haxe/swift-runtime-closure/native-split-only.swift \
  -o "$attempt/split-only-check"
split_result=$("$attempt/split-only-check")
test "$split_result" = 33
printf 'string split: %s\n' "$split_result"

swiftc "$process_args_only/Runtime.swift" \
  "$process_args_only/ProcessArgsOnly.swift" \
  "$process_args_only/std/UStringException.swift" \
  "$process_args_only/std/UStringFault.swift" \
  tests/haxe/swift-runtime-closure/native-process-args-only.swift \
  -o "$attempt/process-args-only-check"
process_args_result=$("$attempt/process-args-only-check" a b c)
test "$process_args_result" = 3
printf 'process args: %s\n' "$process_args_result"

swiftc "$slice_only/Runtime.swift" \
  "$slice_only/SliceOnly.swift" \
  "$slice_only/std/UStringException.swift" \
  "$slice_only/std/UStringFault.swift" \
  tests/haxe/swift-runtime-closure/native-slice-only.swift \
  -o "$attempt/slice-only-check"
slice_result=$("$attempt/slice-only-check")
test "$slice_result" = 9
printf 'mutable slice: %s\n' "$slice_result"

swiftc "$boundary_only/Runtime.swift" \
  "$boundary_only/BoundaryOnly.swift" \
  "$boundary_only/std/UStringException.swift" \
  "$boundary_only/std/UStringFault.swift" \
  tests/haxe/swift-runtime-closure/native-boundary-only.swift \
  -o "$attempt/boundary-only-check"
boundary_result=$("$attempt/boundary-only-check")
test "$boundary_result" = 109
printf 'array boundary: %s\n' "$boundary_result"

fs_fixture_dir=/tmp/tq-swift-readdir-fixture
rm -rf "$fs_fixture_dir"
mkdir -p "$fs_fixture_dir"
touch "$fs_fixture_dir/alpha" "$fs_fixture_dir/beta"
swiftc "$fs_readdir_only/Runtime.swift" \
  "$fs_readdir_only/FsReadDirOnly.swift" \
  "$fs_readdir_only/std/FsError.swift" \
  "$fs_readdir_only/std/FsException.swift" \
  "$fs_readdir_only/std/UStringException.swift" \
  "$fs_readdir_only/std/UStringFault.swift" \
  tests/haxe/swift-runtime-closure/native-fs-readdir-only.swift \
  -o "$attempt/fs-readdir-only-check"
fs_readdir_result=$("$attempt/fs-readdir-only-check")
test "$fs_readdir_result" = 2
printf 'filesystem readDir: %s\n' "$fs_readdir_result"

for rt in \
  "$ordinary/Runtime.swift" \
  "$array_only/Runtime.swift" \
  "$scalar_array_only/Runtime.swift" \
  "$static_data_array_only/Runtime.swift" \
  "$with_tests/Runtime.swift" \
  "$comprehension_only/Runtime.swift" \
  "$empty_default_only/Runtime.swift" \
  "$split_only/Runtime.swift" \
  "$process_args_only/Runtime.swift" \
  "$slice_only/Runtime.swift" \
  "$boundary_only/Runtime.swift" \
  "$fs_readdir_only/Runtime.swift"; do
  test "$(rg -c '^public final class BoringArray<' "$rt")" = 1
  test "$(rg -c '^public final class ReadOnlyArray<' "$rt")" = 1
done

test_host_count=$(rg -c '^public final class (BoringArray|ReadOnlyArray)<' "$with_tests/Test.swift" || printf '0')
test "$test_host_count" = 0

swiftc "$with_tests/Runtime.swift" \
  "$with_tests/Test.swift" \
  "$with_tests/Main.swift" \
  "$with_tests/std/UStringException.swift" \
  "$with_tests/std/UStringFault.swift" \
  "$tests/closureFixture/ClosureTests.swift" \
  "$tests/TestMain.swift" \
  -o "$attempt/test-check"
BORING_TEST_RESULTS="$attempt/results.jsonl" \
  "$attempt/test-check"
rg -q '"verdict":"pass"' "$attempt/results.jsonl"
printf 'attempt: %s\n' "$attempt"
printf 'test host: passed\n'
