#!/usr/bin/env bash
# Rust native stages for one generated tree.
# Usage: rust.sh compile <gen dir> | rust.sh run <gen dir>.
# The harness is a separate binary target written beside the generated lib;
# it calls the generated entry and implements no source operation.
set -euo pipefail
mode=$1
gen=$2
mkdir -p "$gen/src"
cat >"$gen/src/main.rs" <<'EOF'
fn main() {
    generated::scp::caller_cases::CallerCases::caller_cases_run();
}
EOF
cd "$gen" || exit 1
case "$mode" in
compile)
	find . -type f -print0 | sort -z | xargs -0 sha256sum >../native-inputs.sha256
	cargo build --offline
	;;
run)
	./target/debug/generated
	;;
*)
	printf 'unknown mode %s\n' "$mode"
	exit 2
	;;
esac
