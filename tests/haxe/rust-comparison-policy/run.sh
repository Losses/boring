#!/usr/bin/env bash
set -u
root="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$root" || exit 2
mkdir -p "$root/out/rust-comparison-policy" || exit 2
run="$(mktemp -d "$root/out/rust-comparison-policy/run-XXXXXXXX")" || exit 2
log="$run/logs"
mkdir -p "$log"
printf '%s\n' "$run" >"$root/out/rust-comparison-policy/latest"
git rev-parse HEAD >"$run/base-head"
sha256sum \
    packages/compiler/SourceComparisonAnalysis.hx \
    packages/compiler/SemanticPassRegistry.hx \
    packages/compiler/reflaxe/rust/rustcompiler/RustDecl.hx \
    packages/compiler/reflaxe/rust/rustcompiler/RustType.hx \
    packages/compiler/reflaxe/rust/rustcompiler/RustExpr.hx \
    tests/haxe/comparison-runtime-observation/comparison/ComparisonObserve.hx \
    tests/haxe/comparison-runtime-observation/comparison/ParameterCompositionCases.hx \
    tests/haxe/rust-comparison-policy/rust.hxml \
    tests/haxe/rust-comparison-policy/reject-float-key.hxml \
    tests/haxe/rust-comparison-policy/reject-record-parameter.hxml \
    tests/haxe/rust-comparison-policy/unused-param-key.hxml \
    tests/haxe/rust-comparison-policy/comparison/GenericRustKey.hx \
    tests/haxe/rust-comparison-policy/comparison/RejectFloatKey.hx \
    tests/haxe/rust-comparison-policy/comparison/RejectRecordParameter.hx \
    tests/haxe/rust-comparison-policy/comparison/UnusedParamKeyCase.hx \
    tests/haxe/rust-comparison-policy/native/harness.rs \
    tests/haxe/rust-comparison-policy/native/harness-unused-param.rs \
    tests/haxe/rust-comparison-policy/expected.tsv \
    tests/haxe/rust-comparison-policy/run.sh >"$run/inputs.sha256"
printf 'stage\texit\n' >"$run/status.tsv"
stage() {
    local name="$1"
    shift
    printf '%q ' "$@" >"$log/$name.command"
    printf '\n' >>"$log/$name.command"
    "$@" >"$log/$name.stdout" 2>"$log/$name.stderr"
    local rc=$?
    printf '%s\n' "$rc" >"$log/$name.exit"
    printf '%s\t%s\n' "$name" "$rc" >>"$run/status.tsv"
    return "$rc"
}
stage haxe haxe tests/haxe/rust-comparison-policy/rust.hxml \
    -D "rust-output=$run/gen" || exit 1
stage rustc-library rustc --edition=2024 --crate-type lib --crate-name cmpgen \
    -o "$run/libcmpgen.rlib" "$run/gen/lib.rs" || exit 1
stage rustc-harness rustc --edition=2024 -o "$run/harness" \
    tests/haxe/rust-comparison-policy/native/harness.rs \
    --extern "cmpgen=$run/libcmpgen.rlib" || exit 1
failed=0
while IFS=$'\t' read -r name expected; do
    [ "$name" = case ] && continue
    stage "run-$name" "$run/harness" "$name" || { failed=1; continue; }
    printf '%s\n' "$expected" >"$log/run-$name.expected"
    cmp -s "$log/run-$name.expected" "$log/run-$name.stdout"
    rc=$?
    printf '%s\n' "$rc" >"$log/run-$name.compare-exit"
    [ "$rc" -eq 0 ] || failed=1
done <tests/haxe/rust-comparison-policy/expected.tsv

# Negative control: a stored Float field is outside the sorted-key domain.
# The source gate rejects the builder construction with the domain
# diagnostic; a zero exit or a different diagnostic defeats the control.
stage reject-float-key haxe tests/haxe/rust-comparison-policy/reject-float-key.hxml \
    -D "rust-output=$run/gen-reject-float-key"
if [ "$?" -eq 0 ]; then
    printf 'reject-float-key-outcome\t1\n' >>"$run/status.tsv"
    failed=1
else
    if grep -qF 'Float is outside the sorted-key domain' "$log/reject-float-key.stderr"; then
        printf 'reject-float-key-outcome\t0\n' >>"$run/status.tsv"
    else
        printf 'reject-float-key-outcome\t1\n' >>"$run/status.tsv"
        failed=1
    fi
fi

# Negative control: a generic key whose parameter is bound to a record type.
# The source gates admit the shape, so generation exits zero; the
# parameter trait supplies u32 and UString only, so the target compiler
# rejects the instantiation with the missing trait bound diagnostic. A zero
# rustc exit or a different error defeats the control.
stage reject-record-parameter haxe tests/haxe/rust-comparison-policy/reject-record-parameter.hxml \
    -D "rust-output=$run/gen-reject-record-parameter"
