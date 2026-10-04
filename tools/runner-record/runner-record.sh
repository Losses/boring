#!/usr/bin/env bash
# Shared runner recording layer: status, streams and input identity.
#
# Boundary. This library records what happened to one command: its exact
# argument array, working directory, separate raw standard output and error, a
# numeric status, and the content identity of declared inputs and tools. It does
# not decide a verdict, run a compiler, own fixture semantics, define stage
# membership (tests/support/stage-check.sh owns that), or derive a status from
# log text. It never calls git or jj.
#
# Two honesty rules are part of the interface:
# - A shell cannot tell a signal death from an exit with status 128+N. The
#   record keeps the raw status and marks such an outcome "exit-or-signal" with
#   basis "status-range"; it never claims an observed signal.
# - A revision supplied by the caller is recorded as a caller-asserted
#   attestation, never as independently verified identity.
#
# Every record write is fail-closed: if a record cannot be written, the helper
# returns non-zero and the attempt is not recorded, so a caller must stop. A
# record helper never reports success for a record it could not write.
#
# Source it, do not execute it:
#   . tools/runner-record/runner-record.sh

RR_RUN=""
RR_NAME=""
RR_CMD=""
RR_CMD_SUB="commands"
RR_ERRORS=""
RR_ERROR_STATE=0

# rr_identifier NAME
#   Rejects a record name that could break the record layout or run.json.
rr_identifier() {
	case "$1" in
		"" | *[!A-Za-z0-9._-]*)
			printf 'runner-record: refusing record name: %s\n' "$1" >&2
			return 2
			;;
	esac
	return 0
}

# rr_write FILE
#   Writes standard input to FILE atomically. Any failure is a non-zero return;
#   a partially written record is never left in place.
rr_write() {
	local f="$1"
	local tmp="$f.tmp.$$"
	if ! cat > "$tmp"; then
		rm -f "$tmp"
		return 2
	fi
	if ! mv "$tmp" "$f"; then
		rm -f "$tmp"
		return 2
	fi
	return 0
}

# rr_json_escape TEXT
#   Escapes a string for a JSON double-quoted value. Control bytes become the
#   JSON escapes \t \r \b \f or \u00XX, so a tab or carriage return in a path
#   cannot produce invalid JSON. A string that is not valid UTF-8 is refused:
#   JSON cannot represent it, and writing it verbatim would make run.json
#   unreadable.
rr_json_escape() {
	local s="$1"
	if command -v iconv > /dev/null 2>&1; then
		if ! printf '%s' "$s" | iconv -f UTF-8 -t UTF-8 > /dev/null 2>&1; then
			printf 'runner-record: refusing a path that is not valid UTF-8\n' >&2
			return 2
		fi
	fi
	local out=""
	local i ch code
	for (( i=0; i<${#s}; i++ )); do
		ch="${s:i:1}"
		case "$ch" in
			'"') out="$out\\\"" ;;
			'\') out="$out\\\\" ;;
			$'\t') out="$out\\t" ;;
			$'\n') out="$out\\n" ;;
			$'\r') out="$out\\r" ;;
			$'\b') out="$out\\b" ;;
			$'\f') out="$out\\f" ;;
			*)
				printf -v code '%d' "'$ch"
				if [ "$code" -lt 32 ]; then
					printf -v ch '\\u%04x' "$code"
				fi
				out="$out$ch"
				;;
		esac
	done
	printf '%s' "$out"
	return 0
}

# rr_require_dir
rr_require_dir() {
	if [ -z "$RR_CMD" ]; then
		printf 'runner-record: called before rr_init or rr_adopt\n' >&2
		return 2
	fi
	return 0
}

# rr_mark_error NAME REASON
#   Sets the in-memory sticky failure state and best-effort appends the
#   run-level sentinel. The state lives in this shell, so a caller that also
#   cannot write the sentinel still cannot report success at finish.
rr_mark_error() {
	RR_ERROR_STATE=1
	local name="$1"
	local reason="$2"
	if [ -n "$RR_ERRORS" ]; then
		printf '%s\t%s\n' "$name" "$reason" >> "$RR_ERRORS" 2> /dev/null || true
	fi
	return 0
}

