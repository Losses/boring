#!/usr/bin/env bash
# Dedicated control for tests/support/stage-check.sh.
#
# Exercises the shared stage membership check against synthetic status
# tables: the default membership behavior, the optional strict producer
# success mode, and the pre-existing missing, duplicate, unexpected, and
# prefix diagnostics under strict mode. Exits nonzero on any failure.
#
# Usage: bash tests/support/stage-check-control.sh

set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=stage-check.sh
. "$here/stage-check.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

failures=0

expect_ok() {
	local label=$1 rc=$2 findings=$3
	if [ "$rc" -ne 0 ]; then
		printf 'FAIL %s: expected success, got rc %s\n' "$label" "$rc" 1>&2
		sed 's/^/  finding: /' "$findings" 1>&2
		failures=$((failures + 1))
	elif [ -s "$findings" ]; then
		printf 'FAIL %s: expected no findings\n' "$label" 1>&2
		sed 's/^/  finding: /' "$findings" 1>&2
		failures=$((failures + 1))
	else
		printf 'ok   %s\n' "$label"
	fi
}

expect_defect() {
	local label=$1 rc=$2 findings=$3 needle=$4
	if [ "$rc" -eq 0 ]; then
		printf 'FAIL %s: expected failure, got success\n' "$label" 1>&2
		failures=$((failures + 1))
	elif ! grep -qF -- "$needle" "$findings"; then
		printf 'FAIL %s: finding %q not reported\n' "$label" "$needle" 1>&2
		sed 's/^/  finding: /' "$findings" 1>&2
		failures=$((failures + 1))
	else
		printf 'ok   %s\n' "$label"
	fi
}

# Synthetic table: one successful producer, one failed producer.
printf 'stage\tstatus\ncompile-a\tok\ncompile-b\tfailed\n' >"$tmp/status-mixed.tsv"
printf 'stage\tstatus\ncompile-a\tok\ncompile-b\tok\n' >"$tmp/status-ok.tsv"
printf 'compile-a\ncompile-b\n' >"$tmp/expected.txt"
# Prefix row must never satisfy the full id.
printf 'stage\tstatus\nrustc\tok\n' >"$tmp/status-prefix.tsv"
printf 'rustc\nrustc-R1\n' >"$tmp/expected-prefix.txt"

# Default membership mode ignores the producer status field.
stage_check "$tmp/status-mixed.tsv" "$tmp/expected.txt" "$tmp/findings"
expect_ok "default membership passes a failed producer row" $? "$tmp/findings"

stage_check "$tmp/status-ok.tsv" "$tmp/expected.txt" "$tmp/findings"
expect_ok "default membership passes an all-ok table" $? "$tmp/findings"

# Strict mode reports the failed producer.
stage_check "$tmp/status-mixed.tsv" "$tmp/expected.txt" "$tmp/findings" strict
expect_defect "strict mode reports the failed stage" $? "$tmp/findings" "failed stage compile-b (status failed)"

stage_check "$tmp/status-ok.tsv" "$tmp/expected.txt" "$tmp/findings" strict
expect_ok "strict mode passes an all-ok table" $? "$tmp/findings"

# Strict mode keeps the existing membership diagnostics.
printf 'compile-a\ncompile-b\ncompile-c\n' >"$tmp/expected-missing.txt"
stage_check "$tmp/status-ok.tsv" "$tmp/expected-missing.txt" "$tmp/findings" strict
expect_defect "strict mode keeps the missing-stage diagnostic" $? "$tmp/findings" "missing stage compile-c"

printf 'stage\tstatus\ncompile-a\tok\ncompile-b\tok\ncompile-b\tok\n' >"$tmp/status-dup.tsv"
stage_check "$tmp/status-dup.tsv" "$tmp/expected.txt" "$tmp/findings" strict
expect_defect "strict mode keeps the duplicate-stage diagnostic" $? "$tmp/findings" "duplicate stage compile-b (2 rows)"

printf 'stage\tstatus\ncompile-a\tok\ncompile-b\tok\nstray\tok\n' >"$tmp/status-stray.tsv"
stage_check "$tmp/status-stray.tsv" "$tmp/expected.txt" "$tmp/findings" strict
expect_defect "strict mode keeps the unexpected-stage diagnostic" $? "$tmp/findings" "unexpected stage stray"

stage_check "$tmp/status-prefix.tsv" "$tmp/expected-prefix.txt" "$tmp/findings" strict
expect_defect "prefix row does not satisfy the full stage id" $? "$tmp/findings" "missing stage rustc-R1"

if [ "$failures" -ne 0 ]; then
	printf '%s control failure(s)\n' "$failures" 1>&2
	exit 1
fi
printf 'stage-check control: all cases passed\n'