if [ "$?" -ne 0 ]; then
    printf 'reject-record-parameter-outcome\t1\n' >>"$run/status.tsv"
    failed=1
else
    stage reject-record-parameter-rustc rustc --edition=2024 --crate-type lib --crate-name cmpgenreject \
        -o "$run/libcmpgenreject.rlib" "$run/gen-reject-record-parameter/lib.rs"
    if [ "$?" -eq 0 ]; then
        printf 'reject-record-parameter-outcome\t1\n' >>"$run/status.tsv"
        failed=1
    elif grep -qF 'E0277' "$log/reject-record-parameter-rustc.stderr"; then
        printf 'reject-record-parameter-outcome\t0\n' >>"$run/status.tsv"
    else
        printf 'reject-record-parameter-outcome\t1\n' >>"$run/status.tsv"
        failed=1
    fi
fi

# End-to-end acceptance: a generic key whose parameter takes no stored
# field. The plan has no direct comparison obligation for the parameter,
# so the comparator takes no trait bound for it. The struct carries the
# parameter as a zero-sized PhantomData marker. The full crate must
# compile, and the builder run at a record type must report the stored
# field order.
stage unused-param-key haxe tests/haxe/rust-comparison-policy/unused-param-key.hxml \
    -D "rust-output=$run/gen-unused-param-key" || exit 1
stage unused-param-key-rustc rustc --edition=2024 --crate-type lib --crate-name cmpunused \
    -o "$run/libcmpunused.rlib" "$run/gen-unused-param-key/lib.rs" || exit 1
stage unused-param-key-harness rustc --edition=2024 -o "$run/harness-unused-param" \
    tests/haxe/rust-comparison-policy/native/harness-unused-param.rs \
    --extern "cmpgen=$run/libcmpunused.rlib" || exit 1
stage unused-param-key-run "$run/harness-unused-param" unused-param-key || exit 1
printf 'amount=AB\n' >"$log/unused-param-key.expected"
cmp -s "$log/unused-param-key.expected" "$log/unused-param-key-run.stdout"
if [ "$?" -eq 0 ]; then
    printf 'unused-param-key-outcome\t0\n' >>"$run/status.tsv"
else
    printf 'unused-param-key-outcome\t1\n' >>"$run/status.tsv"
    failed=1
fi

# Negative control: a mutated expectation must be detected by the comparison
# step. The compiled harness runs one case and the result is compared against
# a deliberately wrong line; a matching comparison defeats the control.
printf '%q ' "$run/harness" generic-sequence >"$log/mutation.command"
printf '\n' >>"$log/mutation.command"
"$run/harness" generic-sequence >"$log/mutation.stdout" 2>"$log/mutation.stderr"
printf '%s\n' "$?" >"$log/mutation.exit"
printf 'signed=BA;utf16=AB\n' >"$log/mutation.expected"
cmp -s "$log/mutation.expected" "$log/mutation.stdout"
mutation_cmp=$?
printf '%s\n' "$mutation_cmp" >"$log/mutation.compare-exit"
if [ "$mutation_cmp" -ne 0 ]; then
    printf 'mutation\t0\n' >>"$run/status.tsv"
else
    printf 'mutation\t1\n' >>"$run/status.tsv"
    failed=1
fi

# Zero new numeric casts in the generated comparison code. The comparator
# reinterprets same-width integer storage into the signed i32 domain by
# byte copy, never by an as cast. The predicate matches the primitive i32
# cast text emitted at the comparator sites; a UFCS path such as
# `<T as CompareParameterWitness>` names a trait, never a primitive, so it
# cannot match, and the negative control below pins both the hit and the
# exclusion on one planted probe file.
CAST_RE='\bas i32\b'
stage no-as-cast bash -c 'if grep -rnE "$1" "$2" "$3" "$4"; then exit 1; fi' _ \
    "$CAST_RE" \
    "$run/gen/comparison" \
    "$run/gen-unused-param-key/comparison" \
    "$run/gen-reject-record-parameter/comparison" || failed=1

# Negative control for the guard: a planted probe file carries one line with
# the emitted cast form and one line with the UFCS trait syntax. The
# predicate must count exactly one matching line; counting zero defeats the
# detection, counting two fails the UFCS exclusion.
{
    printf 'fn cast_probe(a: &u32, b: &u32) -> i32 { (*a as i32).cmp(&(*b as i32)) as i32 }\n'
    printf 'fn ufcs_probe<T: CompareParameterWitness>(a: &T, b: &T) -> i32 { <T as CompareParameterWitness>::compare_order(a, b) }\n'
} >"$log/no-as-cast-probe.rs"
stage no-as-cast-negative bash -c 'n="$(grep -cE "$1" "$2")"; [ "$n" = "1" ]' _ \
    "$CAST_RE" "$log/no-as-cast-probe.rs" || failed=1

printf '%s\n' "$run"
exit "$failed"
