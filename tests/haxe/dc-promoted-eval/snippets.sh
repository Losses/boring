#!/usr/bin/env bash
# Extracts, for one run directory, the region of each target's generated module
# that carries the promoted switch: the digest of the module, and the lines that
# bind the synthetic local and switch over it. This is the raw text the runtime
# observation is about; the digests let a reader tie the text to the compiled
# artifact the target compiler was given.
set -u

RUN="${1:-}"
if [ -z "$RUN" ] || [ ! -d "$RUN" ]; then
	printf 'usage: snippets.sh <run-directory>\n' >&2
	exit 2
fi
mkdir -p "$RUN/snippets" || exit 2

for t in ts kotlin dart rust swift; do
	out="$RUN/snippets/$t.txt"
	{
		printf '# target %s\n' "$t"
		printf '# generated tree %s\n' "$RUN/$t-gen"
	} >"$out"
	case "$t" in
	ts)
		mod="$RUN/ts-gen/dcpe/EvalProbe.ts"
		pattern='_g|switch|case '
		;;
	kotlin)
		mod="$RUN/kotlin-gen/dcpe/EvalProbe.kt"
		pattern='_g|when|is Kind'
		;;
	dart)
		mod="$RUN/dart-gen/lib/dcpe/eval_probe.dart"
		pattern='_g|switch|case '
		;;
	rust)
		mod="$RUN/rust-gen/dcpe/eval_probe.rs"
		pattern='_g|match|Kind::'
		;;
	swift)
		mod="$RUN/swift-gen/dcpe/EvalProbe.swift"
		pattern='_g|switch|case '
		;;
	esac
	if [ -f "$mod" ]; then
		sha256sum "$mod" >>"$out"
		printf '# --- subject region of %s ---\n' "$mod" >>"$out"
		grep -nE "$pattern" "$mod" >>"$out" 2>/dev/null || true
	else
		printf '# generated module missing: %s\n' "$mod" >>"$out"
	fi
done
printf 'wrote one subject snippet per target under %s/snippets\n' "$RUN"
