#!/usr/bin/env bash
set -u
root="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$root" || exit 2
mkdir -p "$root/out/kotlin-coerce-concat" || exit 2
run="$(mktemp -d "$root/out/kotlin-coerce-concat/run-XXXXXXXX")" || exit 2
failed=0

# Generate the fixture tree.
haxe tests/haxe/kotlin-coerce-concat/kotlin.hxml -D "kotlin-output=$run/gen"
rc=$?
if [ "$rc" -ne 0 ]; then
    echo "generate FAILED"
    exit 1
fi
echo "generate OK"

# Three operand shapes, each pinned to its exact operator. The needles name
# the whole expression, so a plain "+" is never counted from a "?.plus(":
#   leftSafeChain -> value?.label?.plus("x")  (left ?. chain -> ?.plus)
#   rightNullable -> "prefix" + s             (nullable right -> plain +)
#   bothNullable  -> value?.label?.plus(s)    (both nullable -> ?.plus)
kt="$run/gen/coerceconcat/ConcatCases.kt"
if [ ! -f "$kt" ]; then
    echo "ConcatCases.kt missing"
    exit 1
fi
for needle in 'value?.label?.plus("x")' '"prefix" + s' 'value?.label?.plus(s)'; do
    if grep -qF "$needle" "$kt"; then
        echo "form OK: $needle"
    else
        echo "form MISSING: $needle"
        failed=1
    fi
done

# Compile the generated tree (positive arm; the ?.plus forms type-check because
# their methods return Null<String>, i.e. String?).
ktfiles="$(find "$run/gen" -name '*.kt' -print | sort)"
if [ -z "$ktfiles" ]; then
    echo "no .kt files"
    exit 1
fi
kotlinc $ktfiles -d "$run/normal.jar"
rc=$?
if [ "$rc" -ne 0 ]; then
    echo "compile FAILED"
    failed=1
else
    echo "compile OK"
fi

echo "run dir: $run"
exit "$failed"
