#!/usr/bin/env bash
set -u

# Platform module import regression control, fixed zero-failure mode.
# std.Fs, std.Env, std.Process and StringTools lower at their call site or
# inline, so generated files must not import them as modules. The control
# generates the full sample set, scans every generated module for those
# import lines, typechecks the freshly generated tree through its own
# tsconfig, and runs the generated test tree requiring zero failures.

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
cd "$ROOT" || exit 2
if [ "${IN_NIX_SHELL:-}" = "" ]; then
    exec nix develop -c bash "$HERE/run.sh"
fi

PARENT=out/ts-platformops-imports
mkdir -p "$PARENT" || exit 2
RUN="$(mktemp -d "$PARENT/attempt-XXXXXXXX")" || exit 2
printf '%s\n' "$RUN"

INPUTS=(
    packages/compiler/reflaxe/ts/tscompiler/TsDecl.hx
    packages/compiler/reflaxe/ts/tscompiler/TsExpr.hx
    packages/compiler/reflaxe/ts/tscompiler/TsImports.hx
    packages/compiler/reflaxe/ts/tscompiler/TsType.hx
    samples/boring/PlatformOps.hx
    "$HERE/run.sh"
)
sha256sum "${INPUTS[@]}" >"$RUN/input-sha256.txt" || exit 2

run_stage() {
    local name="$1"
    shift
    printf '%q ' "$@" >"$RUN/$name.command"
    printf '\n' >>"$RUN/$name.command"
    "$@" >"$RUN/$name.stdout" 2>"$RUN/$name.stderr"
    local status=$?
    printf '%s\n' "$status" >"$RUN/$name.status"
    printf '%s status=%s\n' "$name" "$status"
    return "$status"
}

run_stage generate \
    haxe -v -cp samples -cp packages/registry/src -D ts-test-runner=bun \
    examples/ts.hxml -D "ts-output=$RUN/gen" \
    -D "ts-test-output=$RUN/gen-tests" || exit 1

# The typecheck below must see this attempt's tree. Refuse an empty or
# incomplete generation before any verdict is computed.
[ -s "$RUN/gen/boring/PlatformOps.ts" ] || {
    printf '%s\n' "generated tree misses PlatformOps.ts" >"$RUN/generate.reason"
    exit 1
}
gen_files=$(find "$RUN/gen" -name '*.ts' | wc -l)
[ "$gen_files" -gt 100 ] || {
    printf '%s\n' "generated tree suspiciously small: $gen_files files" \
        >"$RUN/generate.reason"
    exit 1
}
printf '%s\n' "$gen_files generated modules" >"$RUN/generate.verdict"

# The scan pattern names every module the emitter lowers without a module
# import line. It must not match the generated tree.
PATTERN='from "[^"]*(std/(Env|Fs|Process)|StringTools|haxe/io/FPHelper|haxe/ds/StringMap|/Type|/Lambda)\.ts"'
[ -n "$(find "$RUN/gen/boring" "$RUN/gen/std" "$RUN/gen/registry" -name '*.ts' -print -quit)" ] || {
    printf '%s\n' "scan target directories are empty" >"$RUN/phantom-scan.reason"
    exit 1
}
if grep -rnE "$PATTERN" "$RUN/gen/boring" "$RUN/gen/std" "$RUN/gen/registry" \
    >"$RUN/phantom-scan.stdout" 2>&1; then
    printf '%s\n' "phantom module import present" >"$RUN/phantom-scan.reason"
    exit 1
fi
printf '%s\n' "no phantom module imports" >"$RUN/phantom-scan.verdict"

# Negative control for the scan itself: an injected phantom import must be
# detected, so a silent scanner cannot pass this suite.
sed '2a import { Env } from "./../std/Env.ts";' \
    "$RUN/gen/boring/PlatformOps.ts" >"$RUN/injected-phantom.ts"
