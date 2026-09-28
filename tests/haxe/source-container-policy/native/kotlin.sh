#!/usr/bin/env bash
# Kotlin native stages for one generated tree.
# Usage: kotlin.sh compile <gen dir> | kotlin.sh run <gen dir>.
# The harness file is a separate input written beside the generated tree.
set -euo pipefail
mode=$1
gen=$2
harness="$gen/CallerCasesRun.kt"
cat >"$harness" <<'EOF'
fun main() {
    scp.CallerCases.run()
}
EOF
cd "$gen" || exit 1
case "$mode" in
compile)
	find . -type f -print0 | sort -z | xargs -0 sha256sum >../native-inputs.sha256
	# The emitted runtime/test support module references runtime faces this
	# small fixture does not generate, so the harness compiles the caller
	# module and its harness with the runtime implementation modules only.
	kotlinc "$harness" $(find scp runtime -name '*.kt' -not -path '*runtime/test*') -include-runtime -d run.jar
	;;
run)
	java -cp run.jar CallerCasesRunKt
	;;
*)
	printf 'unknown mode %s\n' "$mode"
	exit 2
	;;
esac
