#!/usr/bin/env bash
# Reverse assertion for the rust-engine-capture fixture (TCN-302 / P-24).
#
# The positive green (cargo build RC=0) alone cannot catch a dead-code
# elimination or a silent degradation to a bare &mut borrow. This check scans
# the GENERATED Rust for the exact ABI shape the policy requires and fails if
# the emitter regressed.
#
# Assertions (by mapped symbol, not by grep of a type name):
#   1. engine_make_capture's parameter is the handle Rc<RefCell<Engine>>.
#   2. The parameter is NOT a bare borrow (&Engine / &mut Engine).
#   3. The generated file exists (the path was really emitted, not
#      dead-code-eliminated).
#
# Exit 0 = green (correct handle form). Exit 1 = red (degraded or missing).
set -u
GEN_DIR="${1:?usage: check.sh <generated-rust-dir>}"
FILE="$GEN_DIR/probe/engine.rs"

if [ ! -f "$FILE" ]; then
  echo "RED: $FILE missing (path was dead-code-eliminated or not emitted)"
  exit 1
fi

# 1. handle parameter present
if ! grep -q 'fn engine_make_capture(engine: Rc<RefCell<Engine>>)' "$FILE"; then
  echo "RED: engine_make_capture parameter is not Rc<RefCell<Engine>>"
  exit 1
fi

# 2. no bare borrow in the ABI position
if grep -qE 'fn engine_make_capture\((engine: )?&(mut )?Engine' "$FILE"; then
  echo "RED: engine_make_capture parameter degraded to a bare borrow"
  exit 1
fi

echo "GREEN: engine_make_capture is Rc<RefCell<Engine>> (handle), not a bare borrow"
exit 0
