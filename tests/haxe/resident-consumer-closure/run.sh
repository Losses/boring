#!/usr/bin/env bash
# Five-target resident-closure GATE (t-mum0mp8l-m0a6) — assertion build.
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
# This is a gate, not an observation fixture. Every measured row is
# asserted (one line per row in logs/assertions.tsv) and a failed
# assertion makes the script exit 1; a clean run exits 0:
#   * generation must succeed on all ten inputs (rc=0);
#   * every generated tree must compile natively (rc=0) — the central
#     claim: a consumer entry that omits the runtime.* roots must still
#     pull in the resident modules, so every (a) row must pass, and the
#     (b) rows are the explicit-roots positive control;
#   * the stage-4 mutation rows must fail (rc!=0): the compile stage
#     must not pass vacuously.
# The rc tables are still printed as evidence, unchanged. The pre-fix
# verdict (closure broken on rust/swift/kotlin/dart, REPORT.md §2,
# measured on base 1ae6de72) is cited per row; the forced-typing gap it
# described was closed by 756c0c8a, so the (a) rows must pass from that
# commit on. Rows whose measurement drifts from the asserted expectation
# fail loudly until re-measured — that is the point.
set -u

root=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$root"
fixture=tests/haxe/resident-consumer-closure
O=out/resident-consumer-closure
L=$O/logs
rm -rf "$O"
mkdir -p "$L"

# ------------------------------------------------------------------
# Toolchains. Environment-overridable (tools/warning-gate/check.sh
# convention); defaults are the store paths measured in this
# environment. The swiftc default is the SDK-injecting shim, not the
# store binary: the store swiftc is bwrap-wrapped and dies here with
# `bwrap: setting up uid map: Permission denied` (PIT-250, bypass
# wrapper). There is no `swift` or `swift build` in this environment.
# ------------------------------------------------------------------
export PATH=/nix/store/98pb92k7pi6g5cifmg872jn18kghaxw5-haxe-4.3.7/bin:$PATH
export PATH=/nix/store/agfrkw7lvckq29w4dp0i3jfrhxjmgv3q-rust-default-1.98.0/bin:$PATH
export PATH=/home/losses/Development/tq-workspace/p09-chainA-work/swift-shim-bin:$PATH
export PATH=/nix/store/rqx09a40a82di944xi6ydjyzx632av28-kotlin-2.4.10/bin:$PATH
export PATH=/nix/store/qpggxvncr1jwa7xjn0wf0i6045na7hki-dart-3.13.0/bin:$PATH
export PATH=/nix/store/vd788darzi6n1k2zrj5x3kqgg03kbz93-nodejs-official-22.23.3/bin:$PATH
DART_BIN=${DART_BIN:-dart}
KOTLINC_BIN=${KOTLINC_BIN:-kotlinc}
CARGO_BIN=${CARGO_BIN:-cargo}
SWIFTC_BIN=${SWIFTC_BIN:-swiftc}
TSC_BIN=${TSC_BIN:-node_modules/.bin/tsc}

# Assertion bookkeeping. assert_rc <row> <rc> <expect: 0|nz> <note>:
# records ok/FAIL in logs/assertions.tsv and accumulates failures; the
# verdict block at the bottom is the gate.
TOTAL=0
FAILED=0
FAILURES=""
assert_rc() {
    TOTAL=$((TOTAL + 1))
    case "$3" in
        0) want='rc=0' ;;
        *) want='rc!=0' ;;
    esac
    if { [ "$3" = 0 ] && [ "$2" -eq 0 ]; } || { [ "$3" = nz ] && [ "$2" -ne 0 ]; }; then
        printf 'ok\t%s\t%s\t%s\n' "$1" "$2" "$4" >> "$L/assertions.tsv"
    else
        FAILED=$((FAILED + 1))
        FAILURES="$FAILURES"$'\n'"  $1: measured rc=$2, expected $want — $4"
        printf 'FAIL\t%s\t%s\t%s\n' "$1" "$2" "$4" >> "$L/assertions.tsv"
    fi
}

