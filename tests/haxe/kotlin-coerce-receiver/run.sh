#!/usr/bin/env bash
set -u
root="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$root" || exit 2
mkdir -p "$root/out/kotlin-coerce-receiver" || exit 2
run="$(mktemp -d "$root/out/kotlin-coerce-receiver/run-XXXXXXXX")" || exit 2
log="$run/logs"
mkdir -p "$log"
printf '%s\n' "$run" >"$root/out/kotlin-coerce-receiver/latest"
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

# Positive arm: the normal tree must generate and compile clean, and the
# fixture class must render each of the three receiver access forms at least
# once.
stage generate haxe tests/haxe/kotlin-coerce-receiver/kotlin.hxml -D "kotlin-output=$run/gen"
rc_gen=$?
if [ "$rc_gen" -ne 0 ]; then
    printf 'generate-outcome\t1\n' >>"$run/status.tsv"
    failed=1
else
    printf 'generate-outcome\t0\n' >>"$run/status.tsv"
fi

# Three access forms each at least once. The needles name the exact expected
# expressions, so a plain "." is never counted from "?." or "!!.":
#   finalChild.label   -> proven val        -> "."
#   varChild!!.label   -> proven var        -> "!!."
#   value?.label       -> unproven          -> "?."
receiver_kt="$run/gen/coercereceiver/ReceiverCases.kt"
if [ ! -f "$receiver_kt" ]; then
    printf 'receiver-kt-outcome\t1\n' >>"$run/status.tsv"
    failed=1
else
    printf 'receiver-kt-outcome\t0\n' >>"$run/status.tsv"
    for needle in 'finalChild.label' 'varChild!!.label' 'value?.label'; do
        if grep -qF "$needle" "$receiver_kt"; then
            printf 'form-%s\t0\n' "$needle" >>"$run/status.tsv"
        else
            printf 'form-%s\t1\n' "$needle" >>"$run/status.tsv"
            failed=1
        fi
    done
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

# Ablation arm: skip Receiver coercion. The member-access operator (".", "?.")
# is dropped, leaving receiverfield text; kotlinc must reject it.
stage generate-ablate haxe tests/haxe/kotlin-coerce-receiver/kotlin.hxml -D kotlin_coerce_ablate=Receiver -D "kotlin-output=$run/gen-ablate"
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
    else
        printf 'compile-ablate-outcome\t0\n' >>"$run/status.tsv"
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
