#!/usr/bin/env bash
# In-repo regression controls for the shared recording layer.
#
# Single command:
#   bash tests/support/runner-record-controls.sh
#
# The script resolves the library through a relative path, writes only under an
# exclusive temporary directory, and exits non-zero when any assertion fails.
# It reads no archived evidence and needs only bash, coreutils and python3.
# Set RUNNER_RECORD_LIB to point at another copy of the library for mutation
# checks; the default is the committed relative path.
set -u

for tool in mktemp python3 cmp tr grep sed chmod cp mkdir rm dirname; do
	command -v "$tool" >/dev/null 2>&1 || { printf 'missing required tool: %s\n' "$tool" >&2; exit 2; }
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" || exit 2
LIB="${RUNNER_RECORD_LIB:-$ROOT/tools/runner-record/runner-record.sh}"
[ -f "$LIB" ] || { printf 'missing library: %s\n' "$LIB" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/runner-record-controls.XXXXXXXX")" || exit 2
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT

# shellcheck source=../../tools/runner-record/runner-record.sh
. "$LIB" || { printf 'cannot source %s\n' "$LIB" >&2; exit 2; }

PASS=0
FAIL=0
ok() { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1" >&2; }
eq() { if [ "$2" = "$3" ]; then ok "$1 ($4=$3)"; else bad "$1 (expected $4=$2, actual $3)"; fi; }
inlist() { case "|$2|" in *"|$3|"*) ok "$1 ($4=$3)";; *) bad "$1 (expected $4 in [$2], actual $3)";; esac; }
field() { tr -d '\n' < "$RR_CMD/$1" 2>/dev/null; }

printf 'runner-record controls\n'

# 1. Raw exit codes, outcome labels, byte-exact streams and argv round-trip.
rr_init semantics "$TMP" || { printf 'rr_init failed\n' >&2; exit 2; }
rr_record_cmd exit0 -- bash -c 'printf "out\n"; printf "err\n" >&2; exit 0'
rr_record_cmd exit7 -- bash -c 'exit 7'
rr_record_cmd exit127 -- bash -c 'exit 127'
rr_record_cmd exit143 -- bash -c 'exit 143'
rr_record_cmd bytes -- python3 -c 'import sys; sys.stdout.buffer.write(b"out-\x80\xff\n"); sys.stderr.buffer.write(b"err-\xfe\n")'
rr_record_cmd argvr -- bash -c 'i=0; for a in "$@"; do printf "%d:[%s]\n" "$i" "$a"; i=$((i+1)); done' _ "" "a b" "line1
line2" "  "
eq "exit0 status" 0 "$(field exit0.status)" status
eq "exit0 outcome" exit "$(field exit0.outcome)" outcome
eq "exit7 status" 7 "$(field exit7.status)" status
eq "exit127 status" 127 "$(field exit127.status)" status
inlist "exit127 outcome" "exit|exit-or-signal" "$(field exit127.outcome)" outcome
eq "exit143 status" 143 "$(field exit143.status)" status
inlist "exit143 outcome" "exit|exit-or-signal" "$(field exit143.outcome)" outcome
printf 'out-\x80\xff\n' > "$TMP/bytes.stdout.expected"
printf 'err-\xfe\n' > "$TMP/bytes.stderr.expected"
if cmp -s "$TMP/bytes.stdout.expected" "$RR_CMD/bytes.stdout"; then ok "bytes stdout byte-exact"; else bad "bytes stdout differs"; fi
if cmp -s "$TMP/bytes.stderr.expected" "$RR_CMD/bytes.stderr"; then ok "bytes stderr byte-exact"; else bad "bytes stderr differs"; fi
printf '0:[]\n1:[a b]\n2:[line1\nline2]\n3:[  ]\n' > "$TMP/argv.expected"
if cmp -s "$TMP/argv.expected" "$RR_CMD/argvr.stdout"; then ok "argv round-trip"; else bad "argv round-trip differs"; fi

# 2. An empty command must be refused, never recorded as a success.
rr_record_cmd emptyargv --; earc=$?
eas="$(field emptyargv.status)"
eao="$(field emptyargv.outcome)"
if [ "$earc" -ne 0 ] && [ "$eas" = "125" ] && [ "$eao" = "record-error" ]; then
	ok "empty argv refused (rc=$earc status=$eas outcome=$eao)"
else
	bad "empty argv not refused consistently (rc=$earc status=$eas outcome=$eao)"
fi

