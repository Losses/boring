#!/usr/bin/env bash
# Minimal-consumer guard for the Rust resident emission bridge.
#
# Why this fixture exists at all, and why it is not a corpus test:
# the resident emission gate (Compiler.hx:862) is a GLOBAL UNION over one
# shared `shimsUsed` map -- it emits a resident if ANY of that module's
# business externs is lit anywhere in the program. On the full corpus some
# unrelated module always lights the std.SortedMap* keys, so sorted_table.rs
# is emitted no matter what the RustImports requireType bridge does. Ablating
# the bridge over the full corpus therefore produces a byte-identical tree
# and proves nothing; the same ablation over a single @:dataClass root
# produces a dangling `use` and a cargo E0432. (PIT-390, TCN-172)
#
# What is checked, in order:
#   1. generation succeeds;
#   2. the consumer .rs really does import the resident;
#   3. runtime/mod.rs declares that resident (the bridge's job);
#   4. the generated crate compiles, which is the end-to-end statement:
#      a dangling import is what a missing bridge actually costs.
#
# A missing toolchain is environment-not-reached and is reported as such,
# never silently skipped (house convention, cf. tests/haxe/dc-promoted-eval).
set -u

cd "$(dirname "$0")/../../.." || exit 2
ROOT="$(pwd)"
OUT="$ROOT/out/rust-resident-dataclass/gen"

# The haxe log is written under out/, so that directory must exist before the
# redirect. Without this, a fresh checkout with no out/ makes the redirect
# fail, haxe never runs, and the guard fails for the WRONG reason with an
# unreadable log (observed during verification).
mkdir -p "$ROOT/out"

if ! command -v haxe >/dev/null 2>&1; then
    echo "haxe not on PATH: generation stage environment-not-reached"
    exit 0
fi

rm -rf "$OUT"
haxe tests/haxe/rust-resident-dataclass/gen/rust.hxml > "$ROOT/out/rust-resident-dataclass-gen.log" 2>&1
gen_rc=$?
echo "generation rc=$gen_rc"
[ "$gen_rc" -eq 0 ] || { echo "GENERATION FAILED"; tail -20 "$ROOT/out/rust-resident-dataclass-gen.log"; exit 1; }

CONSUMER="$OUT/boring/data_class_string_compare.rs"
MOD="$OUT/runtime/mod.rs"

[ -f "$CONSUMER" ] || { echo "FAIL: consumer not generated at $CONSUMER"; exit 1; }
[ -f "$MOD" ] || { echo "FAIL: runtime/mod.rs not generated at $MOD"; exit 1; }

# 2. The consumer must actually reach into the resident; otherwise this
#    fixture would pass vacuously by testing nothing.
if ! grep -q 'runtime::sorted_table::SortedTable' "$CONSUMER"; then
    echo "FAIL: the consumer does not import runtime::sorted_table -- the fixture no longer exercises the bridge"
    exit 1
fi
echo "consumer imports the resident: yes"

# 3. The bridge's product: the declaration that backs that import.
if ! grep -q 'pub mod sorted_table;' "$MOD"; then
    echo "FAIL: runtime/mod.rs does not declare sorted_table, but the consumer imports it --"
    echo "      this is the dangling-mod-entry defect the RustImports bridge exists to prevent."
    echo "--- mod.rs ---"; cat "$MOD"
    exit 1
fi
echo "mod.rs declares sorted_table: yes"

# 4. End-to-end: an unbacked import is a compile error, so compile.
if ! command -v cargo >/dev/null 2>&1; then
    echo "cargo not on PATH: compile stage environment-not-reached"
    exit 0
fi

( cd "$OUT" && cargo check ) > "$ROOT/out/rust-resident-dataclass-cargo.log" 2>&1
cargo_rc=$?
echo "cargo check rc=$cargo_rc"
if [ "$cargo_rc" -ne 0 ]; then
    echo "FAIL: the generated crate does not compile"
    grep -E 'error\[E[0-9]+\]|^error' "$ROOT/out/rust-resident-dataclass-cargo.log" | head -10
    exit 1
fi

echo "PASS: the resident is emitted and backed on a single @:dataClass root"
