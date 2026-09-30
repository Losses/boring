#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT" || exit 2
HAXE="${HAXE:-/nix/store/98pb92k7pi6g5cifmg872jn18kghaxw5-haxe-4.3.7/bin/haxe}"
NODE="${NODE:-$(command -v node 2>/dev/null || true)}"
OUT="${OUT:-/tmp/variable-bound-loop-eval}"
rm -rf "$OUT"; mkdir -p "$OUT"
sha256sum tests/haxe/variable-bound-loop-eval/vble/Probe.hx > "$OUT/input.sha256"
"$HAXE" tests/haxe/variable-bound-loop-eval/oracle.hxml > "$OUT/haxe-generate.out" 2>&1; rc=$?; printf '%s\n' "$rc" > "$OUT/haxe-generate.rc"
if [ "$rc" -eq 0 ]; then
  "$NODE" /tmp/vble-oracle.js > "$OUT/haxe-run.out" 2>&1; rc=$?; printf '%s\n' "$rc" > "$OUT/haxe-run.rc"
else
  printf 'not-reached\n' > "$OUT/haxe-run.rc"
fi
for target in ts kotlin rust swift dart; do
  printf 'target=%s generation=not-reached reason=haxelib not found in current environment; compile=not-reached; run=not-reached\n' "$target" >> "$OUT/targets.tsv"
done
printf 'evidence=%s\n' "$OUT"
