#!/usr/bin/env bash
# Dart native stages for one generated tree.
# Usage: dart.sh compile <gen dir> | dart.sh run <gen dir>.
# The harness file is a separate input written inside the package library so
# the generated relative imports keep resolving.
set -euo pipefail
mode=$1
gen=$2
harness="$gen/lib/scp/zz_run.dart"
cat >"$harness" <<'EOF'
import "caller_cases.dart" as caller_cases;

void main() {
  caller_cases.run();
}
EOF
cd "$gen" || exit 1
case "$mode" in
compile)
	find . -type f -print0 | sort -z | xargs -0 sha256sum >../native-inputs.sha256
	dart pub get
	dart compile exe "$harness" -o run.exe
	;;
run)
	./run.exe
	;;
*)
	printf 'unknown mode %s\n' "$mode"
	exit 2
	;;
esac
