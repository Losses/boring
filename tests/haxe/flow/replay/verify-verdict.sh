#!/usr/bin/env bash
# Bounded controls over the production verdict chain.
#
# Each control writes one complete attempt in the attempt layout and then
# measures it with the commands the caller runs: the membership adapter, the
# shared stage checker, the compare entry and the finalize entry. One control is
# the complete passing declared-observation case; every other control derives
# from it by changing exactly one condition and keeps the other obligations of
# the frozen declaration unchanged. They never run a compiler, never forge or
# overwrite historical child evidence, and never write outside their directory.
#
# Run: nix develop -c bash tests/haxe/flow/replay/verify-verdict.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPLAY="$(cd "$SCRIPT_DIR" && pwd)"
ROOT="$(cd "$REPLAY/../../../.." && pwd)"
cd "$ROOT"

# The frozen declaration and the authored expectations are copied into the
# verifier's own directory, so every control reads the unchanged obligations
# from one place.
FROZEN="${FLOW_OUT:-out/flow}/verifier-$(date +%s%3N)-$$/frozen"
OUT="$(dirname "$FROZEN")"
mkdir -p "$FROZEN/expected"
echo "verifier directory: $OUT"
cp "$REPLAY/stages.json" "$FROZEN/stages.json"
cp "$REPLAY/expected/normalized.txt" "$FROZEN/expected/normalized.txt"
cp "$REPLAY/expected/stable-local.txt" "$FROZEN/expected/stable-local.txt"

SHARED="$ROOT/tests/support/stage-check.sh"
if [ ! -f "$SHARED" ]; then
    echo "FAIL shared-checker: tests/support/stage-check.sh is not part of this revision" | tee "$OUT/controls.txt"
    echo "verifier verdict: 1 defect(s)" | tee -a "$OUT/controls.txt"
    exit 1
fi
sha256sum "$SHARED" > "$OUT/shared-stage-check.sha256"

STATUS=0
bun "$REPLAY/verdict.ts" verify --out "$OUT" --replay "$FROZEN" --stage-check "$SHARED" \
    | tee "$OUT/controls.txt" || STATUS=$?
if grep -q "^FAIL " "$OUT/controls.txt"; then
    STATUS=1
fi

echo "verifier verdict: $(grep -c '^FAIL ' "$OUT/controls.txt" || true) defect(s)"
echo "verifier directory: $OUT"
if [ "$STATUS" -ne 0 ]; then
    exit 1
fi
exit 0
