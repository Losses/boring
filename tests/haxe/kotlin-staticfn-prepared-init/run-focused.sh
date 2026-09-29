#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT_DIR"
mkdir -p out/kotlin-staticfn-prepared-init out/nix-cache
export XDG_CACHE_HOME="$ROOT_DIR/out/nix-cache"
ATTEMPT_DIR="$(mktemp -d out/kotlin-staticfn-prepared-init/attempt-XXXXXXXX)"

record_inputs() {
    local destination="$1"
    {
        sha256sum packages/compiler/reflaxe/kotlin/kotlincompiler/KotlinDecl.hx \
            packages/compiler/reflaxe/kotlin/kotlincompiler/KotlinExpr.hx \
            packages/compiler/reflaxe/kotlin/kotlincompiler/KotlinPreparedFunction.hx \
            samples/boring/StaticFnOps.hx
        find tests/haxe/kotlin-staticfn-prepared-init -type f -print0 | sort -z | xargs -0 sha256sum
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
if ! run_stage generation nix develop -c haxe tests/haxe/kotlin-staticfn-prepared-init/kotlin-gen.hxml; then
    record_inputs "$ATTEMPT_DIR/inputs.after.sha256"
    printf 'retained attempt: %s\n' "$ATTEMPT_DIR"
    exit 1
fi
mapfile -d '' KOTLIN_SOURCES < <(find out/kotlin-staticfn-prepared-init/kotlin-gen/boring out/kotlin-staticfn-prepared-init/kotlin-gen/ksfshapes -name '*.kt' -print0 | sort -z)
if ! run_stage kotlin-compile nix develop -c kotlinc "${KOTLIN_SOURCES[@]}" \
    tests/haxe/kotlin-staticfn-prepared-init/StaticFnRunner.kt \
    tests/haxe/kotlin-staticfn-prepared-init/StaticFnShapesRunner.kt \
    -include-runtime -d "$ATTEMPT_DIR/staticfn.jar"; then
    record_inputs "$ATTEMPT_DIR/inputs.after.sha256"
    printf 'retained attempt: %s\n' "$ATTEMPT_DIR"
    exit 1
fi
if ! run_stage jvm nix develop -c java -cp "$ATTEMPT_DIR/staticfn.jar" StaticFnRunnerKt; then
    record_inputs "$ATTEMPT_DIR/inputs.after.sha256"
    printf 'retained attempt: %s\n' "$ATTEMPT_DIR"
    exit 1
fi
if ! run_stage jvm-shapes nix develop -c java -cp "$ATTEMPT_DIR/staticfn.jar" StaticFnShapesRunnerKt; then
    record_inputs "$ATTEMPT_DIR/inputs.after.sha256"
    printf 'retained attempt: %s\n' "$ATTEMPT_DIR"
    exit 1
fi
record_inputs "$ATTEMPT_DIR/inputs.after.sha256"
printf 'retained attempt: %s\n' "$ATTEMPT_DIR"