# rr_fail NAME REASON
#   Marks a record error (memory plus sentinel), writes the best-effort
#   per-record markers, then returns non-zero unconditionally.
rr_fail() {
	local name="$1"
	local reason="$2"
	rr_mark_error "$name" "$reason"
	if [ -n "$RR_CMD" ]; then
		printf '125\n' | rr_write "$RR_CMD/$name.status" 2> /dev/null || true
		printf 'record-error\n' | rr_write "$RR_CMD/$name.outcome" 2> /dev/null || true
		printf 'status-range\n' | rr_write "$RR_CMD/$name.basis" 2> /dev/null || true
		printf '%s\n' "$reason" | rr_write "$RR_CMD/$name.error" 2> /dev/null || true
	fi
	return 2
}

# rr_init NAME OUT_ROOT
#   Allocates OUT_ROOT/NAME-<utc>-<pid>-XXXXXX exclusively and sets RR_RUN.
rr_init() {
	local name="$1"
	local out_root="$2"
	rr_identifier "$name" || return 2
	mkdir -p "$out_root" || return 2
	local stamp
	stamp="$(date -u +%Y%m%dT%H%M%SZ)" || return 2
	local dir
	dir="$(mktemp -d "$out_root/$name-$stamp-$$-XXXXXX")" || return 2
	# An absolute record root survives a runner that changes directory later.
	RR_RUN="$(cd "$dir" && pwd)" || return 2
	# Refuse an unrepresentable record root before any work is recorded.
	rr_json_escape "$RR_RUN" > /dev/null || {
		printf 'runner-record: refusing an unrepresentable record root: %s\n' "$RR_RUN" >&2
		return 2
	}
	RR_NAME="$name"
	RR_CMD_SUB="commands"
	RR_CMD="$RR_RUN/$RR_CMD_SUB"
	RR_ERRORS="$RR_RUN/record-errors.log"
	RR_ERROR_STATE=0
	mkdir -p "$RR_CMD" "$RR_RUN/identity" || return 2
	printf '%s\n' "$$" | rr_write "$RR_RUN/runner.pid" || return 2
	printf '%s\n' "$stamp" | rr_write "$RR_RUN/runner.started" || return 2
	return 0
}

# rr_adopt DIR [CMD_SUBDIR]
#   Adopts an already-allocated exclusive directory instead of allocating one,
#   for a runner that keeps its own allocation and its own captured-child
#   layout. CMD_SUBDIR places command records under DIR/CMD_SUBDIR (default
#   "commands"). The caller stays responsible for having allocated DIR
#   exclusively; this function never reuses an earlier attempt's records.
rr_adopt() {
	local dir="$1"
	shift
	local sub="commands"
	if [ "$#" -gt 0 ]; then sub="$1"; fi
	rr_identifier "$sub" || return 2
	if [ ! -d "$dir" ]; then
		printf 'runner-record: rr_adopt: not a directory: %s\n' "$dir" >&2
		return 2
	fi
	RR_RUN="$(cd "$dir" && pwd)" || return 2
	rr_json_escape "$RR_RUN" > /dev/null || {
		printf 'runner-record: refusing an unrepresentable record root: %s\n' "$RR_RUN" >&2
		return 2
	}
	RR_NAME="adopted"
	RR_CMD_SUB="$sub"
	RR_CMD="$RR_RUN/$RR_CMD_SUB"
	RR_ERRORS="$RR_RUN/record-errors.log"
	RR_ERROR_STATE=0
	mkdir -p "$RR_CMD" "$RR_RUN/identity" || return 2
	return 0
}

# rr_argv_matches FILE ARGV...
#   Re-reads the saved NUL-separated array and compares it byte for byte with
#   the live arguments.
rr_argv_matches() {
	local file="$1"
	shift
	local saved=()
	mapfile -d '' -t saved < "$file" || return 1
	if [ "${#saved[@]}" -ne "$#" ]; then return 1; fi
	local i=0
	while [ "$i" -lt "$#" ]; do
		if [ "${saved[$i]}" != "$1" ]; then return 1; fi
		shift
		i=$((i + 1))
	done
	return 0
}

