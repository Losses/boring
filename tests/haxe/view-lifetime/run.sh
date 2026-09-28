#!/usr/bin/env bash
# Reproducible runner of the view-lifetime fixture.
#
# One fresh attempt directory per run under out/view-lifetime/runs.
# Child stages are captured through the existing EvidenceProbe via the thin
# typed orchestrator (run.ts); stage membership is checked with the shared
# tests/support/stage-check.sh. Both the Haxe JS/Bun oracle and the native
# Swift run are compared against independently authored expected values.
# Every failure is preserved unchanged in the attempt directory.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
SHARED_CHECK="$HERE/../../support/stage-check.sh"
cd "$ROOT" || exit 1

# Responsibility boundary: resolve the shared checker and verify the root
# markers before any Haxe invocation.
[ -f "$SHARED_CHECK" ] || { printf 'runner-defect: shared stage check missing: %s\n' "$SHARED_CHECK"; exit 2; }
[ -f "$ROOT/AGENT.md" ] || { printf 'runner-defect: AGENT.md missing at %s\n' "$ROOT"; exit 2; }
[ -f "$ROOT/tools/bundle/ChildEvidence.hx" ] || { printf 'runner-defect: ChildEvidence.hx missing at %s\n' "$ROOT"; exit 2; }
[ -f "$HERE/run.ts" ] || { printf 'runner-defect: orchestrator missing: %s\n' "$HERE/run.ts"; exit 2; }
# shellcheck source=../../support/stage-check.sh
. "$SHARED_CHECK"

OUT_ROOT="$ROOT/out/view-lifetime"
mkdir -p "$OUT_ROOT/runs" || exit 2
RUN="$(mktemp -d "$OUT_ROOT/runs/view-XXXXXXXX")" || { printf 'runner-defect: attempt directory allocation failed\n'; exit 2; }
GEN="$RUN/gen"
ORACLE_JS="$RUN/oracle/oracle.js"
PROBE_JS="$RUN/probe/evidence-probe.js"
BINARY="$RUN/view-lifetime-check"
STATUS="$RUN/status.tsv"
EXPECTED="$RUN/expected-stages.txt"
mkdir -p "$RUN/identity" "$RUN/bootstrap" "$RUN/compare" "$RUN/checks" "$RUN/stages"

printf 'stage\tstatus\tproducer\n' >"$STATUS"
printf '%s\n' \
	bootstrap-probe \
	haxe-oracle-compile \
	haxe-oracle-run \
	swift-gen \
	swift-compile \
	swift-run \
	compare >"$EXPECTED"

REASONS=""
record_status() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >>"$STATUS"; }
add_reason() { if [ -z "$REASONS" ]; then REASONS="$1"; else REASONS="$REASONS,$1"; fi; }

identity_step() {
	local label="$1"; shift
	printf '%s\n' "$@" >"$RUN/identity/$label.argv"
	"$@" >"$RUN/identity/$label.stdout" 2>"$RUN/identity/$label.stderr"
	local st=$?
	printf '%s\n' "$st" >"$RUN/identity/$label.status"
	if [ "$st" -ne 0 ]; then
		add_reason "identity-$label"
	fi
}
identity_step haxe-path command -v haxe
identity_step bun-path command -v bun
identity_step swiftc-path command -v swiftc
identity_step haxelib-path command -v haxelib
identity_step haxe-version haxe --version
identity_step bun-version bun --version
identity_step swiftc-version swiftc --version
identity_step haxelib-boring haxelib path boring
identity_step git-head git rev-parse HEAD
identity_step git-status git status --porcelain
# After the Nix shell hook, the resolved boring library must point to this
# assigned checkout. The haxelib output can begin with a blank line, so the
# compiler path is identified as the first non-blank line and compared
# exactly. The raw haxelib output and this check are retained in the attempt
# for inspection; the cwd and the HEAD alone do not state the loaded
# compiler.
HXLIB_FIRST=$(grep -m1 . "$RUN/identity/haxelib-boring.stdout")
if [ "$HXLIB_FIRST" = "$ROOT/packages/compiler/" ]; then
	printf '0\n' >"$RUN/checks/haxelib-checkout"
else
	printf '%s\n' "$HXLIB_FIRST" >"$RUN/checks/haxelib-checkout"
	add_reason haxelib-checkout
fi

# Actual compiler inputs and fixture/probe inputs, hashed before the attempt.
# The manifest covers the code actually used: the compiler tree, the std
# inputs, the fixture, the probe and its ChildEvidence owner, the shared
# checker, and the project identity file the probe hashes.
input_manifest() {
	find packages/compiler samples/std tools/bundle tests/haxe/view-lifetime \
		tests/bundle-child-evidence/probe tests/support boring.json \
		-type f | LC_ALL=C sort | xargs -d '\n' sha256sum
}
input_manifest >"$RUN/inputs-before.sha256" 2>"$RUN/inputs-before.stderr"
INPUTS_BEFORE=$?
[ "$INPUTS_BEFORE" -eq 0 ] || add_reason "input-manifest-before"

