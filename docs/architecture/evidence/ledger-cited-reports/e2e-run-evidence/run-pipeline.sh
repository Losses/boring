#!/usr/bin/env bash
# E2E CI-shaped run of the collected suite. Evidence-only; touches nothing tracked.
set -u
REPO=/home/losses/Development/tq-workspace/boring-wt-architecture
OUT=/home/losses/Development/tq-workspace/dc-warn/out/e2e-run
EV=$OUT/evidence
export PATH="$(grep -m1 '^PATH=' /home/losses/Development/tq-workspace/dc-warn/out/chainA-fixed-rerun/evidence/env.json | cut -d= -f2-)"
cd "$REPO"
E="$EV/stage-exits.txt"; : > "$E"
stage() { # stage <name> -- runs "$@" writing raw output to evidence/<name>.log
  local name="$1"; shift
  echo "== stage $name start $(date -Is)" >> "$E"
  "$@" > "$EV/$name.log" 2>&1
  local rc=$?
  echo "$name rc=$rc end $(date -Is)" >> "$E"
  if [ $rc -ne 0 ]; then echo "ABORT at $name rc=$rc $(date -Is)" >> "$E"; exit $rc; fi
}
stage bun-install bun install
for g in ts kotlin kotlin-f32 rust rust-f32 swift swift-f32 dart; do
  stage "gen:$g" bun run "gen:$g"
done
# Blocking suite. CI uses `nix develop -c bash -c 'bun run test'`; here the
# toolchain comes from the chainA PATH env (substitution recorded in REPORT.md).
stage collected-suite bun run test
echo "ALL-STAGES-DONE $(date -Is)" >> "$E"
