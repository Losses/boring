#!/usr/bin/env bash
# Four acceptance gates for the Haxe port tree, run through serial-test.sh so
# parallel lanes queue instead of racing. Usage (from the WORKTREE ROOT,
# because compile.hxml classpaths are root-relative):
#
#   nix develop -c bash engine-haxe/tools/gates.sh [all|g4|tests|compare|ts]
#
# Gates:
#   g4      compile the engine with targets/kotlin-f32.hxml, print G4-RC
#   tests   compile the test bundle (tests/compile.hxml), then run it with
#           bun and print the FAIL line count (want 0)
#   compare tolerance-compare produced traces against baseline goldens for
#           every class registered in tests/Main.hx via flushClass
#   ts      type-check generated TS trees under the project strict profile,
#           print TS-RC (delegates to ts-gate.sh); 0 = zero diagnostics
# all runs g4, tests, compare, ts in order and prints a one-line summary.
set -u
cd "$(git rev-parse --show-toplevel)"
HERE="$(git rev-parse --show-toplevel)"

run_g4() {
  haxe engine-haxe/targets/kotlin-f32.hxml >/dev/null 2>&1
  echo "G4-RC=$?"
}

run_tests() {
  haxe engine-haxe/tests/compile.hxml
  local compile_rc=$?
  if [ "$compile_rc" -ne 0 ]; then
    echo "TESTS-COMPILE-RC=$compile_rc"
    return 1
  fi
  rm -f engine-haxe/out/haxe-traces/*.txt
  bun engine-haxe/out/haxe-tests.js 2>&1 | grep -c "^FAIL"
}

run_compare() {
  local classes
  classes="$(grep -o 'flushClass("[^"]*")' engine-haxe/tests/Main.hx \
    | sed 's/flushClass("//;s/")//' | paste -sd,)"
  python3 engine-haxe/tools/compare-traces.py \
    engine-haxe/baseline-goldens/test-traces engine-haxe/out/haxe-traces \
    --mode tolerance --classes "$classes"
  echo "COMPARE-RC=$?"
}

run_ts() {
  bash engine-haxe/tools/ts-gate.sh
  local rc=$?
  echo "TS-RC=$rc"
  return "$rc"
}

what="${1:-all}"
case "$what" in
  g4) run_g4 ;;
  tests) run_tests ;;
  compare) run_compare ;;
  ts) run_ts ;;
  all)
    run_g4
    run_tests
    run_compare
    run_ts
    ;;
  *)
    echo "usage: gates.sh [all|g4|tests|compare|ts]" >&2
    exit 2
    ;;
esac