# Bootstrap the existing probe with exactly one attempt-local JS output target.
mkdir -p "$RUN/probe"
sed 's|^-js .*|-js '"$PROBE_JS"'|' tests/bundle-child-evidence/probe/probe.hxml >"$RUN/probe/probe-attempt.hxml"
grep -qF -e "-js $PROBE_JS" "$RUN/probe/probe-attempt.hxml" || { printf 'runner-defect: probe bootstrap hxml did not take the attempt-local -js target\n'; exit 2; }
printf 'haxe %s\n' "$RUN/probe/probe-attempt.hxml" >"$RUN/bootstrap/argv"
haxe "$RUN/probe/probe-attempt.hxml" >"$RUN/bootstrap/stdout" 2>"$RUN/bootstrap/stderr"
BOOTSTRAP_STATUS=$?
printf '%s\n' "$BOOTSTRAP_STATUS" >"$RUN/bootstrap/status"
if [ "$BOOTSTRAP_STATUS" -eq 0 ]; then
	record_status bootstrap-probe zero runner
else
	record_status bootstrap-probe "failure($BOOTSTRAP_STATUS)" runner
	add_reason bootstrap-probe
fi

run_stage() { # <stage-id> <cmd> [args...]
	local id="$1" cmd="$2"; shift 2
	bun "$HERE/run.ts" "$PROBE_JS" "$RUN" "$id" "$cmd" "$@" \
		>"$RUN/stages/$id/orchestrator.stdout" 2>"$RUN/stages/$id/orchestrator.stderr"
}
mkdir -p "$RUN/stages/haxe-oracle-compile" "$RUN/stages/haxe-oracle-run" \
	"$RUN/stages/swift-gen" "$RUN/stages/swift-compile" "$RUN/stages/swift-run" "$RUN/stages/compare"

if [ "$BOOTSTRAP_STATUS" -ne 0 ]; then
	for skipped in haxe-oracle-compile haxe-oracle-run swift-gen swift-compile swift-run compare; do
		record_status "$skipped" "not-reached(bootstrap-probe)" runner
	done
