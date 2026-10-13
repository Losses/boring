#!/usr/bin/env bash
set -euo pipefail

# P5.3/P5.4 fixture: Null<ReadOnlyArray<Int>> crossing argument/field/return
# boundaries. Reproduces the round-2 defect and pins the dual-axis presence
# rendering. Two distinct force-unwrap mechanisms are observable in the text:
#   unproven -> (view!)  (Unwrap dispatch, parenthesized)
#   proven   -> view     (if-let shadow renders a non-optional binding, bare)
# P5.4 fixed Bug B (destinationOptionalOverride made conditional at call and
# constructor args), so argumentUnproven now force-unwraps as (view!) and the
# normal arm compiles clean.

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"

GEN="out/swift-optional-native-array/gen"
ABLATE_GEN="out/swift-optional-native-array/ablate-gen"
ARG_GEN="out/swift-optional-native-array/ablate-arg-gen"
rm -rf "$GEN" "$ABLATE_GEN" "$ARG_GEN"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0
check() {
  if grep -Fq -- "$2" "$OPS"; then echo "PASS: $1"; else echo "FAIL: $1 (missing: $2)"; fail=1; fi
}

echo "== generate =="
haxe tests/haxe/swift-optional-native-array/compile.hxml
OPS="$GEN/SwiftOptionalNativeArrayOps.swift"
[ -f "$OPS" ] || { echo "FAIL: missing $OPS"; exit 1; }

check "argumentProven renders bare (if-let shadow)"  "consumeRequired(view, 20)"
check "fieldUnproven unwraps (parens)"            "held = (view!)"
check "fieldProven renders bare (if-let shadow)"     "held = view"
check "returnUnproven unwraps (parens)"           "return (view!)"
check "returnProven renders bare (if-let shadow)"    "return view"
check "argumentUnproven unwraps (parens)"         "consumeRequired((view!), 10)"

echo "== swiftc (normal) =="
set +e
( cd "$TMP" && swiftc -c "$ROOT/$OPS" "$ROOT/$GEN/Runtime.swift" "$ROOT/$GEN"/std/*.swift ) 2>"$TMP/normal.err"
rc=$?
set -e
if [ "$rc" -eq 0 ]; then
  echo "PASS: swiftc compiles clean (3 proven boundaries bare via if-let; 3 unproven force-unwrapped; Bug B fixed)"
else
  echo "FAIL: swiftc rc=$rc"
  cat "$TMP/normal.err"; fail=1
fi

echo "== GP-ABLATE Presence =="
haxe tests/haxe/swift-optional-native-array/compile.hxml \
  -D swift_coerce_ablate=Presence -D swift-output="$ABLATE_GEN"
AOPS="$ABLATE_GEN/SwiftOptionalNativeArrayOps.swift"
set +e
swiftc -typecheck "$AOPS" "$ABLATE_GEN/Runtime.swift" "$ABLATE_GEN"/std/*.swift 2>"$TMP/ablate.err"
rc=$?
set -e
n_unwrap="$(grep -cE '^[^ ]+: error: .*must be unwrapped' "$TMP/ablate.err" || true)"
if [ "$rc" -ne 0 ] && [ "$n_unwrap" -eq 3 ]; then
  echo "PASS: ablated presence axis leaves only the 3 unproven optional boundaries bare (3 swiftc unwrap errors)"
else
  echo "FAIL: ablated swiftc rc=$rc unwrap_errors=$n_unwrap"
  cat "$TMP/ablate.err"; fail=1
fi

echo "== GP-ABLATE Argument =="
haxe tests/haxe/swift-optional-native-array/compile.hxml \
  -D swift_coerce_ablate=Argument -D swift-output="$ARG_GEN"
AOPS_ARG="$ARG_GEN/SwiftOptionalNativeArrayOps.swift"
set +e
swiftc -typecheck "$AOPS_ARG" "$ARG_GEN/Runtime.swift" "$ARG_GEN"/std/*.swift 2>"$TMP/ablate-arg.err"
rc=$?
set -e
n_unwrap="$(grep -cE '^[^ ]+: error: .*must be unwrapped' "$TMP/ablate-arg.err" || true)"
if [ "$rc" -ne 0 ] && [ "$n_unwrap" -eq 1 ]; then
  echo "PASS: ablated Argument role leaves only the 1 unproven argument boundary bare (1 swiftc unwrap error)"
else
  echo "FAIL: ablated-Argument swiftc rc=$rc unwrap_errors=$n_unwrap"
  cat "$TMP/ablate-arg.err"; fail=1
fi

[ "$fail" -eq 0 ] || { echo "== FAILED =="; exit 1; }
echo "== PASSED =="