# 3. A missing identity input is refused with a failure status and no hash.
rr_identity_files missing-input "$TMP/does-not-exist"; mrc=$?
eq "missing input rc" 2 "$mrc" rc
eq "missing input status" 125 "$(tr -d '\n' < "$RR_RUN/identity/missing-input.status" 2>/dev/null)" status
eq "missing input outcome" record-error "$(tr -d '\n' < "$RR_RUN/identity/missing-input.outcome" 2>/dev/null)" outcome
if [ ! -e "$RR_RUN/identity/missing-input.sha256" ]; then ok "missing input leaves no hash"; else bad "missing input wrote a hash"; fi

# 4. A control byte in the record root stays valid JSON; a non-UTF-8 root is refused.
tabbase="$TMP/tab$(printf '\t')dir"; mkdir -p "$tabbase"
if rr_init jsonpath "$tabbase" >/dev/null 2>&1; then
	rr_finish >/dev/null 2>&1
	if python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert "\t" in d["directory"]' "$RR_RUN/run.json" 2>/dev/null; then
		ok "tab root is valid JSON and escaped"
	else
		bad "tab root is not valid escaped JSON"
	fi
else
	bad "tab root refused before JSON"
fi
badbase="$TMP/bad$(printf '\xff')"; mkdir -p "$badbase" 2>/dev/null
rr_init utf8path "$badbase" >/dev/null 2>&1; urc=$?
eq "non-utf8 root refused" 2 "$urc" rc

# 5. Record write failure with a failing sentinel must still fail closed.
rr_init writefail-all "$TMP" >/dev/null 2>&1
WFA_RUN="$RR_RUN"
rm -rf "$RR_CMD"; : > "$RR_CMD"
RR_ERRORS="$TMP/no-such-subdir/errors.log"
rr_record_cmd wfa -- bash -c 'exit 0'
rr_finish >/dev/null 2>&1; wfafin=$?
wfastatus="$(tr -d '\n' < "$WFA_RUN/run.status" 2>/dev/null)"
if [ "$wfafin" != "0" ] && [ -n "$wfastatus" ] && [ "$wfastatus" != "0" ]; then
	ok "writefail-all closed and consistent (finish=$wfafin status=$wfastatus)"
else
	bad "writefail-all fail-open or inconsistent (finish=$wfafin status=$wfastatus)"
fi

# 6. Consumer error propagation. A temporary tree holds copies so the reviewed
#    consumer is never modified in place.
TREE="$TMP/consumer"
mkdir -p "$TREE/tools/runner-record" "$TREE/tests/bundle-child-evidence" "$TREE/bin"
cp "$LIB" "$TREE/tools/runner-record/runner-record.sh"
cp "$ROOT/tests/bundle-child-evidence/run.sh" "$TREE/tests/bundle-child-evidence/run.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TREE/bin/haxe"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TREE/bin/bun"
chmod +x "$TREE/bin/haxe" "$TREE/bin/bun"

# 6a. A record-command failure must stop the consumer with a non-zero exit.
#     The temporary copy holds one injected stub, so the reviewed file is
#     unchanged and the real identity path still runs.
awk '/rr_identity_files source-hashes/{f=1;next} f&&/\|\|/{exit} f{print}' "$ROOT/tests/bundle-child-evidence/run.sh" \
	| tr -d '\\' | tr -s ' \t' '\n' | grep -v '^$' > "$TMP/identity-inputs.txt"
while IFS= read -r rel; do
	mkdir -p "$TREE/$(dirname "$rel")"
	: > "$TREE/$rel"
done < "$TMP/identity-inputs.txt"
sed '/runner-record\.sh" || exit 2/a rr_record_cmd() { return 2; }' \
	"$ROOT/tests/bundle-child-evidence/run.sh" > "$TREE/tests/bundle-child-evidence/run-injected.sh"
( cd "$TREE" && PATH="$TREE/bin:$PATH" BORING_REVISION=deadbeef bash tests/bundle-child-evidence/run-injected.sh > "$TMP/consumer-inject.log" 2>&1 ); irc=$?
eq "consumer record failure rc" 2 "$irc" rc
if grep -q "recording failed" "$TMP/consumer-inject.log"; then ok "consumer names the failed record"; else bad "consumer did not name the failed record"; fi

# 6b. An unwritable record root must stop the consumer with a non-zero exit.
mkdir -p "$TREE/out/f1-child-evidence"
chmod a-w "$TREE/out/f1-child-evidence"
( cd "$TREE" && BORING_REVISION=deadbeef bash tests/bundle-child-evidence/run.sh > "$TMP/consumer-init.log" 2>&1 ); prc=$?
chmod u+w "$TREE/out/f1-child-evidence"
eq "consumer init failure rc" 2 "$prc" rc

printf '\nrunner-record controls: pass=%d fail=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
