#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT_DIR"
mkdir -p out/ts-template-newline-escape out/nix-cache
export XDG_CACHE_HOME="$ROOT_DIR/out/nix-cache"
ATTEMPT_DIR="$(mktemp -d out/ts-template-newline-escape/datatable-XXXXXXXX)"
GEN_DIR="$ATTEMPT_DIR/gen"
TEST_DIR="$ATTEMPT_DIR/gen-tests"

record_inputs() {
    local destination="$1"
    {
        sha256sum packages/compiler/reflaxe/ts/tscompiler/TsExpr.hx \
            packages/compiler/reflaxe/ts/tscompiler/TsDecl.hx \
            samples/tests/DataTableTests.hx \
            samples/boring/PayloadTextTable.hx
    } > "$destination"
}

run_stage() {
    local label="$1"
    shift
    printf '%q ' "$@" > "$ATTEMPT_DIR/$label.command"
    printf '\n' >> "$ATTEMPT_DIR/$label.command"
    "$@" > "$ATTEMPT_DIR/$label.stdout" 2> "$ATTEMPT_DIR/$label.stderr"
    local status=$?
    printf '%s\n' "$status" > "$ATTEMPT_DIR/$label.exit"
    return "$status"
}

record_inputs "$ATTEMPT_DIR/inputs.before.sha256"
if ! run_stage generation nix develop -c haxe tests/haxe/ts-template-newline-escape/ts-datatable.hxml \
    -D "ts-output=$GEN_DIR" -D "ts-test-output=$TEST_DIR"; then
    record_inputs "$ATTEMPT_DIR/inputs.after.sha256"
    printf 'retained attempt: %s\n' "$ATTEMPT_DIR"
    exit 1
fi
cp "./$TEST_DIR/tests/DataTableTests.test.ts" "$ATTEMPT_DIR/DataTableTests.generated.ts" 2>/dev/null \
    || cp "$(find "$TEST_DIR" -name 'DataTableTests.test.ts' -print -quit)" "$ATTEMPT_DIR/DataTableTests.generated.ts"
if ! run_stage payload-roundtrip nix develop -c bun test "./$TEST_DIR/tests/DataTableTests.test.ts" -t "decodes back to the file content"; then
    record_inputs "$ATTEMPT_DIR/inputs.after.sha256"
    printf 'retained attempt: %s\n' "$ATTEMPT_DIR"
    exit 1
fi
record_inputs "$ATTEMPT_DIR/inputs.after.sha256"
printf 'retained attempt: %s\n' "$ATTEMPT_DIR"