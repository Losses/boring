#!/usr/bin/env bash
# Five-target resident-closure measurement (t-mum0mp8l-m0a6).
#
# Consumer entry: tests/haxe/resident-consumer-closure/Consumer.hx calls
# StringTools, std.UStringRT, std.Graphemes, std.SortedMap/SortedSet
# through the std extern face only. Variant a roots only Consumer (no
# runtime.* root); variant b adds the runtime.* roots the examples
# hxml lists. Stages per target and variant, each with a direct-read
# rc and a raw log under out/resident-consumer-closure/logs/:
#
#   1. Haxe generation          gen/<target>-<variant>.hxml
#   2. Resident file manifest   find over the generated tree
#   3. Native compile           tsc / cargo / swiftc / kotlinc / dart
#   4. Mutation negative        delete one resident file, recompile
#
# Exit codes are recorded per command with `cmd > log 2>&1; rc=$?`; no
# command pipes its exit status away. The script never fails early: it
# prints one rc table per stage and returns 0 so the caller reads the
# tables. Toolchain paths are the nix store ones measured in this
# environment; override PATH externally to reuse another toolchain set.
set -u

root=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$root"
fixture=tests/haxe/resident-consumer-closure
O=out/resident-consumer-closure
L=$O/logs
rm -rf "$O"
mkdir -p "$L"

export PATH=/nix/store/98pb92k7pi6g5cifmg872jn18kghaxw5-haxe-4.3.7/bin:$PATH

# ------------------------------------------------------------------
# Stage 1: Haxe generation, ten fixed inputs
# ------------------------------------------------------------------
: > "$L/gen-rc.tsv"
for target in ts rust swift kotlin dart; do
    for variant in a b; do
        haxe "$fixture/gen/$target-$variant.hxml" > "$L/gen-$target-$variant.log" 2>&1
        rc=$?
        printf '%s-%s\t%s\n' "$target" "$variant" "$rc" >> "$L/gen-rc.tsv"
    done
done
printf '== generation rc ==\n'; cat "$L/gen-rc.tsv"

# ------------------------------------------------------------------
# Stage 2: resident runtime file manifest of every generated tree
# ------------------------------------------------------------------
: > "$L/manifests.txt"
for target in ts rust swift kotlin dart; do
    for variant in a b; do
        printf '=== %s-%s\n' "$target" "$variant" >> "$L/manifests.txt"
        (cd "$O/$target-$variant" && find . -type f | sort | sed 's|^\./||') >> "$L/manifests.txt" 2>/dev/null
    done
done
printf '== manifests written to %s ==\n' "$L/manifests.txt"

# ------------------------------------------------------------------
# Stage 3: native compile of every generated tree
# ------------------------------------------------------------------
export PATH=/nix/store/agfrkw7lvckq29w4dp0i3jfrhxjmgv3q-rust-default-1.98.0/bin:$PATH
export PATH=/nix/store/6xl7bxha1n1asrxzxb8dnsh9hvnpa00j-swiftc/bin:$PATH
export PATH=/nix/store/rqx09a40a82di944xi6ydjyzx632av28-kotlin-2.4.10/bin:$PATH
export PATH=/nix/store/qkw9j7gkkz1y7k11y86hqzygb6cr23cr-dart-3.12.2/bin:$PATH
: > "$L/native-rc.tsv"

for variant in a b; do
    node_modules/.bin/tsc --noEmit -p "$fixture/tsconfig-$variant.json" > "$L/native-ts-$variant.log" 2>&1
    printf 'ts-%s\t%s\n' "$variant" "$?" >> "$L/native-rc.tsv"
done
for variant in a b; do
    (cd "$O/rust-$variant" && cargo check) > "$L/native-rust-$variant.log" 2>&1
    printf 'rust-%s\t%s\n' "$variant" "$?" >> "$L/native-rc.tsv"
done
for variant in a b; do
    swiftc $(find "$O/swift-$variant" -name '*.swift') "$fixture/native-main.swift" \
        -o "$O/swift-$variant/native-main-bin" > "$L/native-swift-$variant.log" 2>&1
    printf 'swift-%s\t%s\n' "$variant" "$?" >> "$L/native-rc.tsv"
done
for variant in a b; do
    kotlinc $(find "$O/kotlin-$variant" -name '*.kt') -d "$O/kotlin-$variant/consumer.jar" \
        > "$L/native-kotlin-$variant.log" 2>&1
    printf 'kotlin-%s\t%s\n' "$variant" "$?" >> "$L/native-rc.tsv"
    # Isolation row: the same tree without the test host files, so the
    # four-face closure is measurable apart from the test-host defect.
    kotlinc $(find "$O/kotlin-$variant" -name '*.kt' -not -path '*/test/*') \
        -d "$O/kotlin-$variant/consumer-notest.jar" > "$L/native-kotlin-$variant-notest.log" 2>&1
    printf 'kotlin-%s-notest\t%s\n' "$variant" "$?" >> "$L/native-rc.tsv"
