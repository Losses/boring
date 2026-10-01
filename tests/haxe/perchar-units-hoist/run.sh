#!/usr/bin/env bash
# Collected guard for the per-character units hoisting of the Rust target.
#
# Why this fixture exists: `u_string::units` materializes the receiver's UTF-16
# vector, and on a `&str`-backed runtime `u_string::unit_at` rescans the source
# up to the read index. Both are O(n) in the string length, so a per-character
# walk that re-materializes them once per step is quadratic. Two shapes used to
# do exactly that and both are asserted here:
#
#   1. a per-character loop nested inside another per-character loop over the
#      same receiver re-materialized the vector on every entry into the inner
#      loop -- once per separator found, not once per loop
#      (TestTraceRender.stripWholeFraction, the measured report);
#   2. `for (i in 0...s.length)`, the idiom Haxe users reach for first, lowers
#      through the interval path, which had no per-character hoist at all, so
#      every step called `u_string::unit_at(&s, i)`.
#
# The assertions are per-function `u_string::units(` counts, which is what makes
# them discriminating rather than decorative. Measured on this fixture before
# the fix (RustExpr.hx @ 45743ba4): strip_whole_fraction 3, while_dot_count 2,
# while_local_dot_count 1, for_range_dot_count 1, for_range_local_dot_count 0,
# file total 7. After: 1, 1, 1, 1, 1, total 5. The two functions whose count did
# not move (while_local_dot_count, for_range_dot_count) are kept on purpose:
# they prove the scan really is counting the emitted hoists, so a "1" elsewhere
# is not a vacuous zero.
#
# A missing toolchain is environment-not-reached and is reported as such, never
# silently skipped (house convention, cf. tests/haxe/rust-resident-dataclass).
set -u

cd "$(dirname "$0")/../../.." || exit 2
ROOT="$(pwd)"
OUT="$ROOT/out/perchar-units-hoist/gen"
GEN="$OUT/pch/per_char_units_probe.rs"

mkdir -p "$ROOT/out"

if ! command -v haxe >/dev/null 2>&1; then
    echo "haxe not on PATH: generation stage environment-not-reached"
    exit 0
fi

# A worktree carries its own .haxelib projection; a fresh clone does not and
# relies on the ambient haxelib dev pointers. Prefer the local one when present.
if [ -d "$ROOT/.haxelib" ]; then
    export HAXELIB_PATH="$ROOT/.haxelib"
fi

rm -rf "$OUT"
haxe tests/haxe/perchar-units-hoist/gen/rust.hxml -cp packages/compiler -D rust-output="$OUT" \
    > "$ROOT/out/perchar-units-hoist-gen.log" 2>&1
gen_rc=$?
echo "generation rc=$gen_rc"
[ "$gen_rc" -eq 0 ] || { echo "GENERATION FAILED"; tail -20 "$ROOT/out/perchar-units-hoist-gen.log"; exit 1; }

[ -f "$GEN" ] || { echo "FAIL: generated module not found at $GEN"; exit 1; }

FAILED=0
fn_block() {
    awk -v fn="$1" '
        $0 ~ "fn " fn "\\(" { inside = 1 }
        inside { print }
        inside && /^    \}$/ { exit }
    ' "$GEN"
}

count_in() { printf '%s\n' "$1" | grep -c -- "$2"; }

check_fn() { # <function> <expected units count> <expected unit_count count>
    local name="$1" want_units="$2" want_count="$3" block got_units got_count
    block="$(fn_block "$name")"
    if [ -z "$block" ]; then
        echo "FAIL: $name was not generated -- the fixture root list may have changed"
        FAILED=1
        return
    fi
    got_units="$(count_in "$block" 'u_string::units(')"
    got_count="$(count_in "$block" 'u_string::unit_count(')"
    if [ "$got_units" != "$want_units" ] || [ "$got_count" != "$want_count" ]; then
        echo "FAIL: $name has $got_units u_string::units( and $got_count u_string::unit_count(, expected $want_units/$want_count"
        echo "----- $name -----"
        printf '%s\n' "$block"
        echo "------------------"
        FAILED=1
    else
        echo "ok: $name units=$got_units unit_count=$got_count"
    fi
}

# The measured Tiqian shape: one vector for the whole function, reused by the
# outer walk and by the nested walk inside the '.' branch.
check_fn per_char_units_probe_strip_whole_fraction 1 1
# A single while walk of a parameter: the function-level hoist is reused rather
# than duplicated at the loop.
check_fn per_char_units_probe_while_dot_count 1 1
# A while walk of a local String: no function-level hoist applies, so the loop
# must still materialize exactly one vector (vacuity control).
check_fn per_char_units_probe_while_local_dot_count 1 1
# The interval form of a parameter walk: the loop reuses the function-level
# hoist and its bound reads the hoisted count (vacuity control for the count).
check_fn per_char_units_probe_for_range_dot_count 1 1
# The interval form of a local String walk: the shape that had no hoist at all.
check_fn per_char_units_probe_for_range_local_dot_count 1 1

# The interval walk must read through the hoisted vector, not rescan the source.
RANGE_LOCAL="$(fn_block per_char_units_probe_for_range_local_dot_count)"
if printf '%s\n' "$RANGE_LOCAL" | grep -q 'u_string::unit_at(&'; then
    echo "FAIL: the interval walk still rescans the source with u_string::unit_at(&s, i)"
    FAILED=1
fi
if ! printf '%s\n' "$RANGE_LOCAL" | grep -q 'u_string::unit_at_from(&__units'; then
    echo "FAIL: the interval walk does not read from a hoisted unit vector"
    FAILED=1
fi
if ! printf '%s\n' "$RANGE_LOCAL" | grep -qE 'for i in [^.]*\.\.__count'; then
    echo "FAIL: the interval bound is not the hoisted unit count"
    FAILED=1
fi

TOTAL="$(count_in "$(cat "$GEN")" 'u_string::units(')"
if [ "$TOTAL" != "5" ]; then
    echo "FAIL: the module materializes $TOTAL unit vectors, expected 5 (one per root function)"
    FAILED=1
else
    echo "ok: module-wide u_string::units( count = $TOTAL"
fi

[ "$FAILED" -eq 0 ] || { echo "FAILED"; exit 1; }
echo "PASS"
