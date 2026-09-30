#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FIXTURE_DIR="$ROOT_DIR/tests/haxe/ts-source-origin"
mkdir -p "$ROOT_DIR/out/ts-source-origin"
OUTPUT_ROOT="$(mktemp -d "$ROOT_DIR/out/ts-source-origin/attempt-XXXXXXXX")"
FIRST="$OUTPUT_ROOT/first"
SECOND="$OUTPUT_ROOT/second"
PLAIN="$OUTPUT_ROOT/without-origins"
EXTRA="$OUTPUT_ROOT/extra"
TSC_BIN="${TSC:-tsc}"
assert_baseline() {
	local path="$1"
	local expected="$2"
	local actual
	actual="$(sha256sum "$path" | cut -d' ' -f1)"
	if [[ "$actual" != "$expected" ]]; then
		printf 'generated TypeScript differs from pinned baseline: %s (%s)\n' "$path" "$actual" >&2
		exit 1
	fi
}

cd "$ROOT_DIR"
mkdir -p "$FIRST" "$SECOND" "$PLAIN" "$EXTRA"

haxe tests/haxe/ts-source-origin/ts-origin.hxml -D "ts-output=$FIRST" -D ts-source-origins
haxe tests/haxe/ts-source-origin/ts-origin.hxml -D "ts-output=$SECOND" -D ts-source-origins
haxe tests/haxe/ts-source-origin/ts-origin.hxml -D "ts-output=$PLAIN"
haxe tests/haxe/ts-source-origin/ts-origin-extra.hxml -D "ts-output=$EXTRA" -D ts-source-origins

cmp "$FIRST/OriginSubject.ts" "$SECOND/OriginSubject.ts"
cmp "$FIRST/OriginSubject.ts.origins.json" "$SECOND/OriginSubject.ts.origins.json"
for relative in OriginSubject.ts OriginImported.ts std/UStringException.ts std/UStringFault.ts; do
	cmp "$FIRST/$relative" "$SECOND/$relative"
	cmp "$FIRST/$relative" "$PLAIN/$relative"
done
if find "$PLAIN" -name '*.origins.json' -print -quit | rg -q .; then
	printf '%s\n' "sidecar was emitted without the opt-in define" >&2
	exit 1
fi
assert_baseline "$FIRST/OriginSubject.ts" 2e5590cbcb680421977941e2e7ab2692ce8eab1e4661ccadc35c3f24a3c35378
assert_baseline "$FIRST/OriginImported.ts" 4e543272061031b72e289e8eb2fa49c3d94b31b9e31b21506ec20f6f19d95848
assert_baseline "$FIRST/std/UStringException.ts" 232849f763270f00db6f85d0bf108c019d2f6691665e286f05f4efd33b5967dc
assert_baseline "$FIRST/std/UStringFault.ts" 87e1514baa7cd150a114f7ac8407e8559d1d47a66dd1ec894cd7b3f7ed0df0c9
bun "$FIXTURE_DIR/check.ts" check "$FIRST/OriginSubject.ts" "$FIRST/OriginSubject.ts.origins.json"
bun "$FIXTURE_DIR/check.ts" helper "$EXTRA/OriginExtra.ts" "$EXTRA/OriginExtra.ts.origins.json"

"$TSC_BIN" --version
"$TSC_BIN" --noEmit --target ES2022 --moduleResolution node --allowImportingTsExtensions --strict "$FIRST/OriginSubject.ts"
"$TSC_BIN" --noEmit --target ES2022 --moduleResolution node --allowImportingTsExtensions --strict "$EXTRA/OriginExtra.ts"

bun "$FIXTURE_DIR/check.ts" swap "$FIRST/OriginSubject.ts.origins.json" "$OUTPUT_ROOT/swapped.origins.json"
if bun "$FIXTURE_DIR/check.ts" check "$FIRST/OriginSubject.ts" "$OUTPUT_ROOT/swapped.origins.json" >"$OUTPUT_ROOT/swapped-check.log" 2>&1; then
	printf '%s\n' "swapped occurrence control unexpectedly passed" >&2
	exit 1
fi
if ! rg -q "first source occurrence must be line 10" "$OUTPUT_ROOT/swapped-check.log"; then
	cat "$OUTPUT_ROOT/swapped-check.log" >&2
	printf '%s\n' "swapped occurrence control failed for an unexpected reason" >&2
	exit 1
fi
printf '%s\n' "swapped occurrence control failed at the intended source-range assertion"

sha256sum "$FIRST/OriginSubject.ts" "$SECOND/OriginSubject.ts" \
	"$FIRST/OriginImported.ts" "$FIRST/std/UStringException.ts" "$FIRST/std/UStringFault.ts" \
	"$PLAIN/OriginSubject.ts" "$FIRST/OriginSubject.ts.origins.json" "$SECOND/OriginSubject.ts.origins.json"
printf 'retained attempt: %s\n' "$OUTPUT_ROOT"