done
for variant in a b; do
    dart analyze --no-fatal-warnings "$O/dart-$variant" > "$L/native-dart-$variant.log" 2>&1
    printf 'dart-%s\t%s\n' "$variant" "$?" >> "$L/native-rc.tsv"
done
# Toolchain positive control independent of the generated trees.
printf 'fun main() { println("kotlin-toolchain-ok") }\n' > "$L/kotlinc-probe.kt"
kotlinc "$L/kotlinc-probe.kt" -include-runtime -d "$L/kotlinc-probe.jar" > "$L/kotlinc-probe.log" 2>&1
printf 'kotlinc-probe\t%s\n' "$?" >> "$L/native-rc.tsv"
printf '== native compile rc ==\n'; cat "$L/native-rc.tsv"

# ------------------------------------------------------------------
# Stage 4: mutation negative control. One resident file deleted from a
# copy of the tree, then the same native command re-run. Every row must
# fail: the compile stage must not pass vacuously.
# ------------------------------------------------------------------
: > "$L/mut-rc.tsv"

rm -rf "$O/ts-a-mut"; cp -r "$O/ts-a" "$O/ts-a-mut"; rm "$O/ts-a-mut/runtime.ts"
printf '{\n    "compilerOptions": {\n        "target": "ESNext",\n        "module": "ESNext",\n        "moduleResolution": "bundler",\n        "allowImportingTsExtensions": true,\n        "strict": true,\n        "noEmit": true,\n        "skipLibCheck": true,\n        "lib": ["ESNext"]\n    },\n    "include": ["ts-a-mut/**/*.ts"]\n}\n' > "$O/tsconfig-a-mut.json"
node_modules/.bin/tsc --noEmit -p "$O/tsconfig-a-mut.json" > "$L/mut-ts-a.log" 2>&1
printf 'ts-a-mut(del runtime.ts)\t%s\n' "$?" >> "$L/mut-rc.tsv"

for variant in a b; do
    file=u_string.rs; [ "$variant" = b ] && file=graphemes.rs
    rm -rf "$O/rust-$variant-mut"; cp -r "$O/rust-$variant" "$O/rust-$variant-mut"
    rm "$O/rust-$variant-mut/runtime/$file"
    (cd "$O/rust-$variant-mut" && cargo check) > "$L/mut-rust-$variant.log" 2>&1
    printf 'rust-%s-mut(del %s)\t%s\n' "$variant" "$file" "$?" >> "$L/mut-rc.tsv"
done

for variant in a b; do
    rm -rf "$O/swift-$variant-mut"; cp -r "$O/swift-$variant" "$O/swift-$variant-mut"
    rm "$O/swift-$variant-mut/Runtime.swift"
    swiftc $(find "$O/swift-$variant-mut" -name '*.swift') "$fixture/native-main.swift" \
        -o "$O/swift-$variant-mut/native-main-bin" > "$L/mut-swift-$variant.log" 2>&1
    printf 'swift-%s-mut(del Runtime.swift)\t%s\n' "$variant" "$?" >> "$L/mut-rc.tsv"
done

rm -rf "$O/kotlin-a-mut"; cp -r "$O/kotlin-a" "$O/kotlin-a-mut"; rm "$O/kotlin-a-mut/runtime/UString.kt"
kotlinc $(find "$O/kotlin-a-mut" -name '*.kt') -d "$O/kotlin-a-mut/consumer.jar" \
    > "$L/mut-kotlin-a.log" 2>&1
printf 'kotlin-a-mut(del UString.kt)\t%s\n' "$?" >> "$L/mut-rc.tsv"
rm -rf "$O/kotlin-b-notest-mut"; cp -r "$O/kotlin-b" "$O/kotlin-b-notest-mut"
rm "$O/kotlin-b-notest-mut/runtime/Graphemes.kt"
kotlinc $(find "$O/kotlin-b-notest-mut" -name '*.kt' -not -path '*/test/*') \
    -d "$O/kotlin-b-notest-mut/consumer.jar" > "$L/mut-kotlin-b-notest.log" 2>&1
printf 'kotlin-b-notest-mut(del Graphemes.kt)\t%s\n' "$?" >> "$L/mut-rc.tsv"

for variant in a b; do
    rm -rf "$O/dart-$variant-mut"; cp -r "$O/dart-$variant" "$O/dart-$variant-mut"
    rm "$O/dart-$variant-mut/runtime.dart"
    dart analyze --no-fatal-warnings "$O/dart-$variant-mut" > "$L/mut-dart-$variant.log" 2>&1
    printf 'dart-%s-mut(del runtime.dart)\t%s\n' "$variant" "$?" >> "$L/mut-rc.tsv"
done
printf '== mutation rc (all rows must fail) ==\n'; cat "$L/mut-rc.tsv"

# Input hashes of the fixed consumer inputs, for the record.
sha256sum "$fixture/Consumer.hx" "$fixture"/gen/*.hxml > "$L/input-hashes.txt"
printf '== input hashes written to %s ==\n' "$L/input-hashes.txt"
