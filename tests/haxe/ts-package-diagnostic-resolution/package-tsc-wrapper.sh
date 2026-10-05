#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "-p" || -z "${2:-}" ]]; then
	printf '%s\n' "package-tsc wrapper expected -p <stage>" >&2
	exit 64
fi

stage="$2"
# Defense in depth: the wrapper never resolves tsc through PATH; the runner
# must export an executable explicit path here.
if [[ -z "${TS_DIAGNOSTIC_REAL_TSC:-}" ]]; then
	printf '%s\n' 'TS_DIAGNOSTIC_REAL_TSC is not set: refusing PATH fallback' >&2
	exit 64
fi
if [[ ! -x "$TS_DIAGNOSTIC_REAL_TSC" ]]; then
	printf 'TS_DIAGNOSTIC_REAL_TSC=%s is not executable\n' "$TS_DIAGNOSTIC_REAL_TSC" >&2
	exit 64
fi
printf '%s\n' "$stage" >> "$TS_DIAGNOSTIC_INVOCATIONS"
mode="${TS_DIAGNOSTIC_MODE:-none}"
if [[ "$mode" == "empty-check" || "$mode" == "success-output" ]]; then
	set +e
	"$TS_DIAGNOSTIC_REAL_TSC" -p "$stage" > "$TS_DIAGNOSTIC_TSC_STDOUT" 2> "$TS_DIAGNOSTIC_TSC_STDERR"
	status=$?
	set -e
	stdout_bytes="$(wc -c < "$TS_DIAGNOSTIC_TSC_STDOUT")"
	stderr_bytes="$(wc -c < "$TS_DIAGNOSTIC_TSC_STDERR")"
	printf 'exit=%s stdout-bytes=%s stderr-bytes=%s\n' "$status" "$stdout_bytes" "$stderr_bytes" > "$TS_DIAGNOSTIC_TSC_STATUS"
	if [[ "$mode" == "success-output" ]]; then
		printf "%s\n" "successful tsc stdout marker"
		printf "%s\n" "successful tsc stderr marker" >&2
	fi
	exit "$status"
fi
if [[ "${TS_DIAGNOSTIC_STRESS:-0}" == "1" ]]; then
	head -c 131072 /dev/zero | tr '\0' 'O'
	printf '\n'
	head -c 131072 /dev/zero | tr '\0' 'E' >&2
	printf '\n' >&2
fi
if [[ "$mode" != "none" ]]; then
	bun "$TS_DIAGNOSTIC_MUTATOR" "$stage" "$TS_DIAGNOSTIC_SIDECAR" "$mode"
fi

exec "$TS_DIAGNOSTIC_REAL_TSC" -p "$stage"