# rr_record_cmd NAME -- ARGV...
#   Runs ARGV with stdin from /dev/null and records, under RR_CMD:
#     NAME.argv     exact arguments, NUL-separated
#     NAME.cwd      working directory
#     NAME.stdout   raw standard output, byte for byte
#     NAME.stderr   raw standard error, byte for byte
#     NAME.status   raw numeric status, never rewritten from log text
#     NAME.outcome  exit | exit-or-signal | not-executable | not-found |
#                   record-error
#     NAME.basis    status-range (a convention over the raw status, not an
#                   observation)
#   A zero-argument command is refused: there is nothing to run and nothing to
#   record. Every write is fail-closed, and the saved argument file is compared
#   byte for byte before the command runs.
rr_record_cmd() {
	local name="$1"
	shift
	if [ "$#" -gt 0 ] && [ "$1" = "--" ]; then shift; fi
	rr_identifier "$name" || return 2
	rr_require_dir || return 2
	if [ "$#" -eq 0 ]; then
		printf 'runner-record: refusing a zero-argument command record: %s\n' "$name" >&2
		rr_fail "$name" "zero-argument command record"
		return 2
	fi
	local dir="$RR_CMD"
	# Resolve the command before running it, so a 127 from a real exit is not
	# confused with a missing command, and a 126 from a real exit is not
	# confused with a non-executable file.
	local resolution="resolved"
	case "$1" in
		*/*)
			if [ ! -e "$1" ]; then
				resolution="missing"
			elif [ ! -x "$1" ]; then
				resolution="not-executable"
			fi
			;;
		*)
			if ! command -v "$1" > /dev/null 2>&1; then
				resolution="missing"
			fi
			;;
	esac
	if ! printf '%s\0' "$@" | rr_write "$dir/$name.argv"; then
		rr_fail "$name" "argv record could not be written"
		return 2
	fi
	if ! rr_argv_matches "$dir/$name.argv" "$@"; then
		rr_fail "$name" "argv record did not round-trip"
		return 2
	fi
	if ! printf '%s\n' "$PWD" | rr_write "$dir/$name.cwd"; then
		rr_fail "$name" "cwd record could not be written"
		return 2
	fi
	local out="$dir/$name.stdout.tmp.$$"
	local err="$dir/$name.stderr.tmp.$$"
	if ! : > "$out" 2> /dev/null; then
		rr_fail "$name" "stdout record could not be created"
		return 2
	fi
	if ! : > "$err" 2> /dev/null; then
		rm -f "$out"
		rr_fail "$name" "stderr record could not be created"
		return 2
	fi
	"$@" > "$out" 2> "$err" < /dev/null
	local status=$?
	if ! mv "$out" "$dir/$name.stdout"; then
		rm -f "$out" "$err"
		rr_fail "$name" "stdout record could not be committed"
		return 2
	fi
	if ! mv "$err" "$dir/$name.stderr"; then
		rm -f "$err"
		rr_fail "$name" "stderr record could not be committed"
		return 2
	fi
	local outcome
	local basis="status-range"
	if [ "$status" -eq 127 ] && [ "$resolution" = "missing" ]; then
		outcome="not-found"
		basis="preflight-resolution"
	elif [ "$status" -eq 126 ] && [ "$resolution" = "not-executable" ]; then
		outcome="not-executable"
		basis="preflight-resolution"
	elif [ "$status" -ge 128 ]; then
		outcome="exit-or-signal"
	else
		outcome="exit"
	fi
	if ! printf '%s\n' "$status" | rr_write "$dir/$name.status"; then
		rr_fail "$name" "status record could not be written"
		return 2
	fi
	if ! printf '%s\n' "$outcome" | rr_write "$dir/$name.outcome"; then
		rr_fail "$name" "outcome record could not be written"
		return 2
	fi
	if ! printf '%s\n' "$basis" | rr_write "$dir/$name.basis"; then
		rr_fail "$name" "basis record could not be written"
		return 2
	fi
	return 0
}

# rr_identity_files NAME FILE...
#   Records sha256sum output for the declared inputs. A missing input is a
#   non-zero status value, never a silent omission. Zero paths is refused.
rr_identity_files() {
	local name="$1"
	shift
	rr_identifier "$name" || return 2
	rr_require_dir || return 2
	if [ "$#" -eq 0 ]; then
		printf 'runner-record: refusing an empty file identity: %s\n' "$name" >&2
		return 2
	fi
	local dir="$RR_RUN/identity"
	local input
	for input in "$@"; do
		if [ ! -e "$input" ]; then
			printf 'runner-record: refusing a missing file identity input: %s\n' "$input" >&2
			printf '125\n' | rr_write "$dir/$name.status" 2> /dev/null || true
			printf 'record-error\n' | rr_write "$dir/$name.outcome" 2> /dev/null || true
			rr_fail "$name" "missing file identity input"
			return 2
		fi
	done
	printf '%s\0' "$@" | rr_write "$dir/$name.argv" || return 2
	local status=0
	sha256sum "$@" > "$dir/$name.sha256.tmp.$$" 2> "$dir/$name.stderr.tmp.$$" < /dev/null || status=$?
	mv "$dir/$name.sha256.tmp.$$" "$dir/$name.sha256" || return 2
	mv "$dir/$name.stderr.tmp.$$" "$dir/$name.stderr" || return 2
	printf '%s\n' "$status" | rr_write "$dir/$name.status" || return 2
	return 0
}

# rr_identity_tree NAME DIR...
#   Records the recursive content identity of the declared directories: every
#   regular file path and sha256, in a stable order. Zero paths is refused.
rr_identity_tree() {
	local name="$1"
	shift
	rr_identifier "$name" || return 2
	rr_require_dir || return 2
	if [ "$#" -eq 0 ]; then
		printf 'runner-record: refusing an empty tree identity: %s\n' "$name" >&2
		return 2
	fi
	local dir="$RR_RUN/identity"
	local d
	for d in "$@"; do
		if [ ! -d "$d" ]; then
			printf 'runner-record: refusing a missing tree identity input: %s\n' "$d" >&2
			printf '125\n' | rr_write "$dir/$name.status" 2> /dev/null || true
			printf 'record-error\n' | rr_write "$dir/$name.outcome" 2> /dev/null || true
			rr_fail "$name" "missing tree identity input"
			return 2
		fi
	done
	printf '%s\0' "$@" | rr_write "$dir/$name.argv" || return 2
	{
		for d in "$@"; do
			find "$d" -type f -print0
		done
	} | sort -z | xargs -0 -r sha256sum > "$dir/$name.sha256.tmp.$$" 2> "$dir/$name.stderr.tmp.$$"
	local status=$?
	mv "$dir/$name.sha256.tmp.$$" "$dir/$name.sha256" || return 2
	mv "$dir/$name.stderr.tmp.$$" "$dir/$name.stderr" || return 2
	printf '%s\n' "$status" | rr_write "$dir/$name.status" || return 2
	return 0
}

# rr_identity_stream NAME -- ARGV...
#   Records the standard output of ARGV as a named content-identity record,
#   with its argv, working directory, stderr and numeric status beside it. Use
#   it when the input closure needs a selection rule the file and tree helpers
#   cannot express (a glob, or several roots hashed by one pipeline). Zero
#   arguments is refused.
rr_identity_stream() {
	local name="$1"
	shift
	if [ "$#" -gt 0 ] && [ "$1" = "--" ]; then shift; fi
	rr_identifier "$name" || return 2
	rr_require_dir || return 2
	if [ "$#" -eq 0 ]; then
		printf 'runner-record: refusing an empty stream identity: %s\n' "$name" >&2
		return 2
	fi
	local dir="$RR_RUN/identity"
	printf '%s\0' "$@" | rr_write "$dir/$name.argv" || return 2
	printf '%s\n' "$PWD" | rr_write "$dir/$name.cwd" || return 2
	"$@" > "$dir/$name.sha256.tmp.$$" 2> "$dir/$name.stderr.tmp.$$" < /dev/null
	local status=$?
	mv "$dir/$name.sha256.tmp.$$" "$dir/$name.sha256" || return 2
	mv "$dir/$name.stderr.tmp.$$" "$dir/$name.stderr" || return 2
	printf '%s\n' "$status" | rr_write "$dir/$name.status" || return 2
	return 0
}

# rr_identity_capture NAME
#   Records standard input as a named content-identity record with its own
#   numeric status. Use it to route a runner's existing closure pipeline through
#   the common identity layout without re-implementing the selection rule.
rr_identity_capture() {
	local name="$1"
	rr_identifier "$name" || return 2
	rr_require_dir || return 2
	local dir="$RR_RUN/identity"
	printf 'stdin\n' | rr_write "$dir/$name.argv" || return 2
	if ! cat > "$dir/$name.sha256.tmp.$$"; then
		rm -f "$dir/$name.sha256.tmp.$$"
		return 2
	fi
	mv "$dir/$name.sha256.tmp.$$" "$dir/$name.sha256" || return 2
	printf '0\n' | rr_write "$dir/$name.status" || return 2
	return 0
}

# rr_identity_tool NAME PATH
#   Records one tool's explicit realpath, content hash and version output.
#   PATH must contain a slash; a bare command name is refused so that a PATH
#   lookup can never stand in for an identity.
rr_identity_tool() {
	local name="$1"
	local tool_path="$2"
	rr_identifier "$name" || return 2
	rr_require_dir || return 2
	local dir="$RR_RUN/identity"
	case "$tool_path" in
		*/*) ;;
		*)
			printf 'refusing bare tool name: %s\n' "$tool_path" | rr_write "$dir/$name.stderr" || true
			printf '125\n' | rr_write "$dir/$name.status" || true
			printf 'bare-name\n' | rr_write "$dir/$name.outcome" || true
			return 2
			;;
	esac
	printf '%s\n' "$tool_path" | rr_write "$dir/$name.requested" || return 2
	local rp_status=0
	readlink -f "$tool_path" > "$dir/$name.realpath.tmp.$$" 2> "$dir/$name.realpath.stderr.tmp.$$" || rp_status=$?
	mv "$dir/$name.realpath.tmp.$$" "$dir/$name.realpath" || return 2
	mv "$dir/$name.realpath.stderr.tmp.$$" "$dir/$name.realpath.stderr" || return 2
	printf '%s\n' "$rp_status" | rr_write "$dir/$name.realpath.status" || return 2
	local sha_status=0
	sha256sum "$tool_path" > "$dir/$name.sha256.tmp.$$" 2>> "$dir/$name.realpath.stderr" || sha_status=$?
	mv "$dir/$name.sha256.tmp.$$" "$dir/$name.sha256" || return 2
	printf '%s\n' "$sha_status" | rr_write "$dir/$name.sha256.status" || return 2
	"$tool_path" --version > "$dir/$name.version.tmp.$$" 2> "$dir/$name.version.stderr.tmp.$$" < /dev/null
	local status=$?
	mv "$dir/$name.version.tmp.$$" "$dir/$name.version" || return 2
	mv "$dir/$name.version.stderr.tmp.$$" "$dir/$name.version.stderr" || return 2
	printf '%s\n' "$status" | rr_write "$dir/$name.status" || return 2
	printf 'exit-or-signal\n' | rr_write "$dir/$name.outcome" || return 2
	return 0
}

