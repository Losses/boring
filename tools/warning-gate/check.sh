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
#
# The two rcs of each column were measured, printed, and then ignored: the only
# verdict was `n <= baseline`. So a compiler that FAILED while emitting no
# countable `warning:` line measured n=0, `0 <= baseline` held, and a tree that
# does not compile read as PASS. The failure capability already existed and its
# cost was already paid; it was simply never wired, which is what check() does
# now. See the rc-wiring block inside check() for why the loose rc is the bare
# "did it compile" verdict and the strict rc is not.
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
FAIL_COUNT=0
FAIL_RC=0
HISTOGRAM_ONLY=${HISTOGRAM_ONLY:-0}
MEASURED_dart=
MEASURED_kotlin=
MEASURED_rust=
MEASURED_swift=
MEASURED_typescript=
for required in "$ROOT/reference/dart/gen" "$ROOT/reference/kotlin/gen" "$ROOT/reference/rust/gen"; do
  if [ ! -d "$required" ]; then
    echo "warning-gate: missing generated tree: $required (run generation first)"
    FAIL=1
    FAIL_COUNT=1
    FAIL_RC=1
  fi
done
# --- frozen warning baselines -----------------------------------------------
# tools/warning-gate/baseline.txt is the single source of truth for each
# target's warning allowance and its residual label. A residual (rust
# std-shadow glob, dart noise) is REGISTERED here - visible and named in the
# histogram - never hidden from the count. Reading the allowance from this file
# makes a baseline change an explicit, reviewable edit instead of a quiet
# threshold bump inside check.sh.
baseline_file() { echo "$ROOT/tools/warning-gate/baseline.txt"; }
baseline() { awk -v t="$1" -F'\t' '$1==t { print $2; exit }' "$(baseline_file)" 2>/dev/null; }
residual() { awk -v t="$1" -F'\t' '$1==t { print $3; exit }' "$(baseline_file)" 2>/dev/null; }

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
      FAIL_RC=1
    fi
  fi
}
check() {
  local name=$1 base=$2 n r
  require_measured "$name"
  case "$base" in
    ''|*[!0-9]*)
      echo "warning-gate: $name baseline is missing or not numeric (got '$base'); the count cannot be judged"
      FAIL=1
      FAIL_COUNT=1
      ;;
  esac
  case "$name" in
    dart) n=$(grep -cE '^warning' "$OUT/dart.loose" || true) ;;
    kotlin) n=$(grep -cE '\.kt:[0-9]+:[0-9]+: warning:' "$OUT/kotlin.loose" || true) ;;
    rust) n=$(grep -E '^[[:space:]]+--> ' "$OUT/rust.loose" | grep -cE 'runtime/|boring/|haxe/|registry/|std/' || true) ;;
    swift) n=$(grep -ciE '(^|: )warning([: ]|$)' "$OUT/swift.loose" || true) ;;
    typescript) n=$(grep -ciE '(^|: )warning([: ]|$)' "$OUT/typescript.loose" || true) ;;
    *) echo "warning-gate: unknown target $name"; FAIL=1; return ;;
  esac
  l=$(rc "$OUT/$name.loose")
  r=$(rc "$OUT/$name.strict")
  printf '%s: loose=%s strict=%s warnings=%s baseline=%s\n' "$name" "$l" "$r" "$n" "$base"
  case "$n" in ''|*[!0-9]*) echo "warning-gate: $name count is not numeric"; FAIL=1; FAIL_COUNT=1;; esac
  # Remember the measured count for the histogram (tier 1 evidence). The
  # dynamic name via eval is bash-3.2-portable (no assoc arrays); it is only
  # ASSIGNED here, never read, so set -u cannot trip on it in the self-test.
  eval "MEASURED_$name=\$n"
  # --- rc wiring -----------------------------------------------------------
  # Both rcs were measured and printed above and then ignored, so the only
  # verdict was `n <= baseline`. A compiler that failed while emitting no
  # countable `warning:` line measured n=0, `0 <= baseline` held, and a tree that
  # does not compile read as PASS.
  #
  # The two rcs do NOT carry the same meaning, which is why only one of them can
  # be read as a bare compile verdict. Measured on the clean generated trees:
  #   kotlin loose rc=0 strict rc=1   (83 countable warnings, 0 error lines)
  #   rust   loose rc=0 strict rc=101 (4 countable warnings, "due to 4 previous
  #                                    errors" - those "errors" ARE the 4 allowed
  #                                    warnings, promoted by -D warnings)
  #   dart   loose rc=0 strict rc=2   (46 warnings; base 5c85feb5; ledger retired to wb 2026-09-30)
  # The strict flag promotes exactly the warnings the baselines already allow, so
  # a non-zero strict rc is the NORMAL state of a clean tree - and on kotlin and
  # rust it keeps the same value on a tree that does not compile at all (injected
  # syntax error: kotlin 1, rust 101). Failing on any non-zero strict rc would
  # therefore redden every column by construction, which is a zero-warning gate,
  # not this no-regression gate.
  #
  # The LOOSE rc is the same compiler without the promotion flag: 0 on a tree
  # that compiles with the recorded stock, non-zero on one that does not
  # (measured: kotlin 0->1, rust 0->101 under injection). That is the
  # un-confounded "did it compile" verdict, and anything but 0 or 127 fails the
  # column here, so the failure reads as "rc triggered", not "one warning over
  # baseline". 127 is "binary absent" and belongs to require_measured.
  case "$l" in
    ''|*[!0-9]*)
      echo "warning-gate: $name loose rc is not numeric (got '$l'); column NOT measured"
      FAIL=1
      FAIL_RC=1
      ;;
    *)
      if [ "$l" -ne 0 ] && [ "$l" -ne 127 ]; then
        echo "warning-gate: $name loose compile FAILED (rc=$l, not a warning-count regression); log: $OUT/$name.loose"
        FAIL=1
        FAIL_RC=1
      fi
      ;;
  esac
  # The strict rc participates in the one state where the allowance cannot
  # explain it: non-zero while no warning was counted. A non-numeric rc file
  # means the strict column never ran, which is also a failure.
  case "$r" in
    ''|*[!0-9]*)
      echo "warning-gate: $name strict rc is not numeric (got '$r'); column NOT measured"
      FAIL=1
      FAIL_RC=1
      ;;
    *)
      if [ "$r" -ne 0 ] && [ "$r" -ne 127 ] && [ "$n" = 0 ]; then
        echo "warning-gate: $name strict compile FAILED (rc=$r with warnings=0, so no counted warning explains it); log: $OUT/$name.strict"
        FAIL=1
        FAIL_RC=1
      fi
      ;;
  esac
  # A non-zero count above the allowance is a regression (tier 1: gen
  # warnings). require_measured above has already rejected the 127 case, and
  # the base validation above has rejected a missing/non-numeric allowance.
  case "$base" in
    ''|*[!0-9]*) : ;; # already flagged above; the comparison would be garbage
    *)
      if [ "$n" -gt "$base" ] 2>/dev/null; then
        echo "warning-gate: $name has $n warning(s), baseline is $base"
        FAIL=1
        FAIL_COUNT=1
      fi
      ;;
  esac
}

