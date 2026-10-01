#!/usr/bin/env bash
# Generated-target warning gate.
# Choice B: the checked-in baselines are an allowance for warnings already
# present in the generated trees; a larger measured count fails the gate.
#
# Every column must be MEASURED for a PASS to mean anything. An absent compiler
# binary returns 127 (command not found), writes an empty log, makes grep count
# 0, and `0 <= baseline` then holds trivially - so the gate prints PASS while
# nothing was checked. That PASS is textually identical to a real measurement;
# on a bare PATH all five columns do it at once. A column that did not run
# therefore FAILS the gate by default. Set WARNING_GATE_ALLOW_UNMEASURED=1 to
# downgrade this to a printed note when a toolchain is deliberately absent; the
# PASS line then states that some columns were skipped.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# CI supplies these through nix develop; local verification may point at the
# pinned toolchain explicitly (the gate itself never downloads or generates).
DART_BIN=${DART_BIN:-dart}
KOTLINC_BIN=${KOTLINC_BIN:-kotlinc}
CARGO_BIN=${CARGO_BIN:-cargo}
SWIFT_BIN=${SWIFT_BIN:-swift}
TSC_BIN=${TSC_BIN:-tsc}
# A column that could not run is a gate failure by default; see the header.
ALLOW_UNMEASURED=${WARNING_GATE_ALLOW_UNMEASURED:-0}
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
FAIL=0
for required in "$ROOT/reference/dart/gen" "$ROOT/reference/kotlin/gen" "$ROOT/reference/rust/gen"; do
  if [ ! -d "$required" ]; then
    echo "warning-gate: missing generated tree: $required (run generation first)"
    FAIL=1
  fi
done
run() {
  local log=$1
  shift
  "$@" >"$log" 2>&1
  echo $? >"$log.rc"
}
rc() { cat "$1.rc"; }

# A column whose compiler binary is absent returns 127 (command not found) and
# writes an empty log, so grep counts 0 and `0 <= baseline` holds trivially.
# That PASS is textually identical to a real measurement, which is how this
# gate passed vacuously on a bare PATH while all five tools were missing.
# Treat 127 as "this column was NOT measured" and make that state fail, so
# "did not run" can never be read as "ran and found zero warnings".
UNMEASURED=0
require_measured() {
  local name=$1
  if [ "$(rc "$OUT/$name.loose")" = 127 ] || [ "$(rc "$OUT/$name.strict")" = 127 ]; then
    UNMEASURED=$((UNMEASURED + 1))
    if [ "$ALLOW_UNMEASURED" = 1 ]; then
      echo "warning-gate: $name compiler not found (rc=127); column SKIPPED (allowed by WARNING_GATE_ALLOW_UNMEASURED=1)"
    else
      echo "warning-gate: $name compiler not found (rc=127); column NOT measured"
      FAIL=1
    fi
  fi
}
check() {
  local name=$1 base=$2 n r
  require_measured "$name"
  case "$name" in
    dart) n=$(grep -cE '^warning' "$OUT/dart.loose" || true) ;;
    kotlin) n=$(grep -cE '\.kt:[0-9]+:[0-9]+: warning:' "$OUT/kotlin.loose" || true) ;;
    rust) n=$(grep -E '^[[:space:]]+--> ' "$OUT/rust.loose" | grep -cE 'runtime/|boring/|haxe/|registry/|std/' || true) ;;
    swift) n=$(grep -ciE '(^|: )warning([: ]|$)' "$OUT/swift.loose" || true) ;;
    typescript) n=$(grep -ciE '(^|: )warning([: ]|$)' "$OUT/typescript.loose" || true) ;;
    *) echo "warning-gate: unknown target $name"; FAIL=1; return ;;
  esac
  r=$(rc "$OUT/$name.strict")
  printf '%s: loose=%s strict=%s warnings=%s baseline=%s\n' "$name" "$(rc "$OUT/$name.loose")" "$r" "$n" "$base"
  # A non-zero count against a zero baseline is only meaningful if the compiler
  # actually ran; require_measured above has already rejected the 127 case.
  case "$n" in ''|*[!0-9]*) echo "warning-gate: $name count is not numeric"; FAIL=1;; esac
  if [ "$n" -gt "$base" ] 2>/dev/null; then
    echo "warning-gate: $name has $n warning(s), baseline is $base"
    FAIL=1
  fi
}

# Keep the loose invocation too: it gives a stable, countable diagnostic set;
# the strict invocation is the fail-capable compiler command for this target.
run "$OUT/dart.loose" "$DART_BIN" analyze --no-fatal-warnings "$ROOT/reference/dart/gen"
run "$OUT/dart.strict" "$DART_BIN" analyze --fatal-warnings "$ROOT/reference/dart/gen"
check dart 46

run "$OUT/kotlin.loose" "$KOTLINC_BIN" $(find "$ROOT/reference/kotlin/gen" -name '*.kt' -print) -d "$OUT/kotlin.jar"
run "$OUT/kotlin.strict" "$KOTLINC_BIN" -Werror $(find "$ROOT/reference/kotlin/gen" -name '*.kt' -print) -d "$OUT/kotlin-strict.jar"
check kotlin 59

run "$OUT/rust.loose" "$CARGO_BIN" check --manifest-path "$ROOT/reference/rust/gen/Cargo.toml"
run "$OUT/rust.strict" env RUSTFLAGS="${RUSTFLAGS:-} -D warnings" "$CARGO_BIN" check --manifest-path "$ROOT/reference/rust/gen/Cargo.toml"
check rust 4

# SwiftPM and tsc do not have warning-count baselines in the audit artifact;
# their strict invocations are nevertheless part of this gate. Their emitted
# warnings are counted and must remain at the recorded zero baseline.
run "$OUT/swift.loose" "$SWIFT_BIN" build --product BoringSwiftTests
run "$OUT/swift.strict" "$SWIFT_BIN" build --product BoringSwiftTests -Xswiftc -warnings-as-errors
check swift 0

run "$OUT/typescript.loose" "$TSC_BIN" -p "$ROOT"
run "$OUT/typescript.strict" "$TSC_BIN" -p "$ROOT" --noEmit
check typescript 0

if [ "$FAIL" -eq 0 ]; then
  if [ "$UNMEASURED" -gt 0 ]; then
    # Reached only with ALLOW_UNMEASURED=1; never claim full coverage here.
    echo "WARNING GATE PASS ($UNMEASURED column(s) SKIPPED - no warning count above baseline for the columns that ran)"
  else
    echo 'WARNING GATE PASS (no warning count above baseline; every column measured)'
  fi
else
  # Distinguish "a column regressed" from "a column never ran" - conflating the
  # two is what let a vacuous run read as a pass.
  if [ "$UNMEASURED" -gt 0 ]; then
    echo "WARNING GATE FAIL ($UNMEASURED column(s) NOT measured - a warning count of 0 here is unproven)"
  else
    echo 'WARNING GATE FAIL'
  fi
fi
exit "$FAIL"