# rr_identity_revision NAME
#   Records the explicit checkout revision supplied in the exported
#   BORING_REVISION, plus the optional BORING_REVISION_STATUS that names how it
#   was verified. It never calls a repository command, so no implicit git or jj
#   invocation can stand in for identity. The revision is recorded as a
#   caller-asserted attestation: a non-zero exit would mean "not supplied", and
#   a zero exit never means "independently verified". An unset or empty revision
#   is a non-zero status value (125) with outcome "unset".
rr_identity_revision() {
	local name="$1"
	rr_identifier "$name" || return 2
	rr_require_dir || return 2
	local dir="$RR_RUN/identity"
	local revision
	local verification
	revision="$(printenv BORING_REVISION 2> /dev/null || true)"
	verification="$(printenv BORING_REVISION_STATUS 2> /dev/null || true)"
	printf 'BORING_REVISION\n' | rr_write "$dir/$name.argv" || return 2
	printf '%s\n' "$revision" | rr_write "$dir/$name.value" || return 2
	printf '%s\n' "$verification" | rr_write "$dir/$name.verification" || return 2
	printf 'caller-asserted\n' | rr_write "$dir/$name.attestation" || return 2
	printf 'no\n' | rr_write "$dir/$name.verified" || return 2
	if [ -z "$revision" ]; then
		printf '125\n' | rr_write "$dir/$name.status" || return 2
		printf 'unset\n' | rr_write "$dir/$name.outcome" || return 2
		return 0
	fi
	printf '0\n' | rr_write "$dir/$name.status" || return 2
	printf 'supplied\n' | rr_write "$dir/$name.outcome" || return 2
	return 0
}