if ! grep -qE "$PATTERN" "$RUN/injected-phantom.ts"; then
    printf '%s\n' "scan failed to detect an injected phantom import" \
        >"$RUN/scan-negative.reason"
    exit 1
fi
printf '%s\n' "scan detects injected phantom" >"$RUN/scan-negative.verdict"

# Typecheck the freshly generated tree through its own tsconfig.
# Require a successful compiler exit and zero diagnostics.
python3 - "$RUN" "$ROOT" <<'PYCFG' || exit 2
import json, sys
run, root = sys.argv[1], sys.argv[2]
base = json.load(open(root + "/tsconfig.json"))
cfg = {
    "compilerOptions": dict(base["compilerOptions"]),
    "include": ["gen/**/*", "gen-tests/**/*"],
}
json.dump(cfg, open(run + "/tsconfig.generated.json", "w"), indent=2)
PYCFG
run_stage typecheck bash -c 'cd "$1" && exec "$2" -p tsconfig.generated.json --listFiles' \
    _ "$RUN" "$ROOT/node_modules/.bin/tsc"
status=$(cat "$RUN/typecheck.status")
if [ "$status" -ne 0 ]; then
    printf '%s\n' "expected successful generated-tree typecheck" \
        >"$RUN/typecheck.reason"
    exit 1
fi
cat "$RUN/typecheck.stdout" "$RUN/typecheck.stderr" >"$RUN/typecheck.combined"
# The file list proves tsc actually read this attempt's generated sources.
grep -q "gen/boring/PlatformOps.ts" "$RUN/typecheck.stdout" || {
    printf '%s\n' "typecheck file list misses PlatformOps.ts" >"$RUN/typecheck.reason"
    exit 1
}
seen=$(grep -c "gen/" "$RUN/typecheck.stdout" || true)
[ "$seen" -ge 100 ] || {
    printf '%s\n' "typecheck covered only $seen generated files" \
        >"$RUN/typecheck.reason"
    exit 1
}
diagnostics=$(grep -cE "error TS[0-9]+" "$RUN/typecheck.combined" || true)
if [ "$diagnostics" -ne 0 ]; then
    printf '%s\n' "$diagnostics diagnostics, expected zero" \
        >"$RUN/typecheck-categories.reason"
    exit 1
fi
printf '%s\n' "zero TypeScript diagnostics" >"$RUN/typecheck-categories.verdict"

# Generated test tree: fixed zero-failure mode.
run_stage bun-test bun test "$RUN/gen-tests"
if [ "$?" -ne 0 ]; then
    printf '%s\n' "generated test tree must exit 0" >"$RUN/bun-test.reason"
    exit 1
fi
if grep -q "(fail)" "$RUN/bun-test.stdout" "$RUN/bun-test.stderr"; then
    printf '%s\n' "failure entries present" >"$RUN/bun-test-failures.reason"
    exit 1
fi
if grep -qE "^error|error:" "$RUN/bun-test.stdout" "$RUN/bun-test.stderr"; then
    printf '%s\n' "error entries present" >"$RUN/bun-test-errors.reason"
    exit 1
fi
if grep -q "Cannot find module" "$RUN/bun-test.stdout" "$RUN/bun-test.stderr"; then
    printf '%s\n' "module resolution failure in the generated test tree" \
        >"$RUN/bun-test-module.reason"
    exit 1
fi
ran=$(grep -oE "Ran [0-9]+ tests" "$RUN/bun-test.stderr" | grep -oE "[0-9]+" | head -1)
[ -n "$ran" ] && [ "$ran" -gt 0 ] || {
    printf '%s\n' "no executed test count" >"$RUN/bun-test-count.reason"
    exit 1
}
printf '%s\n' "zero failures across $ran tests" >"$RUN/bun-test.verdict"

sha256sum "${INPUTS[@]}" >"$RUN/input-sha256-after.txt" || exit 2
cmp "$RUN/input-sha256.txt" "$RUN/input-sha256-after.txt" || exit 2
printf 'platform imports control passed: %s\n' "$RUN"
