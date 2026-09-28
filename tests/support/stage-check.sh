#!/usr/bin/env bash
# Exact stage membership check shared by the fixture runners.
#
# stage_check <status.tsv> <expected-stages.txt> <findings output>
#
# The status table carries one row per recorded stage, tab separated, with
# the stage id in the first field and a header line named `stage`. The
# expected file carries one stage id per line. The check reports a declared
# stage with no row, a declared stage with more than one row, and a recorded
# stage whose id is not a declared line. Comparison is by whole field or
# whole line, so a prefix such as `rustc` never satisfies `rustc-R1`. The
# function returns nonzero when any of the three findings is present.
#
# The fixture runners source this file and name it in their provenance
# records. It takes explicit path inputs only and reads no caller globals.
# It checks stage identity membership only: it does not establish that
# expected stages were declared independently, that artifacts came from
# successful producers, or that native semantics passed.

stage_check() {
	local status=$1 expected=$2 findings=$3
	: >"$findings"
	local defects=0
	local stage rows

	while IFS= read -r stage; do
		[ -z "$stage" ] && continue
		rows="$(awk -F '\t' -v id="$stage" '$1 == id { n++ } END { print n + 0 }' "$status")"
		if [ "$rows" = "0" ]; then
			printf 'missing stage %s\n' "$stage" >>"$findings"
			defects=$((defects + 1))
		elif [ "$rows" != "1" ]; then
			printf 'duplicate stage %s (%s rows)\n' "$stage" "$rows" >>"$findings"
			defects=$((defects + 1))
		fi
	done <"$expected"

	while IFS="$(printf '\t')" read -r stage rest; do
		[ "$stage" = "stage" ] && continue
		[ -z "$stage" ] && continue
		if ! awk -v id="$stage" '$1 == id { found = 1 } END { exit found ? 0 : 1 }' "$expected"; then
			printf 'unexpected stage %s\n' "$stage" >>"$findings"
			defects=$((defects + 1))
		fi
	done <"$status"

	[ "$defects" = "0" ]
}
