#!/usr/bin/env bash
# Roots-manifest consistency guard (precision-switch bundles).
#
# WHAT THIS SCRIPT ACTUALLY ENFORCES -- nothing stronger.  (An earlier header
# claimed it kept "the cross-target test id set equal"; the guard never reads a
# module body or a test id, so that claim is withdrawn.  It compares
# root-module LISTS, which is necessary but not sufficient for equal id sets.)
#
# For each guarded target T in {kotlin,rust,swift}, with
#   B = examples/T.hxml        F = examples/T-f32.hxml
#
#  (1) ROOT-SET EQUALITY, BOTH DIRECTIONS.  root(B) == root(F).
#      A module in B but not F ("base-only") and a module in F but not B
#      ("f32-only") are both reported, and either one fails the guard.
#      A root is:
#        (i)   a bare module-path line `Ident(.Ident)*`,
#        (ii)  a `-main <module>` argument,
#        (iii) any root of a nested `.hxml` include (depth <= 8),
#        (iv) none.  `--macro include('X')` and
#             `--macro haxe.macro.Compiler.include('X')` are PARSED but
#             contribute no roots: measured with haxe 4.3.7, a complete
#             module argument (present, absent, or even a malformed name
#             such as `no-such-pkg`) is a SILENT NO-OP (rc=0, the compiled
#             class set is unchanged -- the argument is not a root); the
#             one case where the line changes compilation is an argument
#             that names a PACKAGE DIRECTORY on the file's own classpath
#             (e.g. `include('extra')` when `extra/` is on -cp): haxe then
#             rejects the file with
#             "Invalid commandline class : extra.X should be X" (rc=1),
#             and this guard fails the file the same way.  That is the
#             only include() effect modelled; nothing else is.

#      Line grammar follows haxe 4.3.7, measured (evidence/05-* in
#      dc-warn/out/roots-guard-f2/evidence/): surrounding whitespace
#      (space, tab) and a trailing CR are trimmed exactly as the compiler
#      trims them, so a root line with a leading space/tab, a trailing space,
#      or a trailing CR is a ROOT here (and a failure when it diverges),
#      never silently dropped.  A line that carries two tokens, or an inline
#      '#' inside the argument, is REJECTED here, exactly as the compiler
#      rejects it ("Could not process argument ... Invalid character").  A
#      line that is neither a recognised flag, an include, nor a module path
#      fails; it is no longer silently dropped.
#      OUT OF SCOPE, explicitly: every other `--macro` line --
#      haxe.macro.Compiler.keep, haxe.macro.Compiler.addGlobalMetadata, and
#      custom macros such as Intercept.run -- and every other flag line.
#      Whatever modules those force-keep, force-add, or otherwise change are
#      NOT part of the root set this guard models, and this header does not
#      claim otherwise.  (A one-sided `--macro` that changes the compiled
#      module set through a non-include macro is therefore undetectable here
#      by design; only the include('X') reject case of (iv) is modelled.)

