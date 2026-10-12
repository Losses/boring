#!/usr/bin/env bash
set -u
root="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$root" || exit 2
mkdir -p "$root/out/rust-refer-unresolved" || exit 2
run="$(mktemp -d "$root/out/rust-refer-unresolved/run-XXXXXXXX")" || exit 2
log="$run/logs"
mkdir -p "$log"
printf '%s
' "$run" >"$root/out/rust-refer-unresolved/latest"
printf 'stage	exit
' >"$run/status.tsv"
stage() {
    local name="$1"
    shift
    printf '%q ' "$@" >"$log/$name.command"
    printf '
' >>"$log/$name.command"
    "$@" >"$log/$name.stdout" 2>"$log/$name.stderr"
    local rc=$?
    printf '%s
' "$rc" >"$log/$name.exit"
    printf '%s	%s
' "$name" "$rc" >>"$run/status.tsv"
    return "$rc"
}
failed=0

# Positive control: the planted phantom reference must fail generation with
# the "unresolved symbol" diagnostic; a zero exit or a different diagnostic
# defeats the control.
stage refer-unresolved haxe tests/haxe/rust-refer-unresolved/rust.hxml     -D "rust-output=$run/gen"
rc_no_ablate=$?
if [ "$rc_no_ablate" -eq 0 ]; then
    printf 'refer-unresolved-outcome	1
' >>"$run/status.tsv"
    failed=1
else
    if grep -qF 'unresolved symbol' "$log/refer-unresolved.stderr"; then
        printf 'refer-unresolved-outcome	0
' >>"$run/status.tsv"
    else
        printf 'refer-unresolved-outcome	1
' >>"$run/status.tsv"
        failed=1
    fi
fi

# Ablation control: -D rust_refer_ablate skips the end-of-generation check,
# so the same fixture must exit zero.
stage refer-ablate haxe tests/haxe/rust-refer-unresolved/rust.hxml     -D rust_refer_ablate -D "rust-output=$run/gen-ablate"
rc_ablate=$?
if [ "$rc_ablate" -ne 0 ]; then
    printf 'refer-ablate-outcome	1
' >>"$run/status.tsv"
    failed=1
else
    printf 'refer-ablate-outcome	0
' >>"$run/status.tsv"
fi

# GP-ABLATE: the two arms must exit differently.
if [ "$rc_no_ablate" -eq "$rc_ablate" ]; then
    printf 'rc-differ-outcome	1
' >>"$run/status.tsv"
    failed=1
else
    printf 'rc-differ-outcome	0
' >>"$run/status.tsv"
fi

printf '%s
' "$run"
exit "$failed"
