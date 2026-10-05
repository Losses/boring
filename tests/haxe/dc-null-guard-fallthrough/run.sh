#!/usr/bin/env bash
# Observation runner for the dc-null-guard-fallthrough probe.
# Dart: gen, dart analyze, dart compile exe, run, compare.
# Kotlin: gen only (join-fact emit contrast). Every stage writes argv,
# separated stdout/stderr and a numeric exit status into one attempt
# directory under dc-warn/out/dart-fix2/<attempt-id>/ (never rewritten).
#
# Invoked as: nix develop -c bash tests/haxe/dc-null-guard-fallthrough/run.sh (dart-fix2 tree)
# (the fuse mount drops the executable bit; always call via `bash`).
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
WS="$(cd "$ROOT/../../.." && pwd)"   # .../tq-workspace
# Evidence lands outside the worktree. Default is the workspace dc-warn layout
# this probe was authored in, but any checkout must be able to redirect it:
# set DC_DART_FIX2_EVIDENCE to a writable directory that exists (or whose
# parent exists) or the run stops here instead of writing into a path that
# may not be there.
EV_PARENT="${DC_DART_FIX2_EVIDENCE:-$WS/dc-warn/out/dart-fix2}"
if [ ! -d "$EV_PARENT" ]; then
	if ! mkdir -p "$EV_PARENT" 2>/dev/null; then
		printf 'evidence parent %s is not writable; set DC_DART_FIX2_EVIDENCE=<writable dir>\n' "$EV_PARENT"
		exit 1
	fi
fi
if [ ! -f "$ROOT/AGENT.md" ]; then
	printf 'AGENT.md absent at %s; wrong worktree\n' "$ROOT"
	exit 1
fi
if [ "${IN_NIX_SHELL:-}" = "" ]; then
	printf 'run through: nix develop -c bash tests/haxe/dc-null-guard-fallthrough/run.sh (dart-fix2 tree)\n'
	exit 1
fi

ATTEMPT="${DC_DART_FIX2_ATTEMPT:-probe-$(date -u +%Y%m%dT%H%M%SZ)}"
RUN="$EV_PARENT/$ATTEMPT"
if [ -e "$RUN" ]; then
	printf 'attempt directory %s already exists; refusing to overwrite\n' "$RUN"
	exit 1
fi
mkdir -p "$RUN/stages" || exit 1
printf 'cwd %s\nattempt %s\n' "$ROOT" "$ATTEMPT" >"$RUN/meta.txt"

stage() {
	local name=$1; shift
	local dir="$RUN/stages/$name"
	mkdir -p "$dir"
	{
		printf 'cwd %s\nargv' "$ROOT"
		printf ' %q' "$@"
		printf '\n'
	} >"$dir/argv"
	"$@" >"$dir/stdout" 2>"$dir/stderr"
	local st=$?
	printf '%s\n' "$st" >"$dir/status"
	printf '%s\t%s\n' "$name" "$st" >>"$RUN/stages.tsv"
	printf 'stage %-26s exit=%s\n' "$name" "$st"
	return $st
}

INPUTS=(
	"$ROOT/packages/compiler/reflaxe/dart/dartcompiler/DartExpr.hx"
	"$HERE/run.sh" "$HERE/expected.txt"
	"$HERE/gen/dart.hxml" "$HERE/gen/kotlin.hxml"
	"$HERE/dcguard/DcGuard.hx" "$HERE/native/main.dart"
)

# --- identity + input hashes (before)
# The identity capture shells out to git. A collected regression test must not
# depend on native VCS (the board owns version control), so
# DC_DART_FIX2_SKIP_VCS=1 records the identity step as skipped instead of
# running git; the default (unset) keeps the observation runner's behaviour.
if [ "${DC_DART_FIX2_SKIP_VCS:-}" = "" ]; then
	{ git -C "$ROOT" rev-parse HEAD; git -C "$ROOT" status --porcelain; } >"$RUN/identity.txt" 2>&1
else
	printf 'vcs-identity skipped (DC_DART_FIX2_SKIP_VCS set)\n' >"$RUN/identity.txt"
fi
sha256sum "${INPUTS[@]}" >"$RUN/input-hashes-before.txt" 2>"$RUN/input-hashes-before.err"

# --- Haxe generation, Dart
stage gen-dart timeout 900 haxe tests/haxe/dc-null-guard-fallthrough/gen/dart.hxml \
	-D dart-output="$RUN/gen-dart" \
	-D dart-test-output="$RUN/gen-dart-tests"