#  (2) DECLARED DIVERGENCE.  roots-allowlist.json `exempt` entries authorise a
#      specific (target, module) asymmetry.  An entry must be LIVE: that module
#      must really be the asymmetric one for that target; an entry for a
#      guarded target whose module is symmetric for it (present in both files,
#      or absent from both) is a STALE exemption and fails.  Entries are
#      structurally validated: target in {kotlin,rust,swift,*} (anything else
#      fails the structural check), module a plausible dotted module path, and
#      a reason that passes the shape checks below.  NO MEANING CHECK: the
#      reason checks verify SHAPE ONLY -- at least 4 whitespace-separated
#      words, at least 24 characters, no tab/newline, not a single known
#      placeholder token, at least three ASCII letters, no repeated-token
#      spam (one token occupying half or more of the words, so "todo todo
#      todo todo todo!" fails), and no padded/gibberish token (three or
#      more consecutive repeats of one character, so the minimal
#      four-word 24-character bypass "aaaa bbbb cccc dddxxxxxx" fails).
#      A well-shaped but meaningless reason (e.g. "alpha beta gamma delta
#      oxen") still passes: a script cannot verify that prose is
#      meaningful, so a reviewer has to read the reason.  A single
#      `target: "*"` entry authorises the same
#      (module, reason) for all three guarded targets at once (one entry =
#      up to three EXEMPT/UNROOT effects); that blast radius is by design.
#  (3) ROOT EXISTENCE, PER FILE.  Every root of a file must resolve to a
#      real .hx on the classpath THAT FILE declares: its own -cp/-lib lines
#      plus the -cp/-lib lines of the .hxml files it includes.  A root that
#      only another file's classpath provides fails -- classpath sets are
#      checked per file, not unioned (removing `-cp samples` from one f32
#      file is a failure).  No repo-wide fallback applies to file roots.
#      Modules named by the allowlist or by the root floor are resolved
#      against the union of all guarded classpaths, with a repo-wide .hx
#      fallback; for those, existence is still not compilability (a module
#      no single file's classpath provides can still pass if the union or
#      the fallback sees it).
#  (4) TEST-MODULE COVERAGE.  Every .hx under a `tests/` directory of a
#      guarded classpath (the union of all six files' classpaths) that
#      declares `@:test` must be a root of at least one of B/F.  A test
#      module missing from BOTH files used to be invisible; it now fails
#      unless declared in allowlist section `unrootedTestModules` (also
#      shape-checked and stale-checked -- and, when it was rooted at the
#      last baseline refresh, caught by (5) even with a well-shaped
#      declaration).
#  (5) ROOT FLOOR.  roots-baseline.txt pins the root set at the moment it
#      was last refreshed: every pinned (target, module) must still be a
#      root of at least one of the pair's files.  (1) compares the two
#      files against each other, so a root deleted from BOTH files is
#      invisible to it; (5) catches that deletion (whether or not the
#      module declares @:test).  The shipped baseline is the root set of
#      the current tree (union of each pair's two files, one line per
#      module).  If a root-set change is deliberate, refresh the floor with
#      `--print-baseline > roots-baseline.txt`; the floor check is
#      fail-closed when the file is missing.
#
# REPORTED BUT NOT FATAL (use --strict-duplicates to fail on them):
#   * duplicate root lines inside one pair.  The shipped hxml files currently
#     contain 45 such lines; duplicates cannot change the module set, they are
#     inert, and this guard does not modify examples/**.  They are printed with
#     file:line and counted so they stop being invisible.
#
# NOT COVERED (the header never claims these):
#   * the meaning of a reason (shape only, see (2));
#   * side effects of non-include `--macro` lines and of all other flag lines
#     (see (1)); `--next`/`--each` multi-compilation files are flattened into
#     one root set;
#   * @:test modules outside a <guarded-classpath>/tests directory, including
#     any under the repository-root tests/ (coverage scans the guarded
#     classpaths' tests/ directories only);
#   * compilability of allowlist/floor modules beyond existence (see (3));
#   * test ids, @:test case sets, module bodies, runtime behaviour under
#     binary32/binary64.  `samples/tests/f32/PrintedFloatTests.hx` ships 6
#     f32-only ids that this guard cannot see (declared in
#     tools/test-consistency/extra-id-allowlist.json);
#   * dart/ts pairs are not guarded (no -f32 variant);
#   * bypass surfaces: ROOTS_GUARD_ALLOWLIST (see below) and --repo-root /
#     ROOTS_GUARD_REPO_ROOT redirect what is checked; a caller who can set
#     them can point the guard at any allowlist or tree, so a PASS is only
#     as strong as the provenance of the allowlist and the tree it ran on.
#
# Usage: check-roots-guard.sh [examples-dir] [--repo-root=PATH]
#                       [--strict-duplicates] [--print-baseline]
#
#   examples-dir        default: <script>/../../examples
#   --repo-root=PATH    repository root used for module-source resolution
#                       (also honoured: ROOTS_GUARD_REPO_ROOT).  If discovery
#                       fails the guard FAILS rather than skipping the checks.
#   --strict-duplicates fail on duplicate root lines (see above)
#   --print-baseline    print the current root floor (one `target<TAB>module`
#                       line per module of the union of each pair's root
#                       sets) and exit; use it to refresh
#                       roots-baseline.txt after a deliberate root change.
#
# Environment:
#   ROOTS_GUARD_REPO_ROOT   repository root (same as --repo-root=PATH)
#   ROOTS_GUARD_ALLOWLIST   path of the allowlist (default:
#                       <script>/roots-allowlist.json).  Documented
#                       override: a PASS produced with a non-default
#                       allowlist is only as strong as that file.
#
# Exit: 0 = PASS, 1 = FAILED, 2 = usage error.
set -u

usage() {
    local last
    last="$(grep -n '^set -u$' "$0" | head -n1 | cut -d: -f1)"
    sed -n "2,$((last - 1))p" "$0"
}

examples=""
repo_override="${ROOTS_GUARD_REPO_ROOT:-}"
strict_dups=0
print_baseline=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --repo-root=*)       repo_override="${1#*=}" ;;
        --strict-duplicates) strict_dups=1 ;;
        --print-baseline)    print_baseline=1 ;;
        -h|--help)           usage; exit 0 ;;
        -*)                  echo "FAIL: unknown option: $1"; exit 2 ;;
        *)                   if [ -z "$examples" ]; then examples="$1";
                              else echo "FAIL: unexpected argument: $1"; exit 2; fi ;;
    esac
    shift
done

here="$(cd "$(dirname "$0")" && pwd)"
allowlist="${ROOTS_GUARD_ALLOWLIST:-$here/roots-allowlist.json}"
baseline="$here/roots-baseline.txt"
examples="${examples:-$here/../../examples}"
if [ ! -d "$examples" ]; then
    echo "FAIL: examples directory not found: $examples"
    echo "roots guard: FAILED"
    exit 1
fi
examples="$(cd "$examples" && pwd)"

# ---------------------------------------------------------------- repo root --
looks_like_repo() {
    local d="$1"
    [ -f "$d/haxelib.json" ] && [ -d "$d/samples" ] && [ -d "$d/packages" ]
}
repo="$repo_override"
if [ -z "$repo" ]; then
    d="$here"
    while :; do
        if looks_like_repo "$d"; then repo="$d"; break; fi
        case "$d" in
            /) repo=""; break ;;
            *) d="${d%/*}"
               [ -n "$d" ] || { d="/"; }
               ;;
        esac
    done
fi
if [ -z "$repo" ] || ! looks_like_repo "$repo"; then
    echo "FAIL: could not discover repository root (need haxelib.json + samples/ + packages/); pass --repo-root=PATH"
    echo "roots guard: FAILED"
    exit 1
fi
repo="$(cd "$repo" && pwd)"

fail=0
exemptions=0
unrooted_decls=0
dup_lines=0
floor_pins=0

tmpd="$(mktemp -d "${TMPDIR:-/tmp}/roots-guard.XXXXXX")"
trap 'rm -rf "$tmpd"' EXIT

