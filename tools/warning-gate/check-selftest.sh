#!/usr/bin/env bash
# Discriminating self-test for the adjudication logic in check.sh.
#
# Why this exists: check() ran a loose and a strict compiler invocation per
# target, printed both rcs, and then judged only the warning COUNT. A compiler
# that fails while emitting no countable `warning:` line yields n=0, so
# `0 <= baseline` held and the gate printed PASS for a build that never
# compiled. This test drives check() with rc/log pairs laid down by hand and
# pins BOTH directions: a compile failure must fail the column on its rc, and a
# clean column carrying its allowed warning stock must still pass - including
# the measured clean shape where the strict rc is non-zero anyway.
#
# check.sh is not sourceable (it runs the five compilers at file scope), so the
# adjudication functions are extracted by a documented awk range: everything
# from `run() {` up to the line before the loose/strict invocation block. If
# that structure changes the extraction is asserted below and the test aborts
# loudly instead of silently checking nothing.
#
# Usage: tools/warning-gate/check-selftest.sh [path/to/check.sh]
set -u

GATE=${1:-"$(cd "$(dirname "$0")" && pwd)/check.sh"}
echo "check-selftest: argv='$0' '$*'"
echo "check-selftest: cwd=$PWD"
echo "check-selftest: gate=$GATE"
echo "check-selftest: gate sha256=$(sha256sum "$GATE" | awk '{print $1}')"

LOGIC=$(awk '/^run\(\) \{/{p=1} p && /^# Keep the loose invocation/{p=0} p' "$GATE")
case "$LOGIC" in
  *'check() {'*) : ;;
  *) echo "check-selftest: FATAL: could not extract check() from $GATE (structure changed?)"; exit 2 ;;
esac
case "$LOGIC" in
  *'require_measured() {'*) : ;;
  *) echo "check-selftest: FATAL: could not extract require_measured() from $GATE"; exit 2 ;;
esac

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
OUT=$WORK/out
ROOT=$WORK
mkdir -p "$OUT"
FAIL=0
UNMEASURED=0
ALLOW_UNMEASURED=0
eval "$LOGIC"
echo "check-selftest: scratch=$OUT"

# One countable diagnostic line in the shape each column's counter matches.
diag_line() { # diag_line <col> <i>
  case "$1" in
    dart) echo "warning: injected diagnostic $2" ;;
    rust) echo "  --> boring/injected.rs:1:$2" ;;
    kotlin) echo "$OUT/injected.kt:1:$2: warning: injected diagnostic" ;;
    swift | typescript) echo "injected.swift:1:$2: warning: injected diagnostic" ;;
  esac
}

# seed <col> <loose_rc> <strict_rc> <warning_lines> [drop_rc]
# drop_rc: none|loose|strict  - omit that rc file, as if the invocation never ran.
seed() {
  local col=$1 lrc=$2 src=$3 lines=$4 drop=${5:-none} i=0
  : >"$OUT/$col.loose"
  : >"$OUT/$col.strict"
  while [ "$i" -lt "$lines" ]; do
    diag_line "$col" "$i" >>"$OUT/$col.loose"
    i=$((i + 1))
  done
  rm -f "$OUT/$col.loose.rc" "$OUT/$col.strict.rc"
  [ "$drop" = loose ] || echo "$lrc" >"$OUT/$col.loose.rc"
  [ "$drop" = strict ] || echo "$src" >"$OUT/$col.strict.rc"
}