# rr_finish
#   Writes run.json and run.status. Returns non-zero if any recorded status was
#   non-zero, or if the summary itself could not be written. The caller decides
#   what a non-zero means; this library never invents a verdict.
rr_finish() {
	local dir="$RR_RUN"
	if [ -z "$dir" ]; then
		printf 'runner-record: rr_finish called before rr_init or rr_adopt\n' >&2
		return 2
	fi
	local esc_dir
	if ! esc_dir="$(rr_json_escape "$dir")"; then
		rr_mark_error summary "record root is not representable in JSON"
		return 2
	fi
	{
		printf '{\n'
		printf '  "runner": "%s",\n' "$(rr_json_escape "$RR_NAME")"
		printf '  "directory": "%s",\n' "$esc_dir"
		printf '  "commands": [\n'
		local first=1
		local f
		for f in "$RR_CMD"/*.status; do
			[ -e "$f" ] || continue
			local base
			base="$(basename "$f" .status)"
			local status outcome basis
			status="$(cat "$RR_CMD/$base.status")"
			outcome="$(cat "$RR_CMD/$base.outcome" 2> /dev/null || printf 'exit')"
			basis="$(cat "$RR_CMD/$base.basis" 2> /dev/null || printf 'status-range')"
			if [ "$first" -eq 0 ]; then printf ',\n'; fi
			first=0
			printf '    {"name": "%s", "status": %s, "outcome": "%s", "basis": "%s", "argv": "%s", "stdout": "%s", "stderr": "%s"}' \
				"$base" "$status" "$outcome" "$basis" "$RR_CMD_SUB/$base.argv" "$RR_CMD_SUB/$base.stdout" "$RR_CMD_SUB/$base.stderr"
		done
		printf '\n  ],\n'
		printf '  "identity": [\n'
		first=1
		for f in "$dir"/identity/*.status; do
			[ -e "$f" ] || continue
			local base
			base="$(basename "$f" .status)"
			local status outcome attestation verified
			status="$(cat "$dir/identity/$base.status")"
			outcome="$(cat "$dir/identity/$base.outcome" 2> /dev/null || printf '')"
			attestation="$(cat "$dir/identity/$base.attestation" 2> /dev/null || printf '')"
			verified="$(cat "$dir/identity/$base.verified" 2> /dev/null || printf '')"
			if [ "$first" -eq 0 ]; then printf ',\n'; fi
			first=0
			printf '    {"name": "%s", "status": %s, "outcome": "%s", "attestation": "%s", "verified": "%s"}' \
				"$base" "$status" "$outcome" "$attestation" "$verified"
		done
		printf '\n  ],\n'
		local record_errors_json="false"
		if [ "$RR_ERROR_STATE" -ne 0 ]; then record_errors_json="true"; fi
		if [ -n "$RR_ERRORS" ] && [ -e "$RR_ERRORS" ]; then record_errors_json="true"; fi
		printf '  "recordErrors": %s\n' "$record_errors_json"
		printf '}\n'
	} > "$dir/run.json.tmp.$$"
	local json_status=$?
	if [ "$json_status" -ne 0 ]; then
		rm -f "$dir/run.json.tmp.$$"
		return 2
	fi
	if ! mv "$dir/run.json.tmp.$$" "$dir/run.json"; then
		rm -f "$dir/run.json.tmp.$$"
		return 2
	fi
	local overall=0
	for f in "$RR_CMD"/*.status "$dir"/identity/*.status; do
		[ -e "$f" ] || continue
		local s
		if ! s="$(cat "$f" 2> /dev/null)" || [ -z "$s" ]; then
			rr_mark_error summary "unreadable status record: $f"
			overall=1
			continue
		fi
		if [ "$s" -ne 0 ]; then overall=1; fi
	done
	local record_errors=0
	if [ "$RR_ERROR_STATE" -ne 0 ]; then
		record_errors=1
		overall=1
	fi
	if [ -n "$RR_ERRORS" ] && [ -e "$RR_ERRORS" ]; then
		record_errors=1
		overall=1
	fi
	printf '%s\n' "$overall" | rr_write "$dir/run.status" || return 2
	printf 'runner-record: %s\n' "$dir"
	printf 'runner-record overall: %s\n' "$overall"
	if [ "$record_errors" -ne 0 ]; then
		printf 'runner-record: record errors were logged in %s\n' "$RR_ERRORS" >&2
		return 2
	fi
	return "$overall"
}
