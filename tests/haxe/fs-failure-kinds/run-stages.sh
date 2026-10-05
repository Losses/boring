#!/usr/bin/env bash
# Stage runner for the fs-failure-kinds fixture (std.Fs failure identity,
# docs/specs/stdlib/17 / 03). Usage: EV=<evidence dir> bash \
#   tests/haxe/fs-failure-kinds/run-stages.sh <target...>
# Targets: ts kotlin dart swift. Each stage records argv, separated streams,
# and exit status under $EV/stages/<stage>/. Run inside nix develop.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="${FIXTURE_WORKTREE_ROOT:-$(cd "$HERE/../../.." && pwd)}"
if [ ! -f "$ROOT/flake.nix" ] || [ ! -f "$ROOT/tests/haxe/fs-failure-kinds/expected.txt" ]; then
	printf 'run-stages: worktree root misresolved: %s\n' "$ROOT" >&2
	exit 2
fi
EV="${EV:?EV must point at the evidence directory}"
cd "$ROOT"
STAGES="$EV/stages"
mkdir -p "$STAGES"
TAB="$(printf '\t')"

record() {
	printf '%s%s%s%s%s\n' "$1" "$TAB" "$TAB$2" "$TAB" "$3" >>"$EV/status.tsv"
	printf '%s observed=%s\n' "$1" "$2"
}

stage() {
	local name=$1 expected=$2
	shift 2
	local dir="$STAGES/$name"
	mkdir -p "$dir"
	{ printf 'cwd %s\nargv' "$ROOT"; printf ' %q' "$@"; printf '\n'; } >"$dir/argv"
	"$@" >"$dir/stdout" 2>"$dir/stderr"
	local observed=$?
	printf '%s\n' "$observed" >"$dir/status"
	record "$name" "$observed" "$expected"
	return "$observed"
}

not_reached() {
	local producer=$1 observed=$2
	shift 2
	for name in "$@"; do record "$name" "producer-$producer-status-$observed" "not-reached"; done
}

targets="${*:-ts kotlin dart}"
for target in $targets; do
	GEN="out/fs-failure-kinds/gen/$target"
	case "$target" in
	ts)
		stage gen-ts data haxe tests/haxe/fs-failure-kinds/gen/ts.hxml \
			-D ts-output="$GEN" -D ts-test-output="$GEN-tests"
		[ $? != 0 ] && { not_reached gen-ts $? build-ts run-ts compare-ts; continue; }
		stage build-ts data bash -c "cd $GEN && cp \"$HERE/native/main.js\" fsfail-run.js && sha256sum fsfail-run.js >harness.sha256 && timeout 300 bun build fsfail-run.js --target node --outfile=run-bundle.js"
		[ $? != 0 ] && { not_reached build-ts $? run-ts compare-ts; continue; }
		stage run-ts zero bash -c "cd $GEN && timeout 120 bun run-bundle.js"
		[ $? != 0 ] && { not_reached run-ts $? compare-ts; continue; }
		;;
	kotlin)
		stage gen-kotlin data haxe tests/haxe/fs-failure-kinds/gen/kotlin.hxml \
			-D kotlin-output="$GEN" -D kotlin-test-output="$GEN-tests"
		[ $? != 0 ] && { not_reached gen-kotlin $? compile-kotlin run-kotlin compare-kotlin; continue; }
		stage compile-kotlin data bash -c "cd $GEN && cp \"$HERE/native/Main.kt\" FsFailRun.kt && sha256sum FsFailRun.kt >harness.sha256 && timeout 1800 kotlinc FsFailRun.kt \$(find fsfail runtime std -name '*.kt' -not -path '*runtime/test*') -include-runtime -d run.jar"
		[ $? != 0 ] && { not_reached compile-kotlin $? run-kotlin compare-kotlin; continue; }
		stage run-kotlin zero bash -c "timeout 300 java -cp $GEN/run.jar FsFailRunKt"
		[ $? != 0 ] && { not_reached run-kotlin $? compare-kotlin; continue; }
		;;
	dart)
		stage gen-dart data haxe tests/haxe/fs-failure-kinds/gen/dart.hxml \
			-D dart-output="$GEN" -D dart-test-output="$GEN-tests"
		[ $? != 0 ] && { not_reached gen-dart $? dart-pub-get run-dart compare-dart; continue; }
		stage dart-pub-get zero bash -c "cd $GEN && timeout 300 dart pub get"
		[ $? != 0 ] && { not_reached dart-pub-get $? run-dart compare-dart; continue; }
		stage run-dart zero bash -c "cd $GEN && cp \"$HERE/native/main.dart\" lib/fsfail/zz_run.dart && sha256sum lib/fsfail/zz_run.dart >harness.sha256 && timeout 600 dart run lib/fsfail/zz_run.dart"
		[ $? != 0 ] && { not_reached run-dart $? compare-dart; continue; }
		;;
	swift)
		stage gen-swift data haxe tests/haxe/fs-failure-kinds/gen/swift.hxml \
			-D swift-output="$GEN" -D swift-test-output="$GEN-tests"
		[ $? != 0 ] && { not_reached gen-swift $? compare-swift; continue; }
		;;
	esac
	mkdir -p "$STAGES/compare-$target"
	diff -u tests/haxe/fs-failure-kinds/expected.txt "$STAGES/run-$target/stdout" >"$STAGES/compare-$target/stdout" 2>"$STAGES/compare-$target/stderr"
	record "compare-$target" $? "0-identical-nonzero-differs"
done
