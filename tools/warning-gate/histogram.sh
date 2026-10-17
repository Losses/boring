#!/usr/bin/env bash
# Warning-count histogram tool.
#
# Prints the per-target warning histogram (measured count, frozen baseline,
# adjudication status, registered residual label) and the tier-1 verdict only.
# It exports HISTOGRAM_ONLY=1 so check.sh judges tier 1 (count vs baseline) and
# exits on FAIL_COUNT alone - a target whose compiler failed on rc still prints
# its measured count here instead of dragging a red build into the histogram
# read. The compile-rc (tier 2) and downstream tiers are deliberately out of
# scope for this read-only histogram.
set -u
HISTOGRAM_ONLY=1
export HISTOGRAM_ONLY
exec bash "$(cd "$(dirname "$0")" && pwd)/check.sh" "$@"
