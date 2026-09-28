#!/usr/bin/env bash
# Focused check of exact stage membership. It feeds synthetic status rows
# into the same stage_check function the runner uses and compares the
# findings against the expected findings. It runs no compiler and writes
# only into a temporary directory.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/stage-check.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

printf 'stage\texpected\tobserved\tproducer\n' >"$WORK/status.tsv"
{
	printf 'paired-js-compile-R1\tzero\t0\tpaired-js-compile-R1\n'
	printf 'rustc\tdata\t0\trustc\n'
	printf 'rustc-R1\tdata\t0\trustc-R1\n'
	printf 'rustc-R1\tdata\t1\trustc-R1\n'
} >>"$WORK/status.tsv"

{
	printf 'paired-js-compile-R1\n'
	printf 'rustc-R1\n'
	printf 'rustc-R2\n'
} >"$WORK/expected.txt"

stage_check "$WORK/status.tsv" "$WORK/expected.txt" "$WORK/findings.txt"
status=$?

printf '%s\n' '--- findings'
cat "$WORK/findings.txt"

fail=0
for fragment in 'unexpected stage rustc' 'duplicate stage rustc-R1' 'missing stage rustc-R2'; do
	if ! grep -qF "$fragment" "$WORK/findings.txt"; then
		printf 'MISSING finding: %s\n' "$fragment"
		fail=1
	fi
done
grep -qF 'unexpected stage rustc-R1' "$WORK/findings.txt" && {
	printf 'WRONG finding: prefix matched as unexpected\n'
	fail=1
}
[ "$status" != "0" ] || {
	printf 'WRONG status: defective tables were accepted\n'
	fail=1
}

# Clean table: rows and declaration agree, so no findings and zero status.
printf 'stage\texpected\tobserved\tproducer\n' >"$WORK/clean.tsv"
printf 'rustc-R2\tzero\t0\trustc-R2\n' >>"$WORK/clean.tsv"
printf 'rustc-R2\n' >"$WORK/clean-expected.txt"
stage_check "$WORK/clean.tsv" "$WORK/clean-expected.txt" "$WORK/clean-findings.txt" || fail=1
[ -s "$WORK/clean-findings.txt" ] && {
	printf 'WRONG finding: clean table produced findings\n'
	fail=1
}

if [ "$fail" != "0" ]; then
	printf 'stage membership check FAILED\n'
	exit 1
fi
printf 'stage membership check passed\n'
