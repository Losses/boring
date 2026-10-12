#!/usr/bin/env bash
set -u
root="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$root" || exit 2
mkdir -p "$root/out/kotlin-coerce-range" || exit 2
run="$(mktemp -d "$root/out/kotlin-coerce-range/run-XXXXXXXX")" || exit 2
log="$run/logs"
mkdir -p "$log"
printf '%s\n' "$run" >"$root/out/kotlin-coerce-range/latest"
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
failed=0
rc_compile=1
rc_compile_ablate=1

# Positive arm: the normal tree must generate and compile clean.
stage generate haxe tests/haxe/kotlin-coerce-range/kotlin.hxml -D "kotlin-output=$run/gen"
rc_gen=$?
if [ "$rc_gen" -ne 0 ]; then
    printf 'generate-outcome\t1\n' >>"$run/status.tsv"
    failed=1
else
    printf 'generate-outcome\t0\n' >>"$run/status.tsv"
fi

ktfiles="$(find "$run/gen" -name '*.kt' -print | sort)"
if [ -z "$ktfiles" ]; then
    printf 'compile-outcome\t1\n' >>"$run/status.tsv"
    failed=1
else
    stage compile kotlinc $ktfiles -d "$run/normal.jar"
    rc_compile=$?
    if [ "$rc_compile" -ne 0 ]; then
        printf 'compile-outcome\t1\n' >>"$run/status.tsv"
        failed=1
    else
        printf 'compile-outcome\t0\n' >>"$run/status.tsv"
    fi
fi

# Ablation arm: skip RangeBound coercion; the nullable endpoint survives and
# kotlinc must reject it with a range-endpoint type mismatch.
stage generate-ablate haxe tests/haxe/kotlin-coerce-range/kotlin.hxml -D kotlin_coerce_ablate=RangeBound -D "kotlin-output=$run/gen-ablate"
rc_gen_ablate=$?
if [ "$rc_gen_ablate" -ne 0 ]; then
    printf 'generate-ablate-outcome\t1\n' >>"$run/status.tsv"
    failed=1
else
    printf 'generate-ablate-outcome\t0\n' >>"$run/status.tsv"
fi

ktfiles_ablate="$(find "$run/gen-ablate" -name '*.kt' -print | sort)"
if [ -z "$ktfiles_ablate" ]; then
    printf 'compile-ablate-outcome\t1\n' >>"$run/status.tsv"
    failed=1
else
    stage compile-ablate kotlinc $ktfiles_ablate -d "$run/ablate.jar"
    rc_compile_ablate=$?
    if [ "$rc_compile_ablate" -eq 0 ]; then
        printf 'compile-ablate-outcome\t1\n' >>"$run/status.tsv"
        failed=1
    elif grep -qF 'type mismatch' "$log/compile-ablate.stderr"; then
        printf 'compile-ablate-outcome\t0\n' >>"$run/status.tsv"
    else
        printf 'compile-ablate-outcome\t1\n' >>"$run/status.tsv"
        failed=1
    fi
fi

# GP-ABLATE: the two compile arms must differ (normal compiles, ablate rejects).
if [ "$rc_compile" -eq "$rc_compile_ablate" ]; then
    printf 'rc-differ-outcome\t1\n' >>"$run/status.tsv"
    failed=1
else
    printf 'rc-differ-outcome\t0\n' >>"$run/status.tsv"
fi

printf '%s\n' "$run"
exit "$failed"

