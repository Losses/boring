#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT_DIR"
mkdir -p out/ts-nullable-lowering out/nix-cache
export XDG_CACHE_HOME="$ROOT_DIR/out/nix-cache"
ATTEMPT_DIR="$(mktemp -d out/ts-nullable-lowering/attempt-XXXXXXXX)"
GEN_DIR="$ATTEMPT_DIR/gen"

record_inputs() {
    local destination="$1"
    {
        sha256sum packages/compiler/reflaxe/ts/tscompiler/TsExpr.hx \
            packages/compiler/reflaxe/ts/tscompiler/TsDecl.hx \
            tests/haxe/ts-nullable-lowering/NullableShapes.hx
        find tests/haxe/ts-nullable-lowering -type f -print0 | sort -z | xargs -0 sha256sum
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
if ! run_stage generation nix develop -c haxe -v tests/haxe/ts-nullable-lowering/ts-nullable.hxml -D "ts-output=$GEN_DIR"; then
    record_inputs "$ATTEMPT_DIR/inputs.after.sha256"
    printf 'retained attempt: %s\n' "$ATTEMPT_DIR"
    exit 1
fi
cp "$GEN_DIR/NullableShapes.ts" "$ATTEMPT_DIR/NullableShapes.generated.ts"
if ! run_stage strict-tsc nix develop -c node_modules/.bin/tsc --noEmit --target ES2022 --module esnext --moduleResolution bundler --strict --types bun "$GEN_DIR/NullableShapes.ts"; then
    record_inputs "$ATTEMPT_DIR/inputs.after.sha256"
    printf 'retained attempt: %s\n' "$ATTEMPT_DIR"
    exit 1
fi
if ! run_stage check-tsc nix develop -c node_modules/.bin/tsc --noEmit --target ES2022 --module esnext --moduleResolution bundler --strict --types bun tests/haxe/ts-nullable-lowering/check.ts; then
    record_inputs "$ATTEMPT_DIR/inputs.after.sha256"
    printf 'retained attempt: %s\n' "$ATTEMPT_DIR"
    exit 1
fi
if ! run_stage runtime nix develop -c bun tests/haxe/ts-nullable-lowering/check.ts "$GEN_DIR/NullableShapes.ts"; then
    record_inputs "$ATTEMPT_DIR/inputs.after.sha256"
    printf 'retained attempt: %s\n' "$ATTEMPT_DIR"
    exit 1
fi
record_inputs "$ATTEMPT_DIR/inputs.after.sha256"
printf 'retained attempt: %s\n' "$ATTEMPT_DIR"
