#!/usr/bin/env bash
# T1 gate: type-check the generated TS trees under the project strict
# profile (the boring tsconfig profile). Regenerates out/ts/tsconfig.json
# because out/ is a generated tree; the profile lives here, in version
# control. TS6133 is NOT a gate criterion (ruling: task t-muhbc7gp-sg81
# timeline seq5, 2026-09-27): noUnusedLocals/noUnusedParameters stay off in
# this profile; run the probe separately via `tsc --noUnusedLocals
# --noUnusedParameters` and never change the gate baseline for it.
set -euo pipefail
TI_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# node_modules is a symlink in this worktree layout; resolve the real path
# so tsc's typeRoots lookup does not stop at the symlink boundary.
TYPES_ROOT="$(cd "$TI_ROOT" && pwd -P)/node_modules/@types"
OUT="$TI_ROOT/engine-haxe/out/ts"
[ -d "$OUT/gen" ] || { echo "ts-gate: $OUT/gen missing; run the bundle driver gen ts first" >&2; exit 2; }
# The profile needs @types/bun for the `types: ["bun"]` entry. Without it
# tsc silently type-checks nothing that matters; fail loudly instead of
# reporting a zero-diagnostic read nobody ran.
if [ ! -d "$TI_ROOT/node_modules/@types/bun" ]; then
  echo "ts-gate: $TI_ROOT/node_modules/@types/bun missing; run 'npm install' at the tiqian root first" >&2
  exit 2
fi

# Pin the repo-local tsc (typescript 5.9.3): a fetched-latest tsc drifts the
# diagnostic set between runs (observed: 744 vs 745 with 9 TS2307 flipping),
# and the gate must keep one frozen reading basis.
TSC="$TI_ROOT/node_modules/.bin/tsc"
[ -x "$TSC" ] || { echo "ts-gate: $TSC missing; run 'npm install' at the tiqian root first" >&2; exit 2; }

# Verify the exact TSC version before writing the tsconfig or running checks.
TSC_VERSION=""
if ! TSC_VERSION="$("$TSC" --version 2>&1)"; then
  echo "ts-gate: $TSC --version failed: $TSC_VERSION" >&2
  exit 2
fi
if [ "$TSC_VERSION" != "Version 5.9.3" ]; then
  echo "ts-gate: expected tsc Version 5.9.3, got '$TSC_VERSION'" >&2
  exit 2
fi

cat > "$OUT/tsconfig.json" <<'JSON'
{
  "compilerOptions": {
    "target": "esnext",
    "module": "esnext",
    "moduleResolution": "bundler",
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noImplicitOverride": true,
    "noFallthroughCasesInSwitch": true,
    "allowImportingTsExtensions": true,
    "erasableSyntaxOnly": true,
    "types": ["bun"],
    "typeRoots": ["$TYPES_ROOT"],
    "noEmit": true,
    "skipLibCheck": true
  },
  "include": ["gen", "gen-tests"]
}
JSON
sed -i "s|\$TYPES_ROOT|$TYPES_ROOT|" "$OUT/tsconfig.json"

cd "$OUT"
# Bound the run: a wedged resolver must read as a failed gate, not a hang.
exec timeout 900 "$TSC" -p tsconfig.json