# ---------------------------------------------------------------- allowlist --
if [ ! -f "$allowlist" ]; then
    echo "FAIL: allowlist not found: $allowlist"
    echo "roots guard: FAILED"
    exit 1
fi
node -e '
const fs = require("fs");
const raw = fs.readFileSync(process.argv[1], "utf8");
let doc;
try { doc = JSON.parse(raw); }
catch (e) { console.log("FAIL: allowlist is not valid JSON: " + e.message); process.exit(1); }
if (doc === null || typeof doc !== "object" || Array.isArray(doc)) {
    console.log("FAIL: allowlist root must be a JSON object"); process.exit(1);
}
const allowed = new Set(["exempt", "unrootedTestModules"]);
for (const k of Object.keys(doc)) if (!allowed.has(k))
    console.log("FAIL: unknown top-level key: " + JSON.stringify(k));
const GUARDED = new Set(["kotlin", "rust", "swift", "*"]);
const PLACEHOLDER = new Set(["", "x", "todo", "n/a", "na", "none", "fixme", "xxx", "placeholder", "reason"]);
function moduleOk(s) { return typeof s === "string" && /^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$/.test(s); }
function reasonProblem(r) {
    if (typeof r !== "string") return "reason is not a string";
    const t = r.trim();
    if (!t) return "blank/whitespace-only reason";
    if (/[\t\n\r]/.test(t)) return "reason contains a tab or newline";
    const words = t.split(/\s+/);
    if (words.length < 4) return "reason is too short to be an exemption sentence (" + words.length +
        " word(s): " + JSON.stringify(t) + "); need >= 4 words";
    if (t.length < 24) return "reason too short (" + t.length + " chars, need >= 24)";
    if (PLACEHOLDER.has(t.toLowerCase())) return "reason is a placeholder token: " + JSON.stringify(t);
    if (!/[A-Za-z]{3}/.test(t)) return "reason contains no prose";
    for (const w of words) {
        if (/(.)\1{2,}/.test(w))
            return "reason contains a padded/gibberish token (three or more consecutive repeats of one character): " +
                JSON.stringify(w);
    }
    const cnt = {};
    let mxTok = "", mxN = 0;
    for (const w of words) {
        const k = w.toLowerCase();
        cnt[k] = (cnt[k] || 0) + 1;
        if (cnt[k] > mxN) { mxN = cnt[k]; mxTok = k; }
    }
    if (mxN >= Math.ceil(words.length / 2))
        return "reason is repeated-token spam (" + mxN + " of " + words.length +
            " words are " + JSON.stringify(mxTok) + ")";
    return "";
}
function checkEntry(section, i, e) {
    if (e === null || typeof e !== "object" || Array.isArray(e))
        return section + "[" + i + "] is not an object";
    const keys = Object.keys(e).sort();
    const want = ["module", "reason", "target"];
    if (keys.join(",") !== want.join(","))
        return section + "[" + i + "] keys must be exactly target,module,reason (got " +
            keys.join(",") + ")";
    if (!GUARDED.has(e.target))
        return section + "[" + i + "].target must be one of kotlin/rust/swift/* (got " +
            JSON.stringify(e.target) + ")";
    if (!moduleOk(e.module))
        return section + "[" + i + "].module is not a plausible dotted module path: " +
            JSON.stringify(e.module);
    const rp = reasonProblem(e.reason);
    if (rp) return section + "[" + i + "].module " + e.module + ": " + rp;
    return "";
}
const seen = new Set();
let bad = 0;
for (const section of ["exempt", "unrootedTestModules"]) {
    const arr = doc[section];
    if (arr === undefined) continue;
    if (!Array.isArray(arr)) {
        console.log("FAIL: " + section + " must be an array"); bad = 1; continue;
    }
    for (let i = 0; i < arr.length; i++) {
        const p = checkEntry(section, i, arr[i]);
        if (p) { console.log("FAIL: allowlist: " + p); bad = 1; continue; }
        const t = arr[i].target === "*" ? ["kotlin", "rust", "swift"] : [arr[i].target];
        for (const tt of t) {
            const k = section + "|" + tt + "|" + arr[i].module;
            if (seen.has(k)) {
                console.log("FAIL: allowlist: duplicate " + section + " entry for target " +
                    tt + " module " + arr[i].module); bad = 1;
            }
            seen.add(k);
        }
    }
}
process.exit(bad ? 1 : 0);
' "$allowlist"
if [ $? -ne 0 ]; then
    echo "roots guard: FAILED"
    exit 1
fi

declare -a ex_keys=() un_keys=()
declare -A ex_reason=() un_reason=()
node -e '
const fs = require("fs");
const doc = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
for (const s of ["exempt", "unrootedTestModules"]) {
    for (const e of doc[s] || []) {
        for (const t of (e.target === "*" ? ["kotlin", "rust", "swift"] : [e.target]))
            process.stdout.write(s + "\t" + t + "\t" + e.module + "\t" +
                e.reason.replace(/\n/g, " ") + "\n");
    }
}
' "$allowlist" > "$tmpd/entries.tsv"
while IFS=$'\t' read -r sect t mod reason; do
    if [ "$sect" = "exempt" ]; then ex_keys+=("$t|$mod"); ex_reason["$t|$mod"]="$reason"
                                   else un_keys+=("$t|$mod"); un_reason["$t|$mod"]="$reason"; fi
done < "$tmpd/entries.tsv"