# ------------------------------------------------------------------
# Stage 1: Haxe generation, ten fixed inputs
# ------------------------------------------------------------------
: > "$L/gen-rc.tsv"
for target in ts rust swift kotlin dart; do
    for variant in a b; do
        haxe "$fixture/gen/$target-$variant.hxml" > "$L/gen-$target-$variant.log" 2>&1
        rc=$?
        printf '%s-%s\t%s\n' "$target" "$variant" "$rc" >> "$L/gen-rc.tsv"
        assert_rc "gen $target-$variant" "$rc" 0 "generation must succeed; baseline 0 on every input (REPORT.md §2)"
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
# Stage 3: native compile of every generated tree. Expectation per row:
# (a) rows: rc=0 — the central claim (no runtime.* root, residents still
# pulled in). (b) rows: rc=0 — explicit-roots positive control. Measured
# pre-fix baselines are cited; the known kotlin test-host FPHelper
# emission-gate defect (REPORT.md §4) makes the kotlin full-tree rows
# red until it is fixed — asserting rc=0 there is deliberate.
# ------------------------------------------------------------------
: > "$L/native-rc.tsv"

for variant in a b; do
    $TSC_BIN --noEmit -p "$fixture/tsconfig-$variant.json" > "$L/native-ts-$variant.log" 2>&1
    rc=$?
    printf 'ts-%s\t%s\n' "$variant" "$rc" >> "$L/native-rc.tsv"
    if [ "$variant" = a ]; then
        assert_rc "native ts-a" "$rc" 0 "closure under test; baseline 0 — ts force-types all residents (REPORT.md §4)"
    else
        assert_rc "native ts-b" "$rc" 0 "explicit-roots control; baseline 0"
    fi
done
for variant in a b; do
    (cd "$O/rust-$variant" && $CARGO_BIN check) > "$L/native-rust-$variant.log" 2>&1
    rc=$?
    printf 'rust-%s\t%s\n' "$variant" "$rc" >> "$L/native-rc.tsv"
    if [ "$variant" = a ]; then
        assert_rc "native rust-a" "$rc" 0 "closure under test; pre-fix baseline 101 (E0583, missing residents), closed by 756c0c8a"
    else
        assert_rc "native rust-b" "$rc" 0 "explicit-roots control; baseline 0"
    fi
done
for variant in a b; do
    $SWIFTC_BIN $(find "$O/swift-$variant" -name '*.swift') "$fixture/native-main.swift" \
        -o "$O/swift-$variant/native-main-bin" > "$L/native-swift-$variant.log" 2>&1
    rc=$?
    printf 'swift-%s\t%s\n' "$variant" "$rc" >> "$L/native-rc.tsv"
    if [ "$variant" = a ]; then
        assert_rc "native swift-a" "$rc" 0 "closure under test; pre-fix baseline 1 (14 errors, residents unemitted), closed by 756c0c8a"
    else
        assert_rc "native swift-b" "$rc" 0 "explicit-roots control; baseline 0"
    fi
done
for variant in a b; do
    $KOTLINC_BIN $(find "$O/kotlin-$variant" -name '*.kt') -d "$O/kotlin-$variant/consumer.jar" \
        > "$L/native-kotlin-$variant.log" 2>&1
    rc=$?
    printf 'kotlin-%s\t%s\n' "$variant" "$rc" >> "$L/native-rc.tsv"
    if [ "$variant" = a ]; then
        assert_rc "native kotlin-a" "$rc" 0 "closure under test; pre-fix baseline 1 (closure + 2 FPHelper errors), closure part closed by 756c0c8a"
    else
        assert_rc "native kotlin-b" "$rc" 0 "control; pre-fix baseline 1 — FPHelper test-host emission-gate defect (REPORT.md §4), red until fixed"
    fi
    # Isolation row: the same tree without the test host files, so the
    # four-face closure is measurable apart from the test-host defect.
    $KOTLINC_BIN $(find "$O/kotlin-$variant" -name '*.kt' -not -path '*/test/*') \
        -d "$O/kotlin-$variant/consumer-notest.jar" > "$L/native-kotlin-$variant-notest.log" 2>&1
    rc=$?
    printf 'kotlin-%s-notest\t%s\n' "$variant" "$rc" >> "$L/native-rc.tsv"
    assert_rc "native kotlin-$variant-notest" "$rc" 0 "closure minus test host; pre-fix baseline 1 (a) / 0 (b)"