if [ -d "$RUN/gen-dart" ]; then
	(find "$RUN/gen-dart" -type f -print0 | sort -z | xargs -0 sha256sum) >"$RUN/gen-dart.sha256" 2>/dev/null
	cp "$RUN/gen-dart/lib/dcguard/dc_guard.dart" "$RUN/generated-dart-probe.dart" 2>/dev/null
	# key emit observation: does s.length carry a non-null assertion?
	grep -n 'length\|!' "$RUN/generated-dart-probe.dart" >"$RUN/generated-dart-probe.grep" 2>&1
fi

# --- dart analyze / compile / run
if [ -f "$RUN/generated-dart-probe.dart" ]; then
	mkdir -p "$RUN/gen-dart/lib/dcguard"
	cp "$HERE/native/main.dart" "$RUN/gen-dart/lib/dcguard/zz_run.dart"
	sha256sum "$RUN/gen-dart/lib/dcguard/zz_run.dart" >"$RUN/harness.sha256"
	cd "$RUN/gen-dart" || exit 1
	stage dart-analyze timeout 900 dart analyze --fatal-infos .
	stage dart-compile timeout 1800 dart compile exe lib/dcguard/zz_run.dart -o run.exe
	if [ -f "$RUN/gen-dart/lib/dcguard/zz_run.dart" ]; then
		# fuse mount drops the executable bit; run JIT instead of the AOT exe
		stage dart-run timeout 300 dart lib/dcguard/zz_run.dart
		stage dart-compare diff -u "$HERE/expected.txt" "$RUN/stages/dart-run/stdout"
	else
		printf 'dart-run\tnot-reached (compile failed)\n' >>"$RUN/stages.tsv"
		printf 'dart-compare\tnot-reached (compile failed)\n' >>"$RUN/stages.tsv"
	fi
	# corrected variant: hand-insert the missing non-null assertion, then
	# compile+run to show the corrected emit satisfies analyzer and runtime.
	rm -rf "$RUN/gen-dart-corrected"
	cp -r "$RUN/gen-dart" "$RUN/gen-dart-corrected"
	sed 's/return s.length;/return s!.length;/' "$RUN/gen-dart/lib/dcguard/dc_guard.dart" \
		>"$RUN/gen-dart-corrected/lib/dcguard/dc_guard.dart"
	cd "$RUN/gen-dart-corrected" || exit 1
	stage dart-analyze-corrected timeout 900 dart analyze --fatal-infos .
	stage dart-compile-corrected timeout 1800 dart compile exe lib/dcguard/zz_run.dart -o run.exe
	if [ -x "$RUN/gen-dart-corrected/run.exe" ]; then
		# fuse mount drops the executable bit; run JIT instead of the AOT exe
		stage dart-run-corrected timeout 300 dart lib/dcguard/zz_run.dart
		stage dart-compare-corrected diff -u "$HERE/expected.txt" "$RUN/stages/dart-run-corrected/stdout"
	fi
	cd "$ROOT"
else
	printf 'dart-analyze\tnot-reached (gen failed)\n' >>"$RUN/stages.tsv"
	printf 'dart-compile\tnot-reached (gen failed)\n' >>"$RUN/stages.tsv"
	printf 'dart-run\tnot-reached (gen failed)\n' >>"$RUN/stages.tsv"
	printf 'dart-compare\tnot-reached (gen failed)\n' >>"$RUN/stages.tsv"
fi

# --- Haxe generation, Kotlin (join-fact contrast)
stage gen-kotlin timeout 900 haxe tests/haxe/dc-null-guard-fallthrough/gen/kotlin.hxml \
	-D kotlin-output="$RUN/gen-kotlin"
if [ -d "$RUN/gen-kotlin" ]; then
	(find "$RUN/gen-kotlin" -type f -print0 | sort -z | xargs -0 sha256sum) >"$RUN/gen-kotlin.sha256" 2>/dev/null
	cp "$RUN/gen-kotlin/dcguard/DcGuard.kt" "$RUN/generated-kotlin-probe.kt" 2>/dev/null
	grep -n '!!\|\.length' "$RUN/generated-kotlin-probe.kt" >"$RUN/generated-kotlin-probe.grep" 2>&1
fi

# --- input hashes (after)
sha256sum "${INPUTS[@]}" >"$RUN/input-hashes-after.txt" 2>"$RUN/input-hashes-after.err"
if cmp -s "$RUN/input-hashes-before.txt" "$RUN/input-hashes-after.txt"; then
	printf 'input-hashes\tidentical\n' >>"$RUN/stages.tsv"
else
	printf 'input-hashes\tCHANGED\n' >>"$RUN/stages.tsv"
fi
printf 'attempt directory: %s\n' "$RUN"
exit 0