# ------------------------------------------------------- root floor (5) -----
FLOOR_MODULES=()
declare -A FLOOR_SEEN=()
if [ "$print_baseline" -eq 0 ]; then
    if [ ! -f "$baseline" ]; then
        echo "FAIL: root-floor baseline not found: $baseline (fail-closed); regenerate it with --print-baseline after a deliberate root-set change"
        fail=1
    else
        bln=0
        while IFS= read -r bline || [ -n "$bline" ]; do
            bln=$((bln + 1))
            bt="${bline#"${bline%%[![:space:]]*}"}"
            bt="${bt%"${bt##*[![:space:]]}"}"
            if [ -z "$bt" ] || [[ "$bt" == \#* ]]; then continue; fi
            fbt=""; fbm=""; fbextra=""
            IFS=$'\t' read -r fbt fbm fbextra <<< "$bt"
            if [ -z "$fbt" ] || [ -z "$fbm" ] || [ -n "$fbextra" ]; then
                echo "FAIL: $baseline:$bln: malformed root-floor line (want exactly target<TAB>module): $bline"
                fail=1
                continue
            fi
            case "$fbt" in
                kotlin|rust|swift) : ;;
                *) echo "FAIL: $baseline:$bln: target must be one of kotlin/rust/swift (got: $fbt)"; fail=1; continue ;;
            esac
            if [[ "$fbm" =~ ^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$ ]]; then :; else
                echo "FAIL: $baseline:$bln: module is not a plausible dotted module path: $fbm"
                fail=1
                continue
            fi
            if [ -n "${FLOOR_SEEN[$fbt|$fbm]:-}" ]; then
                echo "FAIL: $baseline:$bln: duplicate root-floor entry for target $fbt module $fbm (first seen at line ${FLOOR_SEEN[$fbt|$fbm]})"
                fail=1
                continue
            fi
            FLOOR_SEEN["$fbt|$fbm"]="$bln"
            FLOOR_MODULES+=("$fbt"$'\t'"$fbm")
        done < "$baseline"
        floor_pins=${#FLOOR_MODULES[@]}
    fi
fi

# ------------------------------------------------------------- collection ----
declare -A CP_SEEN=()
CP_ALL=()
declare -A FILE_CP=()
declare -A INCLUDE_ARGS=()
INCLUDE_STACK=""
C_QUIET=0

c_fail() {
    fail=1
    [ "$C_QUIET" -eq 1 ] && return 0
    printf '%s\n' "$1" >&2
}

note_cp() {
    [ -d "$1" ] || return 0
    local abs
    abs="$(cd "$1" && pwd)"
    [ -n "${CP_SEEN[$abs]:-}" ] && return 0
    CP_SEEN["$abs"]=1
    CP_ALL+=("$abs")
}

# note_cp_for: record a classpath dir for the global union (allowlist/floor
# existence, coverage) AND for the top-level file it came from (per-file
# existence check).  $1 = top file, $2 = dir (relative or absolute).
note_cp_for() {
    local top="$1" d="$2"
    [ -d "$d" ] || return 0
    local abs
    abs="$(cd "$d" && pwd)"
    note_cp "$abs"
    case $'\n'"${FILE_CP[$top]:-}"$'\n' in
        *$'\n'"$abs"$'\n'*) : ;;
        *) FILE_CP["$top"]="${FILE_CP[$top]:-}${FILE_CP[$top]:+$'\n'}$abs" ;;
    esac
}

lib_classpath() {
    local lib="$1" cur dev hj cp proj rel
    cur="$repo/.haxelib/$lib/.current"
    dev="$repo/.haxelib/$lib/.dev"
    if [ -f "$dev" ] && [ -d "$(cat "$dev" 2>/dev/null)" ]; then
        cp="$(cat "$dev")"
        proj="$cp"
        hj="$cp/haxelib.json"
    elif [ -f "$cur" ] && [ -d "$(cat "$cur" 2>/dev/null)" ]; then
        cp="$(cat "$cur")"
        proj="$cp"
        if [ -f "$cp/haxelib.json" ]; then
            hj="$cp/haxelib.json"
        elif [ -f "$repo/haxelib.json" ] && [ "$(basename "$cp")" = "$lib" ]; then
            hj="$repo/haxelib.json"
            proj="$repo"
        else
            hj=""
        fi
    else
        return 0
    fi
    # A haxelib dev/current install contributes the project's classPath
    # (relative to the project path) to the compiler, which is what haxe
    # actually uses; a dev install's project path is the .dev target.
    # Fall back to the raw install directory when haxelib.json/classPath
    # is absent.
    if [ -n "$hj" ] && [ -f "$hj" ] && command -v node >/dev/null 2>&1; then
        cp="$(node -e 'const d=require(process.argv[1]);const c=d.classPath;if(Array.isArray(c))c.forEach(x=>console.log(x));else if(typeof c==="string")console.log(c);' "$hj" 2>/dev/null)"
        if [ -n "$cp" ]; then
            while IFS= read -r rel; do
                [ -n "$rel" ] && [ -d "$proj/$rel" ] && printf '%s\n' "$proj/$rel"
            done <<< "$cp"
            return 0
        fi
    fi
    [ -d "$cp" ] && printf '%s\n' "$cp"
}


