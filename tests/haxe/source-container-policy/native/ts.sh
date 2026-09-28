#!/usr/bin/env bash
# TypeScript native stages for one generated tree.
# Usage: ts.sh compile <gen dir> | ts.sh run <gen dir>.
# The harness file is a separate input written beside the generated tree; it
# implements no source operation.
set -euo pipefail
mode=$1
gen=$2
harness="$gen/caller-cases-run.js"
cat >"$harness" <<'EOF'
import { CallerCases } from "./scp/CallerCases.js";
CallerCases.run();
EOF
cd "$gen" || exit 1
case "$mode" in
compile)
	find . -type f -print0 | sort -z | xargs -0 sha256sum >../native-inputs.sha256
	bun build "$harness" --outfile=run-bundle.js
	;;
run)
	bun run-bundle.js
	;;
*)
	printf 'unknown mode %s\n' "$mode"
	exit 2
	;;
esac
