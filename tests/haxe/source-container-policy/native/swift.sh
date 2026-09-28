#!/usr/bin/env bash
# Swift native stages for one generated tree.
# Usage: swift.sh compile <gen dir> | swift.sh run <gen dir>.
# The harness file is a separate input written beside the generated tree;
# main.swift carries the top-level entry the executable needs.
set -euo pipefail
mode=$1
gen=$2
cat >"$gen/main.swift" <<'EOF'
CallerCases.run()
EOF
cd "$gen" || exit 1
case "$mode" in
compile)
	find . -type f -print0 | sort -z | xargs -0 sha256sum >../native-inputs.sha256
	swiftc -o run-bin Runtime.swift $(find std scp -name '*.swift') main.swift
	;;
run)
	./run-bin
	;;
*)
	printf 'unknown mode %s\n' "$mode"
	exit 2
	;;
esac