collect_roots() {
    local f="$1" depth="$2" top="${3:-}" line lineno ref base line_t macro_rest inc_pkg pat
    [ -n "$top" ] || top="$f"
    if [ ! -f "$f" ]; then
        c_fail "FAIL: missing file: $f"
        return 0
    fi
    case " $INCLUDE_STACK " in
        *" $f "*) c_fail "FAIL: hxml include cycle at $f"; return 0 ;;
    esac
    if [ "$depth" -gt 8 ]; then
        c_fail "FAIL: hxml include depth exceeded at $f"
        return 0
    fi
    INCLUDE_STACK="$INCLUDE_STACK $f"
    lineno=0
    while IFS= read -r line || [ -n "$line" ]; do
        lineno=$((lineno + 1))
        # haxe 4.3.7 trims surrounding whitespace (space/tab) and a trailing
        # CR on hxml lines (measured, evidence/05-*); classify the trimmed
        # line so such lines are roots here, never silently dropped.
        line_t="${line#"${line%%[![:space:]]*}"}"
        line_t="${line_t%"${line_t##*[![:space:]]}"}"
        case "$line_t" in
            ''|'#'*|';'*) continue ;;
            -main|--main)
                c_fail "FAIL: $f:$lineno: '$line_t' without a module argument"; continue ;;
            -main[[:space:]]*|--main[[:space:]]*)
                ref="$(printf '%s' "$line_t" | sed 's/^-\{1,2\}main[[:space:]]*//; s/[[:space:]]*$//')"
                case "$ref" in
                    '') c_fail "FAIL: $f:$lineno: -main without a module argument" ;;
                    *[[:space:]]*) c_fail "FAIL: $f:$lineno: -main with multiple tokens: $line_t (haxe rejects multi-token argument lines)" ;;
                    *[!A-Za-z0-9_.]*|[!A-Za-z_]*) c_fail "FAIL: $f:$lineno: malformed -main module path: $ref" ;;
                    *) printf '%s\t%s\t%s\n' "$ref" "$(basename "$f")" "$lineno" ;;
                esac
                continue ;;
            -cp|--cp|-cp[[:space:]]*|--cp[[:space:]]*)
                ref="$(printf '%s' "$line_t" | sed 's/^-\{1,2\}cp[[:space:]]*//; s/[[:space:]]*$//')"
                if [ -z "$ref" ]; then
                    c_fail "FAIL: $f:$lineno: -cp without a directory"
                else
                    for base in "$repo" "$examples" "$(dirname "$f")" "$PWD"; do
                        note_cp_for "$top" "$base/$ref"
                    done
                    case "$ref" in /*) note_cp_for "$top" "$ref" ;; esac
                fi
                continue ;;
            -lib|--lib|-lib[[:space:]]*|--lib[[:space:]]*)
                ref="$(printf '%s' "$line_t" | sed 's/^-\{1,2\}lib[[:space:]]*//; s/[[:space:]]*$//')"
                if [ -z "$ref" ]; then
                    c_fail "FAIL: $f:$lineno: -lib without a library name"
                else
                    while IFS= read -r cpdir; do
                        note_cp_for "$top" "$cpdir"
                    done < <(lib_classpath "$ref")
                fi
                continue ;;
            --macro*|-macro*)
                # include('X') / haxe.macro.Compiler.include('X) arguments are
                # recorded for the per-file reject check (measured semantics,
                # header (iv)): a package-directory argument makes haxe
                # reject the file; every other argument is a silent no-op
                # and contributes no roots.  Every other --macro line is out
                # of scope by design (header (1)).
                macro_rest="${line_t#*macro}"
                macro_rest="${macro_rest#"${macro_rest%%[![:space:]]*}"}"
                inc_pkg=""
                for pat in \
                    "haxe\.macro\.Compiler\.include\('([^']+)'\)" \
                    'haxe\.macro\.Compiler\.include\("([^"]+)"\)' \
                    "include\('([^']+)'\)" \
                    'include\("([^"]+)"\)'
                do
                    if [[ "$macro_rest" =~ ^[[:space:]]*$pat[[:space:]]*$ ]]; then
                        inc_pkg="${BASH_REMATCH[1]}"
                        break
                    fi
                done
                if [ -n "$inc_pkg" ]; then
                    case $'\n'"${INCLUDE_ARGS[$top]:-}"$'\n' in
                        *$'\n'"$inc_pkg"$'\n'*) : ;;
                        *) INCLUDE_ARGS["$top"]="${INCLUDE_ARGS[$top]:-}${INCLUDE_ARGS[$top]:+$'\n'}$inc_pkg" ;;
                    esac
                fi

                continue ;;
            -*|+*) continue ;;
        esac
        case "$line_t" in
            *.hxml)
                ref=""
                for base in "$(dirname "$f")" "$examples" "$repo" "$PWD"; do
                    if [ -f "$base/$line_t" ]; then ref="$base/$line_t"; break; fi
                done
                if [ -z "$ref" ]; then
                    c_fail "FAIL: $f:$lineno: unresolved hxml include: $line_t"
                else
                    collect_roots "$ref" $((depth + 1)) "$top"
                fi
                continue ;;
        esac
        # A bare argument line: haxe takes the WHOLE trimmed line as one
        # argument, so anything but a single module token is rejected
        # (measured: "Could not process argument ... Invalid character").
        if [[ "$line_t" =~ ^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$ ]]; then
            printf '%s\t%s\t%s\n' "$line_t" "$f" "$lineno"
        elif [[ "$line_t" =~ ^[A-Za-z_][A-Za-z0-9_.]*$ ]]; then
            c_fail "FAIL: $f:$lineno: malformed root module path: $line_t"
        elif [[ "$line_t" =~ [[:space:]] ]] || [[ "$line_t" == *'#'* ]]; then
            c_fail "FAIL: $f:$lineno: malformed hxml argument line (multi-token or inline '#' not honoured by haxe; the whole argument is rejected): $line_t"
        else
            c_fail "FAIL: $f:$lineno: unrecognised hxml line (not a flag, an include, or a module path): $line_t"
        fi
    done < "$f"
    INCLUDE_STACK="${INCLUDE_STACK% "$f"}"
}

