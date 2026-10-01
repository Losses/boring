#!/usr/bin/env bash
# Runtime cost of the per-character units hoisting, measured rather than read.
#
# Not part of the collected suite (it needs cargo and a release build). Run it
# on a branch to get that branch's numbers; run it on the base to get the
# before. The companion guard tests/haxe/perchar-units-hoist/run.sh asserts the
# emitted SHAPE cheaply; this script is what turns that shape into a curve.
#
#   bash tests/haxe/perchar-units-hoist/measure-units-cost.sh [native|tiqian-unit-at]
#
# What is measured
#   strip_whole_fraction   -- the measured Tiqian shape
#                             (TestTraceRender.stripWholeFraction): a nested
#                             per-character `while` over the same receiver.
#                             Instruments u_string::units with a call counter,
#                             because each call materializes the whole UTF-16
#                             vector.
#   for_range_local_dot_count
#                          -- `for (i in 0...s.length)` over a local String,
#                             the shape the interval path lowers. Instruments
#                             u_string::unit_at with a scanned-unit counter.
#
# The `tiqian-unit-at` variant additionally replaces u_string::unit_at with the
# Tiqian implementation (a linear walk over the UTF-16 units; see
# /tmp/.../engine-haxe/out/rust-gen-f64/.../runtime/u_string.rs, `unit_at`)
# ported to this crate's [u16] storage -- the same loop with the same O(index)
# asymptotics. The boring runtime's own unit_at is an O(1) slice index, so the
# interval shape's quadratic cost is only visible under that variant; the
# nested re-materialization is O(n) under either.
#
# Reading (2026-10-01, RustExpr.hx @ 45743ba4 and its fix):
#   strip_whole_fraction, native, bytes 100k/200k/400k
#     before  units_calls 13798/27590/55178   ms 53/225/968    (4x per doubling)
#     after   units_calls 1/1/1               ms  4/ 10/ 19    (linear)
#   for_range_local_dot_count, tiqian-unit-at
#     before  units_scanned 5.0e9/2.0e10/8.0e10  ms 10027/42134/177795
#     after   units_scanned 0                    ms 0/0/0
set -u

cd "$(dirname "$0")/../../.." || exit 2
ROOT="$(pwd)"
VARIANT="${1:-native}"
OUT="$ROOT/out/perchar-units-hoist/measure-$VARIANT"
WORK="$OUT/crate"

command -v haxe >/dev/null 2>&1 || { echo "haxe not on PATH: environment-not-reached"; exit 0; }
command -v cargo >/dev/null 2>&1 || { echo "cargo not on PATH: environment-not-reached"; exit 0; }

if [ -d "$ROOT/.haxelib" ]; then
    export HAXELIB_PATH="$ROOT/.haxelib"
fi

rm -rf "$WORK"
mkdir -p "$OUT"
haxe tests/haxe/perchar-units-hoist/gen/rust.hxml -cp packages/compiler -D rust-output="$WORK" \
    > "$OUT/gen.log" 2>&1 || { echo "GENERATION FAILED"; tail -20 "$OUT/gen.log"; exit 1; }

python3 - "$WORK/runtime/u_string.rs" "$VARIANT" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); variant = sys.argv[2]
src = p.read_text()
src = ("use std::sync::atomic::{AtomicU64, Ordering as AtomicOrdering};\n"
       "pub static UNITS_CALLS: AtomicU64 = AtomicU64::new(0);\n"
       "pub static UNIT_AT_SCANNED: AtomicU64 = AtomicU64::new(0);\n"
       "pub fn units_calls() -> u64 { UNITS_CALLS.load(AtomicOrdering::Relaxed) }\n"
       "pub fn unit_at_scanned() -> u64 { UNIT_AT_SCANNED.load(AtomicOrdering::Relaxed) }\n\n") + src
old = "pub fn units(s: &UStr) -> Vec<u16> {\n    s.as_slice().to_vec()\n}"
new = ("pub fn units(s: &UStr) -> Vec<u16> {\n"
       "    UNITS_CALLS.fetch_add(1, AtomicOrdering::Relaxed);\n"
       "    s.as_slice().to_vec()\n}")
assert old in src, "units() body changed"
src = src.replace(old, new, 1)
if variant == "tiqian-unit-at":
    old_at = ("pub fn unit_at(s: &UStr, index: u32) -> Option<u32> {\n"
              "    match s.as_slice().get(usize::try_from(index).unwrap_or(0)) {\n"
              "        Some(u) => Some(u32::from(*u)),\n"
              "        None => None,\n"
              "    }\n}")
    new_at = ("pub fn unit_at(s: &UStr, index: u32) -> Option<u32> {\n"
              "    let mut remaining = index;\n"
              "    for unit in s.as_slice() {\n"
              "        UNIT_AT_SCANNED.fetch_add(1, AtomicOrdering::Relaxed);\n"
              "        if remaining == 0 { return Some(u32::from(*unit)); }\n"
              "        remaining -= 1;\n"
              "    }\n"
              "    None\n"
              "}")
    assert old_at in src, "unit_at() body changed"
    src = src.replace(old_at, new_at, 1)
p.write_text(src)
PY

cat >> "$WORK/Cargo.toml" <<'TOML'

[[test]]
name = "perchar_cost"
path = "tests/perchar_cost.rs"
TOML
mkdir -p "$WORK/tests"
cp "$ROOT/tests/haxe/perchar-units-hoist/perchar-cost.rs" "$WORK/tests/perchar_cost.rs"

cd "$WORK"
CARGO_TARGET_DIR="$OUT/target" cargo test --release --test perchar_cost -- --nocapture 2>&1 \
    | grep -E 'MEASURE|test result|^error' | sed "s/^/[$VARIANT] /"
