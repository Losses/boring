#!/usr/bin/env bash
# Reproduction driver for the coalescing String.length unit fixture.
# Run from the repository root: tests/swift-length-utf16/run.sh /tmp/len-utf16
# Toolchain (not on PATH):
#   haxe  = /nix/store/98pb92k7pi6g5cifmg872jn18kghaxw5-haxe-4.3.7/bin
#   swiftc = /home/losses/Development/tq-workspace/p09-chainA-work/swift-shim-bin/swiftc
set -euo pipefail
OUT=${1:-/tmp/len-utf16}
export PATH=/nix/store/98pb92k7pi6g5cifmg872jn18kghaxw5-haxe-4.3.7/bin:$PATH
SWIFTC=/home/losses/Development/tq-workspace/p09-chainA-work/swift-shim-bin/swiftc

echo "== Haxe oracle =="
haxe tests/swift-length-utf16/oracle.hxml

echo "== Swift codegen =="
rm -rf "$OUT" && mkdir -p "$OUT"
haxe tests/swift-length-utf16/swift.hxml -D swift-output="$OUT/gen"

echo "== Swift run =="
mkdir -p "$OUT/bin"
"$SWIFTC" "$OUT/gen/lenfix/CharCount.swift" tests/swift-length-utf16/LengthRuntimeTests.swift -o "$OUT/bin/lenfix"
"$OUT/bin/lenfix"
# Expected: coalesced=4 (UTF-16 code units of "a😀b"), present=9.