# include() reject check (measured semantics, header (iv)): for top-level
# file $1, each --macro include('X') argument that names a package
# directory on the file's own classpath (a dir $d/X with no module file
# $d/X.hx) makes haxe reject the file with "Invalid commandline class :
# X.Y should be Y"; fail the file the same way.  Every other argument is a
# measured silent no-op (rc=0, no root contributed) and emits nothing.
include_reject_check() {
    local top="$1" args="${INCLUDE_ARGS[$1]:-}" X d
    [ -n "$args" ] || return 0
    while IFS= read -r X; do
        [ -n "$X" ] || continue
        for d in ${FILE_CP[$top]:-}; do
            [ -d "$d/$X" ] && [ ! -f "$d/$X.hx" ] && {
                echo "FAIL: $(basename "$top"): --macro include('$X'): argument names a package directory ($d/$X) rather than a module; haxe 4.3.7 rejects this file (measured: \"Invalid commandline class : ${X}.* should be *\", rc=1) and compiles nothing; name the module instead, or drop the include"
                fail=1
                break
            }
        done
    done <<< "$args"
}


# Build a sorted index of module names provided by the cp dirs listed (one
# per line) in $1, written to $2.
make_cp_index() {
    local d rel hx out="$2"
    : > "$out"
    while IFS= read -r d; do
        [ -n "$d" ] && [ -d "$d" ] || continue
        while IFS= read -r hx; do
            rel="${hx#"$d"/}"
            rel="${rel%.hx}"
            printf '%s\n' "${rel//\//.}"
        done < <(find "$d" -type f -name '*.hx' | sort) >> "$out"
    done < "$1"
    sort -u "$out" -o "$out"
}

# ------------------------------------------------------------------ prescan --
# Populate the global classpath union (and per-file sets) before coverage.
for t in kotlin rust swift; do
    for suff in "" "-f32"; do
        f="$examples/$t$suff.hxml"
        if [ -f "$f" ]; then
            C_QUIET=1
            collect_roots "$f" 0 "$f" > /dev/null
            C_QUIET=0
        fi
    done
done


# --------------------------------------------------------------- resolution --
# Union of all guarded classpaths (index) + repo-wide fallback.  Used for
# allowlist/root-floor modules only.
make_cp_index <(printf '%s\n' ${CP_ALL[@]+"${CP_ALL[@]}"}) "$tmpd/idx.all"

# Repo-wide fallback index: every .hx under the repo (skipping installed
# libraries, dependencies, and build output) as dotted module names.
# Built once; membership is a single grep, not a per-module find.
find "$repo" -path "$repo/.haxelib" -prune -o -path "$repo/node_modules" -prune \
    -o -type f -name '*.hx' -print 2>/dev/null |
while IFS= read -r hx; do
    rel="${hx#"$repo"/}"
    rel="${rel%.hx}"
    printf '%s\n' "${rel//\//.}"
done | sort -u > "$tmpd/idx.fallback"
declare -A RESOLVED=()
RESOLVED_PATH=""
resolve_module() {
    local m="$1"
    if [ -n "${RESOLVED[$m]:-}" ]; then RESOLVED_PATH="${RESOLVED[$m]}"; return 0; fi
    if grep -qx -- "$m" "$tmpd/idx.all"; then
        RESOLVED["$m"]=1
        RESOLVED_PATH=""
        return 0
    fi
    if grep -qx -- "$m" "$tmpd/idx.fallback"; then
        RESOLVED["$m"]=fallback
        RESOLVED_PATH=""
        return 0
    fi
    return 1
}

# --print-baseline: emit the current root floor and stop.
if [ "$print_baseline" -eq 1 ]; then
    : > "$tmpd/pb.out"
    for t in kotlin rust swift; do
        b="$examples/$t.hxml"
        f="$examples/$t-f32.hxml"
        : > "$tmpd/pb.$t.base"
        : > "$tmpd/pb.$t.f32"
        collect_roots "$b" 0 "$b" > "$tmpd/pb.$t.base"
        collect_roots "$f" 0 "$f" > "$tmpd/pb.$t.f32"

        cat "$tmpd/pb.$t.base" "$tmpd/pb.$t.f32" | cut -f1 | sort -u | while IFS= read -r m; do
            [ -n "$m" ] && printf '%s\t%s\n' "$t" "$m"
        done >> "$tmpd/pb.out"
    done
    if [ "$fail" -ne 0 ]; then
        echo "FAIL: refusing to print a root-floor baseline: the tree does not parse cleanly (see diagnostics above)"
        echo "roots guard: FAILED"
        exit 1
    fi
    cat "$tmpd/pb.out"
    exit 0
fi

# @:test coverage scan: every .hx under a tests/ directory of a guarded
# classpath that declares @:test, keyed by module path relative to that
# classpath dir (so <cp>/tests/Foo.hx is module tests.Foo).  Built once,
# after the prescan populated the classpath union.
declare -A SCAN_MODULES=()
scan_found=0
for d in ${CP_ALL[@]+"${CP_ALL[@]}"}; do
    tdir="$d/tests"
    [ -d "$tdir" ] || continue
    scan_found=1
    while IFS= read -r f; do
        grep -q '@:test' "$f" 2>/dev/null || continue
        rel="${f#"$d"/}"
        rel="${rel%.hx}"
        SCAN_MODULES["${rel//\//.}"]="$f"
    done < <(find "$tdir" -type f -name '*.hx' | sort)