PASSED=0
FAILED=0
case_run() { # case_run <col> <base> <label> <expected PASS|FAIL> [required-regex ...]
  local col=$1 base=$2 label=$3 expect=$4 want ok=1 got
  shift 4
  FAIL=0
  UNMEASURED=0
  # check() sets FAIL in ITS shell, so it must not run inside a command
  # substitution subshell - capture the transcript through a file and read FAIL
  # afterwards, otherwise every case would observe FAIL=0 and pass vacuously.
  check "$col" "$base" >"$WORK/case.log" 2>&1
  got=PASS
  [ "$FAIL" -eq 0 ] || got=FAIL
  [ "$got" = "$expect" ] || ok=0
  for want in "$@"; do
    [ "$want" = "-" ] && continue
    grep -qE "$want" "$WORK/case.log" || ok=0
  done
  if [ "$ok" -eq 1 ]; then
    echo "ok     $label [$got]"
    PASSED=$((PASSED + 1))
  else
    echo "NOT OK $label: got $got, expected $expect (wanted: $*)"
    sed 's/^/         | /' "$WORK/case.log"
    FAILED=$((FAILED + 1))
  fi
}

# --- the allowance is not broken by the rc wiring --------------------------
seed dart 0 0 46
case_run dart 46 "baseline 46/46, both rcs 0 -> PASS" PASS \
  'dart: loose=0 strict=0 warnings=46 baseline=46'

# The measured clean-kotlin shape: 59 warnings at baseline, -Werror turns them
# into rc=1 with no error lines. Wiring the strict rc unconditionally would
# redden this; it must stay green or the gate has become a zero-warning gate.
seed kotlin 0 1 59
case_run kotlin 59 "clean: strict rc=1 explained by 59 allowed warnings -> PASS" PASS \
  'kotlin: loose=0 strict=1 warnings=59 baseline=59'

# The measured clean-rust shape, where the strict log even says "could not
# compile ... due to 4 previous errors" - those errors are the 4 allowed ones.
seed rust 0 101 4
case_run rust 4 "clean: strict rc=101 explained by 4 allowed warnings -> PASS" PASS \
  'rust: loose=0 strict=101 warnings=4 baseline=4'

# --- the count rule still works on its own ---------------------------------
seed dart 0 0 47
case_run dart 46 "47 > baseline 46 -> FAIL on the count" FAIL \
  'has 47 warning\(s\), baseline is 46'

# --- the defect: the compiler failed and emitted no countable warning ------
seed kotlin 1 1 0
case_run kotlin 59 "injected syntax error: loose rc=1, strict rc=1, 0 warnings -> FAIL on rc" FAIL \
  'kotlin loose compile FAILED \(rc=1, not a warning-count regression\)' \
  'kotlin strict compile FAILED \(rc=1 with warnings=0'

# The loose rc is the un-confounded signal: it still catches the failure when
# the tree does emit countable warnings, where the count rule alone would pass.
seed rust 101 101 4
case_run rust 4 "compile failure with warnings present -> FAIL on the loose rc" FAIL \
  'rust loose compile FAILED \(rc=101, not a warning-count regression\)'

# Pure strict-column failure, loose side clean.
seed dart 0 2 0
case_run dart 46 "strict rc=2 with 0 warnings, loose clean -> FAIL on the strict rc" FAIL \
  'dart strict compile FAILED \(rc=2 with warnings=0'

# --- 127 stays "not measured": allowed on request, fatal by default -------
ALLOW_UNMEASURED=1
seed dart 0 127 0
case_run dart 46 "rc=127 with ALLOW_UNMEASURED=1 -> PASS (skipped)" PASS \
  'compiler not found \(rc=127\); column SKIPPED'
ALLOW_UNMEASURED=0
seed dart 0 127 0
case_run dart 46 "rc=127 without allowance -> FAIL (not measured)" FAIL \
  'compiler not found \(rc=127\); column NOT measured'

# --- an rc file that is absent means the column never ran ------------------
seed dart 0 0 46 strict
case_run dart 46 "missing strict rc file -> FAIL (not measured)" FAIL \
  'strict rc is not numeric'
seed dart 0 0 46 loose
case_run dart 46 "missing loose rc file -> FAIL (not measured)" FAIL \
  'loose rc is not numeric'

echo "check-selftest: passed=$PASSED failed=$FAILED"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
