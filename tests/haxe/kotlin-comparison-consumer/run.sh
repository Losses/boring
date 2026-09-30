#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
cd "$ROOT" || exit 2
if [ -z "${IN_NIX_SHELL:-}" ]; then
    exec nix develop -c bash "$HERE/run.sh"
fi
mkdir -p "$ROOT/out/kotlin-comparison-consumer" || exit 2
RUN="$(mktemp -d "$ROOT/out/kotlin-comparison-consumer/attempt-XXXXXXXX")" || exit 2
mkdir -p "$RUN/logs" "$RUN/gen"
printf '%s\n' "$RUN"
printf '%s\n' "$(git rev-parse HEAD)" > "$RUN/base-head.txt"
sha256sum \
    packages/compiler/SourceComparisonAnalysis.hx \
    packages/compiler/reflaxe/kotlin/kotlincompiler/KotlinDecl.hx \
    packages/compiler/reflaxe/kotlin/kotlincompiler/KotlinExpr.hx \
    packages/compiler/reflaxe/kotlin/kotlincompiler/KotlinComparisonPlan.hx \
    packages/compiler/reflaxe/kotlin/kotlincompiler/KotlinType.hx \
    packages/compiler/SemanticPassRegistry.hx \
    "$HERE/kotlin.hxml" "$HERE/pidentity.hxml" "$HERE/rejected.hxml" "$HERE/run.sh" \
    "$HERE"/expected.stdout "$HERE"/expected-identity.stdout \
    "$HERE"/cases/*.hx "$HERE"/cases/left/*.hx "$HERE"/cases/right/*.hx \
    "$HERE"/pid/*.hx "$HERE"/rejected/*.hx \
    tests/haxe/comparison-runtime-observation/comparison/ParameterCompositionCases.hx \
    "$HERE/native/Main.kt" "$HERE/pid/native/Main.kt" > "$RUN/input-sha256.txt"
run_stage() {
    local name="$1"
    shift
    printf '%s\0' "$@" > "$RUN/logs/$name.argv"
    printf '%s\n' "$ROOT" > "$RUN/logs/$name.cwd"
    "$@" > "$RUN/logs/$name.stdout" 2> "$RUN/logs/$name.stderr"
    local status=$?
    printf '%s\n' "$status" > "$RUN/logs/$name.status"
    printf '%s status=%s\n' "$name" "$status"
    return "$status"
}
run_stage identity-haxe haxe -version || exit 1
run_stage identity-kotlinc kotlinc -version || exit 1
run_stage generate haxe "$HERE/kotlin.hxml" -D "kotlin-output=$RUN/gen" || exit 1
mapfile -t kotlin_sources < <(rg --files "$RUN/gen" -g '*.kt' | rg -v '/runtime/test/' | sort)
sha256sum "${kotlin_sources[@]}" > "$RUN/generated-sha256.txt"
run_stage compile kotlinc -Xallow-kotlin-package "${kotlin_sources[@]}" \
    "$HERE/native/Main.kt" -include-runtime -d "$RUN/app.jar" || exit 1
run_stage jvm java -jar "$RUN/app.jar" || exit 1
cmp "$HERE/expected.stdout" "$RUN/logs/jvm.stdout" || exit 1

# Negative control: the kotlin target carries no retired comparator plan
# spelling. The registry no longer lists a ComparatorPlan consumer row; the
# dedicated comment control fixture proves a comment-only mention cannot
# satisfy a row.
if rg -q ComparatorPlan packages/compiler/reflaxe/kotlin; then
    printf 'negative control failed: old comparator plan spelling remains under the kotlin target\n' >&2
    exit 1
fi
printf '%s\n' 'no old comparator plan spelling under the kotlin target' > "$RUN/logs/negative-registry-spelling.stdout"

# Negative control: a rejected sorted key must fail generation at the key
# selection boundary with the comparison diagnostic.
run_stage generate-rejected haxe "$HERE/rejected.hxml" -D "kotlin-output=$RUN/rejected-gen" && {
    printf 'negative control failed: rejected key generation succeeded\n' >&2
    exit 1
}
if ! grep -q -e 'Kotlin comparison rejected' -e 'comparison analysis could not establish a finite plan' "$RUN/logs/generate-rejected.stderr" "$RUN/logs/generate-rejected.stdout"; then
    printf 'negative control failed: rejected key generation failed without the comparison diagnostic\n' >&2
    exit 1
fi
printf '%s\n' 'rejected key generation failed at the key selection boundary' > "$RUN/logs/negative-rejected-key.stdout"

# Parameter identity probe: two generic records in one module share the
# parameter identity, and the nested key must still order by the outer field
# first and the inner field second.
run_stage generate-identity haxe "$HERE/pidentity.hxml" -D "kotlin-output=$RUN/gen-identity" || exit 1
mapfile -t identity_sources < <(rg --files "$RUN/gen-identity" -g '*.kt' | rg -v '/runtime/test/' | sort)
run_stage compile-identity kotlinc -Xallow-kotlin-package "${identity_sources[@]}" \
    "$HERE/pid/native/Main.kt" -include-runtime -d "$RUN/identity.jar" || exit 1
run_stage jvm-identity java -jar "$RUN/identity.jar" || exit 1
cmp "$HERE/expected-identity.stdout" "$RUN/logs/jvm-identity.stdout" || exit 1

# Mutation negative control: a reversed scalar comparison must fail the JVM check.
cp -r "$RUN/gen" "$RUN/gen-mutated"
mutated="$RUN/gen-mutated/cases/left/SameKey.kt"
sed -i 's/a\.value\.compareTo(b\.value)/b.value.compareTo(a.value)/' "$mutated"
if ! grep -q 'b.value.compareTo(a.value)' "$mutated"; then
    printf 'negative control failed: mutation target not found\n' >&2
    exit 1
fi
mapfile -t mutated_sources < <(rg --files "$RUN/gen-mutated" -g '*.kt' | rg -v '/runtime/test/' | sort)
run_stage compile-mutated kotlinc -Xallow-kotlin-package "${mutated_sources[@]}" \
    "$HERE/native/Main.kt" -include-runtime -d "$RUN/mutated.jar" || {
    printf 'negative control failed: mutated sources no longer compile\n' >&2
    exit 1
}
if run_stage jvm-mutated java -jar "$RUN/mutated.jar"; then
    printf 'negative control failed: reversed comparison still passed the JVM check\n' >&2
    exit 1
fi

sha256sum "$RUN/app.jar" > "$RUN/artifact-sha256.txt"
printf 'passed %s\n' "$RUN"