done
for variant in a b; do
    $DART_BIN analyze --no-fatal-warnings "$O/dart-$variant" > "$L/native-dart-$variant.log" 2>&1
    rc=$?
    printf 'dart-%s\t%s\n' "$variant" "$rc" >> "$L/native-rc.tsv"
    if [ "$variant" = a ]; then
        assert_rc "native dart-a" "$rc" 0 "closure under test; pre-fix baseline 3 (7 errors), closed by 756c0c8a"
    else
        assert_rc "native dart-b" "$rc" 0 "explicit-roots control; baseline 0 (one tolerated warning)"
    fi
done
# Toolchain positive control independent of the generated trees.
printf 'fun main() { println("kotlin-toolchain-ok") }\n' > "$L/kotlinc-probe.kt"
$KOTLINC_BIN "$L/kotlinc-probe.kt" -include-runtime -d "$L/kotlinc-probe.jar" > "$L/kotlinc-probe.log" 2>&1
rc=$?
printf 'kotlinc-probe\t%s\n' "$rc" >> "$L/native-rc.tsv"
assert_rc "kotlinc-probe" "$rc" 0 "standalone toolchain positive control; baseline 0"
printf '== native compile rc ==\n'; cat "$L/native-rc.tsv"

# ------------------------------------------------------------------
# Stage 4: mutation negative control. One resident file deleted from a
# copy of the tree, then the same native command re-run. Every row must
# fail (rc!=0): the compile stage must not pass vacuously. A row that
# started passing here is a broken compile stage, not a win.
# ------------------------------------------------------------------
: > "$L/mut-rc.tsv"

rm -rf "$O/ts-a-mut"; cp -r "$O/ts-a" "$O/ts-a-mut"; rm "$O/ts-a-mut/runtime.ts"
printf '{\n    "compilerOptions": {\n        "target": "ESNext",\n        "module": "ESNext",\n        "moduleResolution": "bundler",\n        "allowImportingTsExtensions": true,\n        "strict": true,\n        "noEmit": true,\n        "skipLibCheck": true,\n        "lib": ["ESNext"]\n    },\n    "include": ["ts-a-mut/**/*.ts"]\n}\n' > "$O/tsconfig-a-mut.json"
$TSC_BIN --noEmit -p "$O/tsconfig-a-mut.json" > "$L/mut-ts-a.log" 2>&1
rc=$?
printf 'ts-a-mut(del runtime.ts)\t%s\n' "$rc" >> "$L/mut-rc.tsv"
assert_rc "mut ts-a (del runtime.ts)" "$rc" nz "must fail; baseline 2 (TS2307)"

for variant in a b; do
    file=u_string.rs; [ "$variant" = b ] && file=graphemes.rs
    rm -rf "$O/rust-$variant-mut"; cp -r "$O/rust-$variant" "$O/rust-$variant-mut"
    rm "$O/rust-$variant-mut/runtime/$file"
    (cd "$O/rust-$variant-mut" && $CARGO_BIN check) > "$L/mut-rust-$variant.log" 2>&1
    rc=$?
    printf 'rust-%s-mut(del %s)\t%s\n' "$variant" "$file" "$rc" >> "$L/mut-rc.tsv"
    assert_rc "mut rust-$variant (del $file)" "$rc" nz "must fail; baseline 101 (E0583)"
done

