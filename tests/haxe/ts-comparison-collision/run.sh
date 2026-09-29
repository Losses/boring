#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT" || exit 2
RUN="$(mktemp -d out/ts-comparison-collision-XXXXXXXX)" || exit 2
printf 'run=%s\n' "$RUN"
sha256sum \
    tests/haxe/ts-comparison-collision/ts.hxml \
    tests/haxe/ts-comparison-collision/run.sh \
    tests/haxe/ts-comparison-collision/run.ts \
    tests/haxe/ts-comparison-collision/comparisoncollision/PairKey.hx \
    tests/haxe/ts-comparison-collision/comparisoncollision/first/Point.hx \
    tests/haxe/ts-comparison-collision/comparisoncollision/second/Point.hx \
    tests/haxe/ts-comparison-collision/comparisoncollision/first/Color.hx \
    tests/haxe/ts-comparison-collision/comparisoncollision/second/Color.hx \
    tests/haxe/ts-comparison-collision/comparisoncollision/TintedKey.hx \
    tests/haxe/ts-comparison-collision/comparisoncollision/TintedHolder.hx \
    tests/haxe/ts-comparison-collision/comparisoncollision/ColorMaker.hx \
    tests/haxe/ts-comparison-collision/comparisoncollision/pair/Pair.hx \
    tests/haxe/ts-comparison-collision/comparisoncollision/pair/other/Pair.hx \
    tests/haxe/ts-comparison-collision/comparisoncollision/pair/other2/Pair.hx \
    tests/haxe/ts-comparison-collision/comparisoncollision/pair/Shell.hx \
    packages/compiler/SourceComparisonAnalysis.hx \
    packages/compiler/reflaxe/ts/tscompiler/TsType.hx \
    packages/compiler/reflaxe/ts/tscompiler/TsExpr.hx \
    packages/compiler/reflaxe/ts/tscompiler/TsDecl.hx \
    packages/compiler/reflaxe/ts/tscompiler/TsImports.hx \
    packages/compiler/reflaxe/ts/tscompiler/TsType.hx \
    packages/compiler/SourceComparisonAnalysis.hx > "$RUN/input-sha256.txt"
run_stage() {
    local name="$1"
    shift
    printf '%s\0' "$@" > "$RUN/$name.argv"
    "$@" > "$RUN/$name.stdout" 2> "$RUN/$name.stderr"
    local status=$?
    printf '%s\n' "$status" > "$RUN/$name.status"
    printf '%s=%s\n' "$name" "$status"
    return "$status"
}
run_stage generate haxe tests/haxe/ts-comparison-collision/ts.hxml -D "ts-output=$RUN/ts-gen" || exit 1
cp tests/haxe/ts-comparison-collision/run.ts "$RUN/ts-gen/run.ts" || exit 2
run_stage typecheck "${TSC:-node_modules/.bin/tsc}" --noEmit --strict --noUncheckedIndexedAccess --target ESNext --module ESNext --moduleResolution bundler --allowImportingTsExtensions --types bun --skipLibCheck "$RUN/ts-gen/run.ts" || exit 1
run_stage execute bun "$RUN/ts-gen/run.ts" || exit 1
# Mutation gate on a copy: the positive-case generated tree stays
# untouched. A corrupted enum order must make the run fail; the stage
# passes only when the mutated copy reports a nonzero status.
cp -r "$RUN/ts-gen" "$RUN/mutation-ts-gen"
sed -i 's/if (v.kind === "Crimson") return 0;/if (v.kind === "Crimson") return 7;/' "$RUN/mutation-ts-gen/comparisoncollision/TintedKey.ts"
bun "$RUN/mutation-ts-gen/run.ts" > "$RUN/mutation-execute.stdout" 2> "$RUN/mutation-execute.stderr"
mutation=$?
printf '%s\n' "$mutation" > "$RUN/mutation-execute.status"
if [ "$mutation" -eq 0 ]; then
    printf '%s\n' "mutated comparator still passed" > "$RUN/mutation.stderr"
    printf 'mutation=1\n'
    exit 1
fi
printf 'mutation=0\n'
sha256sum -c "$RUN/input-sha256.txt" > "$RUN/input-check.stdout" 2> "$RUN/input-check.stderr"
check=$?
printf '%s\n' "$check" > "$RUN/input-check.status"
exit "$check"
