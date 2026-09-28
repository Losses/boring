#!/usr/bin/env bash
# Failure injection wrapper for the durable runner.
#
# It exports a sha256sum function that fails for the path fragment named in
# PLACE_TEST_HASH_FAIL and then runs the runner unchanged. The runner carries
# no injection switch of its own, so the gates are exercised from outside.
# The wrapper changes no fixture source and no generated artifact.
set -u
: "${PLACE_TEST_HASH_FAIL:?PLACE_TEST_HASH_FAIL must name the path fragment that fails}"

sha256sum() {
	case "$*" in
	*"$PLACE_TEST_HASH_FAIL"*)
		printf 'injected hash failure for: %s\n' "$*" >&2
		return 3
		;;
	*)
		command sha256sum "$@"
		;;
	esac
}
export -f sha256sum
export PLACE_TEST_HASH_FAIL

exec bash "$(cd "$(dirname "$0")" && pwd)/../run.sh"
