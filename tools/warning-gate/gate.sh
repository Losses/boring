#!/usr/bin/env bash
# Four-tier composite gate.
#
#   tier 1  gen warnings      - per-target warning count vs frozen baseline
#   tier 2  compile warnings  - loose/strict rc adjudication
#   tier 3  unit tests        - bun run test
#   tier 4  guards            - check:roots / check:precision / check:registry /
#                               check:ledger / check:docs / check:mapping /
#                               check:invariants
#
# check.sh is run ONCE and its transcript carries the histogram, the
# tier1/tier2 verdict lines, and the aggregate WARNING GATE PASS/FAIL, so this
# composite cannot diverge from what check.sh already decided. The two tier
# lines are the interface; they are extracted by sed below and default to FAIL
# if missing.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT" || exit 1

LOG=$(mktemp)
trap 'rm -f "$LOG" "$LOG.driver"' EXIT

FAIL=0
log_tier() { # log_tier <tier-label> <PASS|FAIL>
  echo "gate: $1 = $2"
  [ "$2" = PASS ] || FAIL=1
}

echo "gate: four-tier composite (cwd=$PWD)"

# tiers 1 + 2: one check.sh run provides both verdicts.
bash tools/warning-gate/check.sh >"$LOG" 2>&1
grep -E '^(target |dart |kotlin |rust |swift |typescript |warning-gate: tier|WARNING GATE)' "$LOG" || true
t1=$(sed -n 's/^warning-gate: tier1 gen-warnings = //p' "$LOG" | tail -1)
t2=$(sed -n 's/^warning-gate: tier2 compile-warnings = //p' "$LOG" | tail -1)
[ -n "$t1" ] || t1=FAIL
[ -n "$t2" ] || t2=FAIL
log_tier "tier1 gen-warnings" "$t1"
log_tier "tier2 compile-warnings" "$t2"

# tier 3: unit tests.
#
# `bun run test` collects tests/driver/** and tests/npm-pack-scoped/**, and every
# case there spawns the built artifact out/driver/driver.js. Neither a gen:*
# script nor the dev shell produces it in the worktree (the `driver` package
# derivation compiles it inside its own build directory and installs it to
# $out/share/boring/driver.js), so tier 3 compiles it here with the same command
# the collected-suite job runs in its own step. Without it each collected case
# fails with `error: Module not found ".../out/driver/driver.js"`, so a missing
# prerequisite is reported as a test verdict: measured on a clean checkout,
# 28 fail / 0 pass (27 in tests/driver/ plus tests/npm-pack-scoped/). A driver
# build that does not run is NOT a skipped column - it fails tier 3, the same
# way check.sh fails a column it could not measure.
DRIVER_LOG="$LOG.driver"
if ! mkdir -p out/driver || ! haxe packages/driver/driver.hxml >"$DRIVER_LOG" 2>&1; then
  echo "gate: tier3 driver build failed:"
  tail -40 "$DRIVER_LOG" || true
  log_tier "tier3 unit-tests" FAIL
elif bun run test >"$LOG" 2>&1; then
  log_tier "tier3 unit-tests" PASS
else
  echo "gate: tier3 unit-tests failed:"
  tail -40 "$LOG" || true
  log_tier "tier3 unit-tests" FAIL
fi

# tier 4: guards.
for guard in check:roots check:precision check:registry check:ledger check:docs check:mapping check:invariants; do
  if bun run "$guard" >"$LOG" 2>&1; then
    log_tier "tier4 $guard" PASS
  else
    echo "gate: tier4 $guard failed:"
    tail -40 "$LOG" || true
    log_tier "tier4 $guard" FAIL
  fi
done

echo "gate: verdict = $([ "$FAIL" -eq 0 ] && echo PASS || echo FAIL)"
exit "$FAIL"