else
	# Haxe oracle: fresh JS generation, then a captured Bun execution.
	if run_stage haxe-oracle-compile haxe tests/haxe/view-lifetime/oracle.hxml -js "$ORACLE_JS"; then
		record_status haxe-oracle-compile zero haxe
	else
		record_status haxe-oracle-compile failure haxe
		add_reason haxe-oracle-compile
	fi
	ORACLE_COMPILE_STATUS=$(awk -F '\t' '$1 == "haxe-oracle-compile" { print $2 }' "$STATUS" | tail -1)
	if [ "$ORACLE_COMPILE_STATUS" = "zero" ]; then
		if run_stage haxe-oracle-run bun "$ORACLE_JS"; then
			record_status haxe-oracle-run zero bun
		else
			record_status haxe-oracle-run failure bun
			add_reason haxe-oracle-run
		fi
		ORACLE_RUN_STATUS=$(awk -F '\t' '$1 == "haxe-oracle-run" { print $2 }' "$STATUS" | tail -1)
	else
		record_status haxe-oracle-run "not-reached(haxe-oracle-compile)" runner
		ORACLE_RUN_STATUS="not-reached(haxe-oracle-compile)"
	fi

	# Swift: fresh generation, native compilation, native execution.
	if run_stage swift-gen haxe tests/haxe/view-lifetime/swift.hxml -D "swift-output=$GEN"; then
		record_status swift-gen zero haxe
	else
		record_status swift-gen failure haxe
		add_reason swift-gen
	fi
	SWIFT_GEN_STATUS=$(awk -F '\t' '$1 == "swift-gen" { print $2 }' "$STATUS" | tail -1)
	if [ "$SWIFT_GEN_STATUS" = "zero" ]; then
		# Runtime declaration closure of the ordinary generated files.
		if [ -f "$GEN/Runtime.swift" ]; then
			TIQIAN_COUNT=$(rg -c '^public final class TiqianArray<' "$GEN/Runtime.swift" || printf '0')
			ROARRAY_COUNT=$(rg -c '^public final class ReadOnlyArray<' "$GEN/Runtime.swift" || printf '0')
			printf '%s\n%s\n' "$TIQIAN_COUNT" "$ROARRAY_COUNT" >"$RUN/checks/runtime-declaration-counts"
			[ "$TIQIAN_COUNT" = "1" ] && [ "$ROARRAY_COUNT" = "1" ] || add_reason runtime-declaration
		else
			printf '0\n0\n' >"$RUN/checks/runtime-declaration-counts"
			add_reason runtime-declaration
		fi
		if [ ! -e "$GEN/Test.swift" ]; then
			printf '0\n' >"$RUN/checks/test-host-absent"
		else
			printf '1\n' >"$RUN/checks/test-host-absent"
			add_reason test-host-present
		fi
		find "$GEN" -name '*.swift' | LC_ALL=C sort >"$RUN/stages/swift-compile/generated-files.txt"
		mapfile -t GEN_FILES <"$RUN/stages/swift-compile/generated-files.txt"
		if [ "${#GEN_FILES[@]}" -gt 0 ]; then
			if run_stage swift-compile swiftc "${GEN_FILES[@]}" "$HERE/native-main.swift" -o "$BINARY"; then
				record_status swift-compile zero swiftc
			else
				record_status swift-compile failure swiftc
				add_reason swift-compile
			fi
			SWIFT_COMPILE_STATUS=$(awk -F '\t' '$1 == "swift-compile" { print $2 }' "$STATUS" | tail -1)
		else
			record_status swift-compile "not-reached(swift-gen-no-output)" runner
			SWIFT_COMPILE_STATUS="not-reached(swift-gen-no-output)"
			add_reason swift-compile
		fi
		if [ "$SWIFT_COMPILE_STATUS" = "zero" ]; then
			if run_stage swift-run "$BINARY"; then
				record_status swift-run zero "$BINARY"
			else
				record_status swift-run failure "$BINARY"
				add_reason swift-run
			fi
			SWIFT_RUN_STATUS=$(awk -F '\t' '$1 == "swift-run" { print $2 }' "$STATUS" | tail -1)
		else
			record_status swift-run "not-reached(swift-compile)" runner
			SWIFT_RUN_STATUS="not-reached(swift-compile)"
		fi
	else
		record_status swift-compile "not-reached(swift-gen)" runner
		record_status swift-run "not-reached(swift-compile)" runner
		SWIFT_COMPILE_STATUS="not-reached(swift-gen)"
		SWIFT_RUN_STATUS="not-reached(swift-compile)"
		add_reason swift-compile
	fi

	# Compare both hosts' complete raw stdout directly against the
	# independently authored expected lines. Both real producers emit clean
	# labeled lines (typed Console.log and Swift print); the raw outputs are
	# preserved unchanged and no normalization is applied.
	printf '%s\n' "rebind=123" "escaped=56" "local-mutation=42" "combined=123" "boundary=564:1494" >"$RUN/compare/expected.txt"
	if [ "$ORACLE_RUN_STATUS" = "zero" ] && [ "$SWIFT_RUN_STATUS" = "zero" ]; then
		cp "$RUN/stages/haxe-oracle-run/child-stdout.txt" "$RUN/compare/oracle-raw.txt"
		cp "$RUN/stages/swift-run/child-stdout.txt" "$RUN/compare/swift-raw.txt"
		diff -u "$RUN/compare/expected.txt" "$RUN/compare/oracle-raw.txt" >"$RUN/compare/oracle-diff.txt"
		ORACLE_DIFF=$?
		diff -u "$RUN/compare/expected.txt" "$RUN/compare/swift-raw.txt" >"$RUN/compare/swift-diff.txt"
		SWIFT_DIFF=$?
		if [ "$ORACLE_DIFF" -eq 0 ] && [ "$SWIFT_DIFF" -eq 0 ]; then
			record_status compare zero runner
			printf 'match\n' >"$RUN/compare/compare-status"
		else
			record_status compare failure runner
			add_reason compare
			printf 'mismatch oracle-diff=%s swift-diff=%s\n' "$ORACLE_DIFF" "$SWIFT_DIFF" >"$RUN/compare/compare-status"
		fi
	else
		record_status compare "not-reached(haxe-oracle-run,swift-run)" runner
		printf 'not-reached\n' >"$RUN/compare/compare-status"
	fi
fi

# Input integrity after the attempt.
input_manifest >"$RUN/inputs-after.sha256" 2>"$RUN/inputs-after.stderr"
if [ "$INPUTS_BEFORE" -eq 0 ] && cmp -s "$RUN/inputs-before.sha256" "$RUN/inputs-after.sha256"; then
	printf 'unchanged\n' >"$RUN/inputs-status"
else
	printf 'changed\n' >"$RUN/inputs-status"
	add_reason inputs-changed
fi

# Stage membership (identity only; it does not establish successful exits).
stage_check "$STATUS" "$EXPECTED" "$RUN/membership-findings.txt"
MEMBERSHIP_STATUS=$?
printf '%s\n' "$MEMBERSHIP_STATUS" >"$RUN/membership-status"
if [ "$MEMBERSHIP_STATUS" -ne 0 ]; then
	add_reason membership-defect
fi

if [ -z "$REASONS" ]; then
	VERDICT=success
else
	VERDICT="failed($REASONS)"
fi
printf 'attempt: %s\n' "$RUN"
printf 'verdict: %s\n' "$VERDICT"
[ "$VERDICT" = "success" ]
