#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FIXTURE_DIR="$ROOT_DIR/tests/haxe/ts-package-diagnostic-resolution"
TSC_BIN="${TSC:-tsc}"
mkdir -p "$ROOT_DIR/out/ts-package-diagnostic-resolution"
OUTPUT_ROOT="$(mktemp -d "$ROOT_DIR/out/ts-package-diagnostic-resolution/attempt-XXXXXXXX")"
WRAPPER="$OUTPUT_ROOT/package-tsc-wrapper.sh"
INVOCATIONS="$OUTPUT_ROOT/tsc-invocations.log"
cd "$ROOT_DIR"
INPUTS=(packages/compiler/PackageArtifacts.hx tests/haxe/ts-package-diagnostic-resolution/*)
sha256sum "${INPUTS[@]}" > "$OUTPUT_ROOT/input-hashes-before.txt"
printf 'nix develop -c bash -c "TSC=%s bash tests/haxe/ts-package-diagnostic-resolution/run.sh"\n' "$TSC_BIN" > "$OUTPUT_ROOT/command.txt"
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