for variant in a b; do
    rm -rf "$O/swift-$variant-mut"; cp -r "$O/swift-$variant" "$O/swift-$variant-mut"
    rm "$O/swift-$variant-mut/Runtime.swift"
    $SWIFTC_BIN $(find "$O/swift-$variant-mut" -name '*.swift') "$fixture/native-main.swift" \
        -o "$O/swift-$variant-mut/native-main-bin" > "$L/mut-swift-$variant.log" 2>&1
    rc=$?
    printf 'swift-%s-mut(del Runtime.swift)\t%s\n' "$variant" "$rc" >> "$L/mut-rc.tsv"
    assert_rc "mut swift-$variant (del Runtime.swift)" "$rc" nz "must fail; baseline 1"
done

rm -rf "$O/kotlin-a-mut"; cp -r "$O/kotlin-a" "$O/kotlin-a-mut"; rm "$O/kotlin-a-mut/runtime/UString.kt"
$KOTLINC_BIN $(find "$O/kotlin-a-mut" -name '*.kt') -d "$O/kotlin-a-mut/consumer.jar" \
    > "$L/mut-kotlin-a.log" 2>&1
rc=$?
printf 'kotlin-a-mut(del UString.kt)\t%s\n' "$rc" >> "$L/mut-rc.tsv"
assert_rc "mut kotlin-a (del UString.kt)" "$rc" nz "must fail; baseline 1 (unresolved UString)"
rm -rf "$O/kotlin-b-notest-mut"; cp -r "$O/kotlin-b" "$O/kotlin-b-notest-mut"
rm "$O/kotlin-b-notest-mut/runtime/Graphemes.kt"
$KOTLINC_BIN $(find "$O/kotlin-b-notest-mut" -name '*.kt' -not -path '*/test/*') \
    -d "$O/kotlin-b-notest-mut/consumer.jar" > "$L/mut-kotlin-b-notest.log" 2>&1
rc=$?
printf 'kotlin-b-notest-mut(del Graphemes.kt)\t%s\n' "$rc" >> "$L/mut-rc.tsv"
assert_rc "mut kotlin-b-notest (del Graphemes.kt)" "$rc" nz "must fail; baseline 1 (unresolved Graphemes)"

for variant in a b; do
    rm -rf "$O/dart-$variant-mut"; cp -r "$O/dart-$variant" "$O/dart-$variant-mut"
    rm "$O/dart-$variant-mut/runtime.dart"
    $DART_BIN analyze --no-fatal-warnings "$O/dart-$variant-mut" > "$L/mut-dart-$variant.log" 2>&1
    rc=$?
    printf 'dart-%s-mut(del runtime.dart)\t%s\n' "$variant" "$rc" >> "$L/mut-rc.tsv"
    assert_rc "mut dart-$variant (del runtime.dart)" "$rc" nz "must fail; baseline 3 (uri_does_not_exist)"
done
printf '== mutation rc (all rows must fail) ==\n'; cat "$L/mut-rc.tsv"

# Input hashes of the fixed consumer inputs, for the record.
sha256sum "$fixture/Consumer.hx" "$fixture"/gen/*.hxml > "$L/input-hashes.txt"
rc=$?
printf '== input hashes written to %s ==\n' "$L/input-hashes.txt"
assert_rc "input hashes" "$rc" 0 "fixture inputs must be intact; combined sha256 acc7eeea… (REPORT.md §1)"

# ------------------------------------------------------------------
# Verdict. The tables above are evidence; this block is the gate.
# ------------------------------------------------------------------
printf '== assertions (%s total, %s failed) ==\n' "$TOTAL" "$FAILED"
cat "$L/assertions.tsv"
if [ "$FAILED" -gt 0 ]; then
    printf '== verdict: FAILED — %s of %s assertions ==\n' "$FAILED" "$TOTAL"
    printf '%s\n' "$FAILURES"
    exit 1
fi
printf '== verdict: PASS — all %s assertions held ==\n' "$TOTAL"
exit 0