done
if [ "$scan_found" -eq 0 ]; then
    echo "FAIL: no tests/ directory found under any guarded classpath (checked: ${CP_ALL[*]:-none}); the @:test coverage check cannot run"
    fail=1
fi
mapfile -t SCAN_MOD_LIST < <(printf '%s\n' ${SCAN_MODULES[@]+"${!SCAN_MODULES[@]}"} | sort)

declare -A EX_USED=() UN_USED=()
# ------------------------------------------------------------- per target ---
# The global union is only used for allowlist/floor module existence and for
# the coverage scan; the per-target checks below work per file.
R_ANY=0
while IFS= read -r d; do
    [ -n "$d" ] && [ -d "$d/tests" ] && R_ANY=1
done < <(printf '%s\n' ${CP_ALL[@]+"${CP_ALL[@]}"})

for target in kotlin rust swift; do
    base="$examples/$target.hxml"
    f32="$examples/$target-f32.hxml"
    ok=1
    for f in "$base" "$f32"; do
        if [ ! -f "$f" ]; then
            echo "FAIL: missing file: $f"
            fail=1
            ok=0
        fi
    done
    [ "$ok" -eq 1 ] || continue
    base_name="$(basename "$base")"
    f32_name="$(basename "$f32")"

    : > "$tmpd/roots.base"
    : > "$tmpd/roots.f32"
    C_QUIET=0
    collect_roots "$base" 0 "$base" > "$tmpd/roots.base"
    collect_roots "$f32" 0 "$f32" > "$tmpd/roots.f32"
    # (1-iv) include() reject check, per file (needs the per-file cp sets)
    include_reject_check "$base"
    include_reject_check "$f32"


    # (3) per-file classpath existence, strict (no repo-wide fallback)
    printf '%s\n' ${FILE_CP[$base]:-} | sort -u > "$tmpd/cp.base"
    printf '%s\n' ${FILE_CP[$f32]:-} | sort -u > "$tmpd/cp.f32"
    make_cp_index "$tmpd/cp.base" "$tmpd/idx.base"
    make_cp_index "$tmpd/cp.f32" "$tmpd/idx.f32"
    for side in base f32; do
        if [ "$side" = "base" ]; then rname="$(basename "$base")"; else rname="$f32_name"; fi
        rf="$tmpd/roots.$side"
        idx="$tmpd/idx.$side"
        comm -23 <(cut -f1 "$rf" | sort -u) "$idx" > "$tmpd/missing.$side"
        while IFS= read -r mod; do
            [ -n "$mod" ] || continue
            at="$(awk -F'\t' -v m="$mod" '$1 == m { print $2 ":" $3; exit }' "$rf")"
            echo "FAIL: $rname:$at root module $mod does not resolve to any .hx on the classpath $rname itself declares (its -cp/-lib lines and those of its includes); add the missing -cp/-lib line to $rname"
            fail=1
        done < "$tmpd/missing.$side"
    done

    # (dup) duplicate root lines inside one pair
    for side in base f32; do
        rf="$tmpd/roots.$side"
        if [ "$side" = "base" ]; then rname="$base_name"; else rname="$f32_name"; fi
        dups="$(cut -f1 "$rf" | sort | uniq -d)"
        if [ -n "$dups" ]; then
            while IFS= read -r mod; do
                [ -n "$mod" ] || continue
                at="$(awk -F'\t' -v m="$mod" '$1 == m { print $2 ":" $3; exit }' "$rf")"
                echo "DUP: $rname:$at module $mod appears on multiple root lines in this pair"
                dup_lines=$((dup_lines + 1))
            done <<< "$dups"
        fi
    done
    if [ "$strict_dups" -eq 1 ] && [ "$dup_lines" -gt 0 ]; then
        echo "FAIL: $dup_lines duplicate root line(s) in the $target pair (strict-duplicates)"
        fail=1
    fi

    # (1) root-set equality, both directions
    cut -f1 "$tmpd/roots.base" | sort -u > "$tmpd/set.base"
    cut -f1 "$tmpd/roots.f32" | sort -u > "$tmpd/set.f32"
    comm -23 "$tmpd/set.base" "$tmpd/set.f32" > "$tmpd/only.base"
    comm -13 "$tmpd/set.base" "$tmpd/set.f32" > "$tmpd/only.f32"

    # EX_USED is per-target (checked within the iteration); UN_USED
    # accumulates across targets (checked after the loop).
    EX_USED=()
    while IFS= read -r mod; do
        [ -n "$mod" ] || continue
        at="$(awk -F'\t' -v m="$mod" '$1 == m { print $2 ":" $3; exit }' "$tmpd/roots.base")"
        key="$target|$mod"
        if [ -n "${ex_reason[$key]:-}" ]; then
            exemptions=$((exemptions + 1))
            EX_USED["$key"]=1
            echo "EXEMPT: $f32_name omits root module $mod (base-only, at $at); declared in allowlist: ${ex_reason[$key]}"
        else
            echo "FAIL: $f32_name omits root module $mod (present in $base_name at $at); the f32 bundle would lose a root that the base bundle compiles"
            fail=1
        fi
    done < "$tmpd/only.base"
    while IFS= read -r mod; do
        [ -n "$mod" ] || continue
        at="$(awk -F'\t' -v m="$mod" '$1 == m { print $2 ":" $3; exit }' "$tmpd/roots.f32")"
        key="$target|$mod"
        if [ -n "${ex_reason[$key]:-}" ]; then
            exemptions=$((exemptions + 1))
            EX_USED["$key"]=1
            echo "EXEMPT: $base_name omits root module $mod (f32-only, at $at); declared in allowlist: ${ex_reason[$key]}"
        else
            echo "FAIL: $base_name omits root module $mod (present in $f32_name at $at); the base bundle would compile a root the f32 bundle does not"
            fail=1
        fi
    done < "$tmpd/only.f32"

    # (5) root floor: every pinned module must still be rooted in at least
    # one of the pair's files (a root deleted from BOTH files is invisible
    # to (1), which compares the two files against each other).
    for fl in ${FLOOR_MODULES[@]+"${FLOOR_MODULES[@]}"}; do
        fbt="${fl%%$'\t'*}"
        fbm="${fl#*$'\t'}"
        [ "$fbt" = "$target" ] || continue
        in_base=0
        in_f32=0
        grep -qx -- "$fbm" "$tmpd/set.base" && in_base=1
        grep -qx -- "$fbm" "$tmpd/set.f32" && in_f32=1
        if [ "$in_base" -eq 0 ] && [ "$in_f32" -eq 0 ]; then
            echo "FAIL: root-floor: $fbm is pinned in $baseline (rooted in the $target pair at the last baseline refresh) but is a root of neither $base_name nor $f32_name; a root deleted from BOTH files is invisible to the pair-equality check -- restore it, or refresh the baseline with --print-baseline if the deletion is deliberate"
            fail=1
        fi
    done

    # (4) @:test coverage under guarded classpaths (scan built once above)
    for mod in ${SCAN_MOD_LIST[@]+"${SCAN_MOD_LIST[@]}"}; do
        if grep -qx -- "$mod" "$tmpd/set.base" || grep -qx -- "$mod" "$tmpd/set.f32"; then
            continue
        fi
        unmatch=""
        for k in ${un_keys[@]+"${un_keys[@]}"}; do
            kt="${k%%|*}"
            km="${k#*|}"
            if [ "$km" = "$mod" ] && { [ "$kt" = "*" ] || [ "$kt" = "$target" ]; }; then
                unmatch="$k"
                break
            fi
        done
        if [ -n "$unmatch" ]; then
            unrooted_decls=$((unrooted_decls + 1))
            UN_USED["$unmatch"]=1
            echo "UNROOT: $mod declares @:test in ${SCAN_MODULES[$mod]} but is a root of neither $base_name nor $f32_name; declared in allowlist: ${un_reason[$unmatch]}"
        else
            echo "FAIL: $mod declares @:test in ${SCAN_MODULES[$mod]} but is a root of neither $base_name nor $f32_name; an @:test module missing from both files is a regression unless declared in allowlist section unrootedTestModules"
            fail=1
        fi
    done

    # (stale) allowlist entries that no longer describe the tree
    for key in ${ex_keys[@]+"${ex_keys[@]}"}; do
        [ -z "$key" ] && continue
        kt="${key%%|*}"
        km="${key#*|}"
        case "$kt" in
            kotlin|rust|swift) [ "$kt" = "$target" ] || continue ;;
        esac
        if [ -z "${EX_USED[$key]:-}" ]; then
            echo "STALE: allowlist exempts $km for target $kt but the module is not asymmetric for it now (present in both files, or absent from both); drop the entry"
            fail=1
        fi
    done