# Keep the loose invocation too: it gives a stable, countable diagnostic set;
# the strict invocation is the fail-capable compiler command for this target.
run "$OUT/dart.loose" "$DART_BIN" analyze --no-fatal-warnings "$ROOT/reference/dart/gen"
run "$OUT/dart.strict" "$DART_BIN" analyze --fatal-warnings "$ROOT/reference/dart/gen"
check dart "$(baseline dart)"

run "$OUT/kotlin.loose" "$KOTLINC_BIN" $(find "$ROOT/reference/kotlin/gen" -name '*.kt' -print) -d "$OUT/kotlin.jar"
run "$OUT/kotlin.strict" "$KOTLINC_BIN" -Werror $(find "$ROOT/reference/kotlin/gen" -name '*.kt' -print) -d "$OUT/kotlin-strict.jar"
check kotlin "$(baseline kotlin)"

run "$OUT/rust.loose" "$CARGO_BIN" check --manifest-path "$ROOT/reference/rust/gen/Cargo.toml"
run "$OUT/rust.strict" env RUSTFLAGS="${RUSTFLAGS:-} -D warnings" "$CARGO_BIN" check --manifest-path "$ROOT/reference/rust/gen/Cargo.toml"
check rust "$(baseline rust)"

# SwiftPM and tsc do not have warning-count baselines in the audit artifact;
# their strict invocations are nevertheless part of this gate. Their emitted
# warnings are counted and must remain at the recorded zero baseline.
run "$OUT/swift.loose" "$SWIFT_BIN" build --product BoringSwiftTests
run "$OUT/swift.strict" "$SWIFT_BIN" build --product BoringSwiftTests -Xswiftc -warnings-as-errors
check swift "$(baseline swift)"

run "$OUT/typescript.loose" "$TSC_BIN" -p "$ROOT"
run "$OUT/typescript.strict" "$TSC_BIN" -p "$ROOT" --noEmit
check typescript "$(baseline typescript)"

# --- the warning histogram (tier 1 evidence) --------------------------------
# One row per target: measured count, frozen baseline, adjudication status, and
# the registered residual label. Residuals (rust std-shadow glob, dart noise)
# are REGISTERED here - visible and named - never hidden from the count, and the
# gate below enforces exactly these numbers, so this table and the gate cannot
# diverge.
printf '%-11s %-9s %-9s %-12s %s\n' target measured baseline status residual
for target in dart kotlin rust swift typescript; do
  eval "measured=\$MEASURED_$target"
  base=$(baseline "$target")
  res=$(residual "$target")
  [ -n "$res" ] || res=-
  [ -n "$measured" ] || measured=-
  [ -n "$base" ] || base=-
  status=ok
  case "$measured" in ''|*[!0-9]*) status=UNMEASURED ;; esac
  if [ "$status" = ok ] && [ "$measured" -gt "$base" ] 2>/dev/null; then
    status=REGRESSION
  fi
  printf '%-11s %-9s %-9s %-12s %s\n' "$target" "$measured" "$base" "$status" "$res"
done

# --- four-tier verdicts: tiers 1 and 2 live here (3 and 4 are gate.sh) -------
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "warning-gate: tier1 gen-warnings = PASS"
else
  echo "warning-gate: tier1 gen-warnings = FAIL"
fi
if [ "$FAIL_RC" -eq 0 ]; then
  echo "warning-gate: tier2 compile-warnings = PASS"
else
  echo "warning-gate: tier2 compile-warnings = FAIL"
fi

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
# histogram.sh sets HISTOGRAM_ONLY=1 to read the per-target counts and judge
# ONLY tier 1 (count vs baseline), so the histogram tool can stand alone without
# a red build on an unrelated compile rc. A plain check.sh run judges tiers 1+2.
if [ "$HISTOGRAM_ONLY" = 1 ]; then
  exit "$FAIL_COUNT"
fi
exit "$FAIL"