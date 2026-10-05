#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FIXTURE_DIR="$ROOT_DIR/tests/haxe/ts-package-diagnostic-resolution"
# The runner requires an explicit tsc path: an unset TSC or a bare command
# name would silently resolve through PATH, so both are rejected.
TSC_BIN="${TSC:-}"
if [[ -z "$TSC_BIN" ]]; then
	printf '%s\n' 'TSC is not set: refusing silent PATH fallback; set TSC to an explicit tsc path' >&2
	exit 2
fi
case "$TSC_BIN" in
*/*) ;;
*)
	printf 'TSC=%s is a bare command name; set TSC to an explicit path instead\n' "$TSC_BIN" >&2
	exit 2
	;;
esac
if [[ ! -x "$TSC_BIN" ]]; then
	printf 'TSC=%s is not an executable file\n' "$TSC_BIN" >&2
	exit 2
fi
mkdir -p "$ROOT_DIR/out/ts-package-diagnostic-resolution"
OUTPUT_ROOT="$(mktemp -d "$ROOT_DIR/out/ts-package-diagnostic-resolution/attempt-XXXXXXXX")"
WRAPPER="$OUTPUT_ROOT/package-tsc-wrapper.sh"
INVOCATIONS="$OUTPUT_ROOT/tsc-invocations.log"
cd "$ROOT_DIR"
INPUTS=(packages/compiler/PackageArtifacts.hx tests/haxe/ts-package-diagnostic-resolution/*)
sha256sum "${INPUTS[@]}" > "$OUTPUT_ROOT/input-hashes-before.txt"
printf 'nix develop -c bash -c "TSC=%s bash tests/haxe/ts-package-diagnostic-resolution/run.sh"\n' "$TSC_BIN" > "$OUTPUT_ROOT/command.txt"
{
	printf 'cwd=%s\n' "$PWD"
	printf 'argv='
	printf '"%s" ' "$0" "$@"
	printf '\n'
} > "$OUTPUT_ROOT/runner-argv-cwd.txt"
# Record the exact executable identity every tsc invocation in this run uses:
# requested path, resolved realpath, sha256 of the real file and the compiler
# own --version line. Any failure here aborts the run.
TSC_REAL="$(realpath -- "$TSC_BIN")"
TSC_SHA256="$(sha256sum -- "$TSC_REAL" | awk '{print $1}')"
TSC_VERSION="$( "$TSC_REAL" --version 2>&1 | head -n 1 )"
{
	printf 'tsc-requested=%s\n' "$TSC_BIN"
	printf 'tsc-realpath=%s\n' "$TSC_REAL"
	printf 'tsc-sha256=%s\n' "$TSC_SHA256"
	printf 'tsc-version=%s\n' "$TSC_VERSION"
} > "$OUTPUT_ROOT/tsc-identity.txt"
finish() {
	local status="$?"
	trap - EXIT
	set +e
	sha256sum "${INPUTS[@]}" > "$OUTPUT_ROOT/input-hashes-after.txt"
	if ! cmp -s "$OUTPUT_ROOT/input-hashes-before.txt" "$OUTPUT_ROOT/input-hashes-after.txt"; then
		printf '%s\n' 'selected inputs changed during the run' > "$OUTPUT_ROOT/input-mutation.txt"
		status=1
	fi
	printf '%s\n' "$status" > "$OUTPUT_ROOT/runner.exit"
	exit "$status"
}
trap finish EXIT
# --- compiler provenance gate ------------------------------------------------
# The hxml files below compile with the haxelib-resolved `boring` classpath
# (and its dependencies) loaded by the haxe toolchain, so the compiler bytes
# of the run are whatever the haxelib repository resolves, not necessarily
# the bytes of this checkout. Bind the run to the bytes it will actually
# load: record `haxelib path boring` with its argv, cwd, streams and status,
# and require its realpath to sit under this checkout. A wrong HAXELIB_PATH
# that still resolves (a sibling checkout's or a store source's `.haxelib`)
# fails non-zero here, before any compile, so the input hashes recorded
# above can never describe a run whose compiler came from elsewhere ("hash A
# executed B"). This haxelib build resolves its repository from the nearest
# `.haxelib` directory walked up from the working directory; the recorded
# HAXELIB_PATH value documents the repository the dev shell names.
PROV="$OUTPUT_ROOT/haxelib-path-boring"
printf 'haxelib\0path\0boring\0' > "$PROV.argv"
printf '%s\n' "$ROOT_DIR" > "$PROV.cwd"
set +e
haxelib path boring > "$PROV.stdout" 2> "$PROV.stderr"
PROV_STATUS=$?
set -e
printf '%s\n' "$PROV_STATUS" > "$PROV.status"
# The path line immediately before "-D boring=" is the library this haxelib
# build resolved; fall back to the first absolute line when that marker is
# absent. Every candidate line stays in $PROV.stdout for audit.
BORING_RESOLVED="$(awk '/^-D boring=/{print prev; exit} {prev=$0}' "$PROV.stdout" || true)"
if [[ -z "$BORING_RESOLVED" ]]; then
	BORING_RESOLVED="$(grep -E '^/' "$PROV.stdout" | head -n 1 || true)"
fi
BORING_REAL=""
if [[ -n "$BORING_RESOLVED" && -e "$BORING_RESOLVED" ]]; then
	BORING_REAL="$(readlink -f "$BORING_RESOLVED")"
fi
ROOT_REAL="$(readlink -f "$ROOT_DIR")"
HAXE_BIN_REAL="$(readlink -f "$(command -v haxe)" 2>/dev/null || true)"
BORING_UNDER_ROOT=no
case "$BORING_REAL" in
	"$ROOT_REAL" | "$ROOT_REAL"/*) BORING_UNDER_ROOT=yes ;;
esac
BORING_MANIFEST="$ROOT_REAL/haxelib.json"
{
	printf 'compiler provenance\n'
	printf 'HAXELIB_PATH: %s\n' "${HAXELIB_PATH:-unset}"
	printf 'haxelib path boring (raw): %s\n' "$BORING_RESOLVED"
	printf 'boring-resolved-path (realpath): %s\n' "${BORING_REAL:-none}"
	printf 'checkout root (realpath): %s\n' "$ROOT_REAL"
	printf 'boring resolved under root: %s\n' "$BORING_UNDER_ROOT"
	printf 'haxe binary: %s\n' "${HAXE_BIN_REAL:-none}"
	if [[ -n "$HAXE_BIN_REAL" ]]; then
		sha256sum "$HAXE_BIN_REAL"
	fi
	printf 'haxe version: %s\n' "$(haxe --version 2>&1 || true)"
	if [[ -f "$BORING_MANIFEST" ]]; then
		sha256sum "$BORING_MANIFEST"
	fi
	if [[ -n "$BORING_REAL" && -f "$BORING_REAL/Intercept.hx" ]]; then
		sha256sum "$BORING_REAL/Intercept.hx"
	fi
	printf 'compiler bytes under %s:\n' "${BORING_REAL:-none}"
	if [[ -n "$BORING_REAL" && -d "$BORING_REAL" ]]; then
		find "$BORING_REAL" -type f -print0 | sort -z | xargs -0 -r sha256sum
	fi
	printf 'end compiler provenance\n'
} > "$OUTPUT_ROOT/compiler-provenance.txt"
if [[ "$BORING_UNDER_ROOT" != "yes" ]]; then
	printf 'compiler provenance gate failed: haxelib path boring resolves to %s, not under %s; evidence retained in %s\n' \
		"${BORING_REAL:-<unresolved>}" "$ROOT_REAL" "$OUTPUT_ROOT" >&2
	exit 2
fi
cp "$FIXTURE_DIR/package-tsc-wrapper.sh" "$WRAPPER"
chmod +x "$WRAPPER"
: > "$INVOCATIONS"

run_haxe_failure() {
	local label="$1"
	shift
	set +e
	"$@" > "$OUTPUT_ROOT/$label.stdout" 2> "$OUTPUT_ROOT/$label.stderr"
	local status=$?
	set -e
	printf '%s\n' "$status" > "$OUTPUT_ROOT/$label.exit"
	if [[ "$status" -eq 0 ]]; then
		printf 'expected Haxe failure for %s\n' "$label" >&2
		exit 1
	fi
}

run_haxe_success() {
	local label="$1"
	shift
	set +e
	"$@" > "$OUTPUT_ROOT/$label.stdout" 2> "$OUTPUT_ROOT/$label.stderr"
	local status=$?
	set -e
	printf '%s\n' "$status" > "$OUTPUT_ROOT/$label.exit"
	if [[ "$status" -ne 0 ]]; then
		printf 'expected Haxe success for %s\n' "$label" >&2
		exit 1
	fi
}

export TS_DIAGNOSTIC_INVOCATIONS="$INVOCATIONS"
export TS_DIAGNOSTIC_REAL_TSC="$TSC_BIN"
export TS_DIAGNOSTIC_MUTATOR="$FIXTURE_DIR/stage-mutation.ts"
export TS_DIAGNOSTIC_MODE=none
export TS_DIAGNOSTIC_STRESS=0

VALID_OUT="$OUTPUT_ROOT/valid/tree"
mkdir -p "$VALID_OUT"
export TS_DIAGNOSTIC_MODE=empty-check
export TS_DIAGNOSTIC_TSC_STDOUT="$OUTPUT_ROOT/valid/tsc.stdout"
export TS_DIAGNOSTIC_TSC_STDERR="$OUTPUT_ROOT/valid/tsc.stderr"
export TS_DIAGNOSTIC_TSC_STATUS="$OUTPUT_ROOT/valid/tsc.status"
run_haxe_success valid haxe tests/haxe/ts-package-diagnostic-resolution/ts-diagnostic.hxml \
	-D "ts-output=$VALID_OUT" -D "package-tsc=$WRAPPER"
VALID_TGZ="$OUTPUT_ROOT/valid/ts-diagnostic-resolution-0.1.0.tgz"
test -f "$VALID_TGZ"
rg -q '^exit=0 stdout-bytes=0 stderr-bytes=0$' "$TS_DIAGNOSTIC_TSC_STATUS"
VALID_STAGE="$(head -n 1 "$INVOCATIONS")"
test ! -e "$VALID_STAGE"
rg -q 'from "\./DiagnosticPeer.ts"' "$VALID_OUT/DiagnosticSubject.ts"
if tar -tzf "$VALID_TGZ" | rg -q '\.origins\.json$'; then
	printf '%s\n' "source origin sidecars must not enter the npm archive" >&2
	exit 1
fi

SUCCESS_OUT="$OUTPUT_ROOT/success-output/tree"
mkdir -p "$SUCCESS_OUT"
export TS_DIAGNOSTIC_MODE=success-output
export TS_DIAGNOSTIC_TSC_STDOUT="$OUTPUT_ROOT/success-output/tsc.stdout"
export TS_DIAGNOSTIC_TSC_STDERR="$OUTPUT_ROOT/success-output/tsc.stderr"
export TS_DIAGNOSTIC_TSC_STATUS="$OUTPUT_ROOT/success-output/tsc.status"
run_haxe_success success-output haxe tests/haxe/ts-package-diagnostic-resolution/ts-diagnostic.hxml \
	-D "ts-output=$SUCCESS_OUT" -D "package-tsc=$WRAPPER"
rg -q '^exit=0 stdout-bytes=0 stderr-bytes=0$' "$TS_DIAGNOSTIC_TSC_STATUS"
rg -q '^successful tsc stdout marker$' "$OUTPUT_ROOT/success-output.stdout"
rg -q '^successful tsc stderr marker$' "$OUTPUT_ROOT/success-output.stderr"
test ! -e "$OUTPUT_ROOT/success-output/.package-npm-stage"

MAPPED_OUT="$OUTPUT_ROOT/mapped/tree"
mkdir -p "$MAPPED_OUT"
export TS_DIAGNOSTIC_MODE=mapped
export TS_DIAGNOSTIC_STRESS=1
export TS_DIAGNOSTIC_SIDECAR="$MAPPED_OUT/DiagnosticSubject.ts.origins.json"
run_haxe_failure mapped haxe tests/haxe/ts-package-diagnostic-resolution/ts-diagnostic.hxml \
	-D "ts-output=$MAPPED_OUT" -D "package-tsc=$WRAPPER"
test "$(cat "$OUTPUT_ROOT/mapped.exit")" -eq 1
MAPPED_STAGE="$(cat "$INVOCATIONS" | tail -n 1)"
SELECTED="$MAPPED_STAGE/DiagnosticSubject.ts.selected.json"
rg -q 'from "\./DiagnosticPeer.js"' "$MAPPED_STAGE/DiagnosticSubject.ts"
TS_CHILD_STDOUT="$MAPPED_STAGE/.package-tsc-stdout"
TS_CHILD_STDERR="$MAPPED_STAGE/.package-tsc-stderr"
cmp "$TS_CHILD_STDOUT" "$OUTPUT_ROOT/mapped.stdout"
child_stderr_bytes="$(wc -c < "$TS_CHILD_STDERR")"
head -c "$child_stderr_bytes" "$OUTPUT_ROOT/mapped.stderr" > "$OUTPUT_ROOT/mapped.child-stderr-prefix"
cmp "$TS_CHILD_STDERR" "$OUTPUT_ROOT/mapped.child-stderr-prefix"
bun "$FIXTURE_DIR/assert.ts" mapped "$OUTPUT_ROOT/mapped.stdout" "$OUTPUT_ROOT/mapped.stderr" "$SELECTED"
test "$(basename "$MAPPED_STAGE")" = .package-npm-stage
if find "$MAPPED_STAGE" -name '*.origins.json' -print -quit | rg -q .; then
	printf '%s\n' "sidecar unexpectedly entered npm staging" >&2
	exit 1
fi
if rg -q 'DiagnosticSubject\.emit\(0\)' "$MAPPED_OUT/DiagnosticSubject.ts"; then
	printf '%s\n' "test mutation changed the original generated TypeScript" >&2
	exit 1
fi

RELATIVE_OUT="$OUTPUT_ROOT/relative/tree"
mkdir -p "$RELATIVE_OUT"
export TS_DIAGNOSTIC_MODE=mapped
export TS_DIAGNOSTIC_STRESS=0
export TS_DIAGNOSTIC_SIDECAR="$RELATIVE_OUT/DiagnosticSubject.ts.origins.json"
run_haxe_failure relative haxe tests/haxe/ts-package-diagnostic-resolution/ts-diagnostic.hxml \
	-D "ts-output=${RELATIVE_OUT#"$ROOT_DIR"/}" -D "package-tsc=$WRAPPER"
RELATIVE_STAGE="$(tail -n 1 "$INVOCATIONS")"
bun "$FIXTURE_DIR/assert.ts" mapped-no-stress "$OUTPUT_ROOT/relative.stdout" "$OUTPUT_ROOT/relative.stderr" "$RELATIVE_STAGE/DiagnosticSubject.ts.selected.json"

test -f /etc/passwd
test -f ../../../../../../etc/passwd
test "$(wc -c < /etc/passwd)" -gt 179
ESCAPE_LINK="$OUTPUT_ROOT/source-link.hx"
ln -s /etc/passwd "$ESCAPE_LINK"
export TS_DIAGNOSTIC_ESCAPE_SOURCE="${ESCAPE_LINK#"$ROOT_DIR"/}"
test -f "$ESCAPE_LINK"
test "$(readlink -f "$ESCAPE_LINK")" = /etc/passwd
printf 'existing relative outside path: %s\nsymlink target: %s\noutside bytes: %s\n' \
	../../../../../../etc/passwd "$(readlink -f "$ESCAPE_LINK")" "$(wc -c < /etc/passwd)" > "$OUTPUT_ROOT/escape-control.txt"
for mode in malformed-sidecar bad-generated-file bad-generated-range bad-source-range bad-source-path bad-source-symlink bad-source-order; do
	BAD_OUT="$OUTPUT_ROOT/$mode/tree"
	mkdir -p "$BAD_OUT"
	export TS_DIAGNOSTIC_MODE="$mode"
	export TS_DIAGNOSTIC_SIDECAR="$BAD_OUT/DiagnosticSubject.ts.origins.json"
	run_haxe_failure "$mode" haxe tests/haxe/ts-package-diagnostic-resolution/ts-diagnostic.hxml \
		-D "ts-output=$BAD_OUT" -D "package-tsc=$WRAPPER"
	rg -q 'source resolution: Unmapped \(invalid source origin' "$OUTPUT_ROOT/$mode.stderr"
	rg -q 'error TS2345:' "$OUTPUT_ROOT/$mode.stdout"
done

HELPER_OUT="$OUTPUT_ROOT/helper/tree"
mkdir -p "$HELPER_OUT"
export TS_DIAGNOSTIC_MODE=helper
export TS_DIAGNOSTIC_STRESS=0
export TS_DIAGNOSTIC_SIDECAR="$HELPER_OUT/DiagnosticHelper.ts.origins.json"
run_haxe_failure helper haxe tests/haxe/ts-package-diagnostic-resolution/ts-helper.hxml \
	-D "ts-output=$HELPER_OUT" -D "package-tsc=$WRAPPER"
bun "$FIXTURE_DIR/assert.ts" helper "$OUTPUT_ROOT/helper.stdout" "$OUTPUT_ROOT/helper.stderr"
HELPER_STAGE="$(cat "$INVOCATIONS" | tail -n 1)"
test "$(basename "$HELPER_STAGE")" = .package-npm-stage
test ! -s "$HELPER_STAGE/.package-tsc-stderr"
cmp "$HELPER_STAGE/.package-tsc-stdout" "$OUTPUT_ROOT/helper.stdout"
if find "$HELPER_STAGE" -name '*.origins.json' -print -quit | rg -q .; then
	printf '%s\n' "helper sidecar unexpectedly entered npm staging" >&2
	exit 1
fi

INVOCATIONS_BEFORE_INVALID="$(wc -l < "$INVOCATIONS")"
INVALID_OUT="$OUTPUT_ROOT/haxe-invalid/tree"
mkdir -p "$INVALID_OUT"
export TS_DIAGNOSTIC_MODE=none
run_haxe_failure haxe-invalid haxe tests/haxe/ts-package-diagnostic-resolution/ts-invalid.hxml \
	-D "ts-output=$INVALID_OUT" -D "package-tsc=$WRAPPER"
bun "$FIXTURE_DIR/assert.ts" haxe "$OUTPUT_ROOT/haxe-invalid.stdout" "$OUTPUT_ROOT/haxe-invalid.stderr"
INVOCATIONS_AFTER_INVALID="$(wc -l < "$INVOCATIONS")"
test "$INVOCATIONS_BEFORE_INVALID" = "$INVOCATIONS_AFTER_INVALID"

printf 'retained attempt: %s\n' "$OUTPUT_ROOT"