done

# (stale) unrootedTestModules entries that no longer describe the tree
for key in ${un_keys[@]+"${un_keys[@]}"}; do
    [ -z "$key" ] && continue
    kt="${key%%|*}"
    km="${key#*|}"
    if [ -z "${UN_USED[$key]:-}" ]; then
        echo "STALE: allowlist declares $km unrooted for target $kt but no such unrooted @:test module exists now; drop the entry"
        fail=1
    fi
done

# Existence of every module named by the allowlist or the root floor
# (union of all guarded classpaths + repo-wide fallback).
declare -A CHECKMOD=()
for key in ${ex_keys[@]+"${ex_keys[@]}"}; do
    [ -z "$key" ] && continue
    CHECKMOD["${key#*|}"]=1
done
for key in ${un_keys[@]+"${un_keys[@]}"}; do
    [ -z "$key" ] && continue
    CHECKMOD["${key#*|}"]=1
done
for fl in ${FLOOR_MODULES[@]+"${FLOOR_MODULES[@]}"}; do
    CHECKMOD["${fl#*$'\t'}"]=1
done
for m in ${CHECKMOD[@]+"${!CHECKMOD[@]}"}; do
    if ! resolve_module "$m"; then
        echo "FAIL: allowlist/root-floor module $m does not resolve to any .hx on the guarded classpaths or anywhere under $repo"
        fail=1
    fi
done

if [ "$dup_lines" -gt 0 ]; then
    echo "SUMMARY: $dup_lines duplicate root line(s) reported above (non-fatal; --strict-duplicates makes them fatal)"
fi
if [ "$fail" -ne 0 ]; then
    echo "roots guard: FAILED"
    exit 1
fi
echo "roots guard: PASS ($exemptions exemption(s) in force; $unrooted_decls declared unrooted @:test module(s); $dup_lines duplicate root line(s) reported; $floor_pins pinned root(s) in root-floor)"
exit 0
