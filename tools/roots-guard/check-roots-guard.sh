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
#      A module present in B and missing from F ("base-only") and a module
#      present in F and missing from B ("f32-only") are both reported, and
#      either one fails the guard.
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

#  (2) DECLARED TARGET-ONLY ROOTS (there is no allowlist).  A roots file may
#      declare a root that legitimately exists on only one side of the
#      precision switch, or on only some targets.  The declaration is a fixed
#      comment line in the roots file of the bundle(s) it describes:
#
#        # @only-in: precision:binary64 registry.Main
#        # @only-in: target:rust tests.EscapingTraitIdentityTests
#        # @dormant: rust tests.E0308FiTests
#
#      `@only-in: precision:<binary64|f32>` states that only bundles of that
#      precision root the module (the plain pair files and the non-f32
#      examples are binary64; `*-f32` files and the f32 haxe bundle are f32).
#      `@only-in: target:<kotlin|rust|swift>` states that only that target's
#      bundles root it.  `@dormant: <target>` states that the module declares
#      @:test, its body is wrapped in `#if <target>_output`, and no bundle
#      roots it today (a probe that compiles nowhere; the guard fails if the
#      body stops being fully wrapped by that define, or if any bundle starts
#      rooting it -- drop the marker then, a dormant module must not silently
#      become a permanent exemption).
#
#      Every declaration is a CLAIM ABOUT THE TREE and is verified against it,
#      so a marker is never a free pass: the module must resolve to a real .hx;
#      at least one bundle on the declared side must root it -- through a root
#      line of that bundle's roots file, or through a TestCollector generate()
#      scan directory that file declares -- and NO bundle outside the declared
#      side may root it (a `precision:binary64` module rooted by an f32 bundle
#      fails; a `target:rust` module rooted by kotlin fails).  A marker must
#      sit in a bundle's own rootsFile, never in a file that rootsFile
#      includes, so the guard and the consistency check read the same lines.
#      Declarations are read from the `rootsFile` of every bundle in
#      `boring.json`, so the guard and the bundle driver read the same files;
#      a missing boring.json or bundle roots file is a FAIL, so no check is
#      ever silently disabled.
#
#      EFFECT ON (1) AND (4).  A base-only asymmetry is authorised only by a
#      verified `precision:binary64` declaration (f32-only by
#      `precision:f32`); a target-side declaration never authorises a pair
#      asymmetry.  An unrooted @:test module passes (4) only with a verified
#      declaration of either kind.  Nothing is declared away without the tree
#      checks above, and the PASS line reports those verified counts: there is
#      no per-target exemption list left to grow.
#  (3) ROOT EXISTENCE, PER FILE.  Every root of a file must resolve to a
#      real .hx on the classpath THAT FILE declares: its own -cp/-lib lines
#      plus the -cp/-lib lines of the .hxml files it includes.  A root that
#      only another file's classpath provides fails -- classpath sets are
#      checked per file, with no unioning (removing `-cp samples` from one f32
#      file is a failure).  No repo-wide fallback applies to file roots.
#      Modules named by the root floor (and by a (2) declaration) are
#      resolved against the union of all guarded classpaths, with a
#      repo-wide .hx fallback; for those, existence is still not
#      compilability (a module no single file's classpath provides can
#      still pass if the union or the fallback sees it).
#  (4) TEST-MODULE COVERAGE.  Every .hx under a `tests/` directory of a
#      guarded classpath (the union of all six files' classpaths) that
#      declares `@:test` must be a root of at least one of B/F.  A test
#      module missing from BOTH files used to be invisible; it now fails
#      unless a verified (2) declaration covers it (either @only-in kind,
#      or @dormant -- and, when it was rooted at the last baseline
#      refresh, still caught by (5)).
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
#   * side effects of non-include `--macro` lines and of all other flag lines
#     (see (1)); `--next`/`--each` multi-compilation files are flattened into
#     one root set;
#   * @:test modules outside a <guarded-classpath>/tests directory, including
#     any under the repository-root tests/ (coverage scans the guarded
#     classpaths' tests/ directories only);
#   * compilability of root-floor/declared modules beyond existence (see (3));
#   * test ids, @:test case sets, module bodies, runtime behaviour under
#     binary32/binary64.  This guard reads the (2) declarations only at the
#     module level; the cross-target consistency check
#     (packages/driver/src/driver/Compare.hx) reads the same @only-in markers
#     to authorise the extra ids those modules produce;
#   * dart/ts pairs are not guarded (no -f32 variant);
#   * bypass routes: --repo-root / ROOTS_GUARD_REPO_ROOT redirect what is
#     checked, so a PASS is only as strong as the tree it ran on.
#
# Usage: check-roots-guard.sh [examples-dir] [--repo-root=PATH]
#                       [--strict-duplicates] [--print-baseline]
#
#   examples-dir        default: <script>/../../examples
#   --repo-root=PATH    repository root used for module-source resolution
#                       (also honoured: ROOTS_GUARD_REPO_ROOT).  If discovery
#                       fails the guard FAILS.
#   --strict-duplicates fail on duplicate root lines (see above)
#   --print-baseline    print the current root floor (one `target<TAB>module`
#                       line per module of the union of each pair's root
#                       sets) and exit; use it to refresh
#                       roots-baseline.txt after a deliberate root change.
#
# The (2) declarations are read from the `rootsFile` of every bundle in
# `<repo>/boring.json`; a missing project file or bundle roots file is a
# FAIL, never a silently disabled check.
#
# Environment:
#   ROOTS_GUARD_REPO_ROOT   repository root (same as --repo-root=PATH)
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
unrooted_decls=0
declared_asym=0
declared_onlyin=0
declared_dormant=0
dup_lines=0
floor_pins=0

tmpd="$(mktemp -d "${TMPDIR:-/tmp}/roots-guard.XXXXXX")"
trap 'rm -rf "$tmpd"' EXIT

# --------------------------------------------- target-only declarations (2) --
# The declarations are fixed comment markers in the roots files (see the
# header).  Every one is a CLAIM ABOUT THE TREE: the module must be rooted on
# the declared side and by nothing outside it, so no check below treats a
# marker as a free pass.
project="$repo/boring.json"
if [ ! -f "$project" ]; then
    echo "FAIL: bundle project file not found: $project; the target-only declarations are read from the rootsFile entries of its bundles"
    echo "roots guard: FAILED"
    exit 1
fi
node -e '
const fs = require("fs");
const raw = fs.readFileSync(process.argv[1], "utf8").split("\n").filter(function (line) {
    const text = line.trim();
    return !(text.length > 1 && text[0] === "/" && text[1] === "/");
}).join("\n");
let doc;
try { doc = JSON.parse(raw); }
catch (error) { console.log("FAIL: boring.json is not valid JSON: " + error.message); process.exit(1); }
const bundles = doc && Array.isArray(doc.bundles) ? doc.bundles : null;
if (bundles === null) { console.log("FAIL: boring.json has no bundles array"); process.exit(1); }
for (const bundle of bundles) {
    if (bundle === null || typeof bundle !== "object") { console.log("FAIL: boring.json has a non-object bundle"); process.exit(1); }
    const id = typeof bundle.id === "string" ? bundle.id : "";
    if (!id) { console.log("FAIL: boring.json has a bundle without an id"); process.exit(1); }
    const roots = typeof bundle.rootsFile === "string" ? bundle.rootsFile : "";
    const target = typeof bundle.target === "string" ? bundle.target : "";
    const precision = typeof bundle.precision === "string" ? bundle.precision : "binary64";
    console.log([id, roots, target, precision].join("|"));
}
' "$project" > "$tmpd/bundles.txt"
if [ $? -ne 0 ]; then
    echo "roots guard: FAILED"
    exit 1
fi

declare -A B_ROOTS_FILE=() B_TARGET=() B_PRECISION=() BUNDLE_ROOTS_FILE=()
declare -A OI_SCOPE=() OI_AT=() DORMANT=() DORM_AT=()
declare -a MARK_MODS=()

# marker_collect <bundle> <roots-file> <depth> -- emit pipe-separated records:
#   ROOT|<module>                     a module the bundle roots
#   SCAN|<dir>                        a TestCollector.generate() scan directory
#   ONLYIN|<module>|<scope>|<file>    an @only-in declaration
#   DORMANT|<module>|<target>|<file>  an @dormant declaration
#   ERR|<message>                     an unreadable/unresolvable roots file
marker_collect() {
    local bundle="$1" f="$2" depth="$3" line line_t rest kind scan rel base
    [ -n "$f" ] || return 0
    if [ ! -f "$f" ]; then
        echo "ERR|bundle $bundle: roots file not found: $f"
        return 0
    fi
    if [ "$depth" -gt 8 ]; then
        echo "ERR|bundle $bundle: roots file include depth exceeded at $f"
        return 0
    fi
    rel="$f"
    case "$rel" in "$repo"/*) rel="${rel#"$repo"/}" ;; esac
    while IFS= read -r line || [ -n "$line" ]; do
        line_t="${line#"${line%%[![:space:]]*}"}"
        line_t="${line_t%"${line_t##*[![:space:]]}"}"
        case "$line_t" in
            ''|';'*)
                continue ;;
            '#'*)
                case "$line_t" in
                    '# @only-in:'*)
                        rest="${line_t#'# @only-in:'}"
                        rest="${rest#"${rest%%[![:space:]]*}"}"
                        kind="${rest%%[[:space:]]*}"
                        rest="${rest#"$kind"}"
                        rest="${rest#"${rest%%[![:space:]]*}"}"
                        echo "ONLYIN|$rest|$kind|$rel"
                        ;;
                    '# @dormant:'*)
                        rest="${line_t#'# @dormant:'}"
                        rest="${rest#"${rest%%[![:space:]]*}"}"
                        kind="${rest%%[[:space:]]*}"
                        rest="${rest#"$kind"}"
                        rest="${rest#"${rest%%[![:space:]]*}"}"
                        echo "DORMANT|$rest|$kind|$rel"
                        ;;
                esac
                continue ;;
        esac
        case "$line_t" in
            -main[[:space:]]*|--main[[:space:]]*)
                rest="$line_t"
                rest="${rest#-}"
                rest="${rest#-}"
                rest="${rest#main}"
                rest="${rest#"${rest%%[![:space:]]*}"}"
                rest="${rest%"${rest##*[![:space:]]}"}"
                case "$rest" in
                    ''|*[[:space:]]*) : ;;
                    *) echo "ROOT|$rest" ;;
                esac
                continue ;;
        esac
        case "$line_t" in
            --macro*|-macro*)
                case "$line_t" in
                    *TestCollector.generate*)
                        case "$line_t" in
                            *"["*"]"*)
                                rest="${line_t#*[}"
                                rest="${rest%%]*}"
                                while IFS= read -r scan; do
                                    scan="${scan#"${scan%%[![:space:]]*}"}"
                                    scan="${scan%"${scan##*[![:space:]]}"}"
                                    scan="$(echo "$scan" | tr -d "'" | tr -d '"')"
                                    scan="${scan#"${scan%%[![:space:]]*}"}"
                                    scan="${scan%"${scan##*[![:space:]]}"}"
                                    [ -n "$scan" ] && echo "SCAN|$scan"
                                done <<< "$(echo "$rest" | tr "," "\n")"
                                ;;
                        esac ;;
                esac
                continue ;;
        esac
        case "$line_t" in
            *.hxml)
                for base in "$(dirname "$f")" "$examples" "$repo" "$PWD"; do
                    if [ -f "$base/$line_t" ]; then
                        marker_collect "$bundle" "$base/$line_t" $((depth + 1))
                        break
                    fi
                done
                continue ;;
        esac
        case "$line_t" in
            -*|+*) continue ;;
        esac
        if [[ "$line_t" =~ ^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$ ]]; then
            echo "ROOT|$line_t"
        fi
    done < "$f"
}

while IFS='|' read -r bid rfile btarget bprec; do
    [ -n "$bid" ] || continue
    B_TARGET["$bid"]="$btarget"
    B_PRECISION["$bid"]="$bprec"
    if [ -z "$rfile" ]; then
        echo "FAIL: boring.json bundle $bid declares no rootsFile; the target-only declarations cannot be located"
        fail=1
        continue
    fi
    B_ROOTS_FILE["$bid"]="$rfile"
    BUNDLE_ROOTS_FILE["$rfile"]=1
    : > "$tmpd/bundle.$bid.roots"
    : > "$tmpd/bundle.$bid.scan"
    rf="$rfile"
    case "$rf" in /*) : ;; *) rf="$repo/$rfile" ;; esac
    stream="$tmpd/bundle.$bid.stream"
    marker_collect "$bid" "$rf" 0 > "$stream"
    while IFS='|' read -r kind a b c; do
        case "$kind" in
            ROOT)
                echo "$a" >> "$tmpd/bundle.$bid.roots" ;;
            SCAN)
                echo "$a" >> "$tmpd/bundle.$bid.scan" ;;
            ONLYIN)
                if [ -n "${OI_SCOPE[$a]:-}" ] && [ "${OI_SCOPE[$a]}" != "$b" ]; then
                    echo "FAIL: conflicting @only-in declarations for $a: '${OI_SCOPE[$a]}' (${OI_AT[$a]}) and '$b' ($c)"
                    fail=1
                else
                    OI_SCOPE["$a"]="$b"
                    OI_AT["$a"]="$c"
                fi ;;
            DORMANT)
                if [ -n "${DORMANT[$a]:-}" ] && [ "${DORMANT[$a]}" != "$b" ]; then
                    echo "FAIL: conflicting @dormant declarations for $a: '${DORMANT[$a]}' (${DORM_AT[$a]}) and '$b' ($c)"
                    fail=1
                else
                    DORMANT["$a"]="$b"
                    DORM_AT["$a"]="$c"
                fi ;;
            ERR)
                echo "FAIL: $a"
                fail=1 ;;
        esac
    done < "$stream"
done < "$tmpd/bundles.txt"

MARK_MODS=()
for decl_module in "${!OI_SCOPE[@]}" "${!DORMANT[@]}"; do
    MARK_MODS+=("$decl_module")
done
if [ "${#MARK_MODS[@]}" -gt 1 ]; then
    mapfile -t MARK_MODS < <(printf "%s\n" "${MARK_MODS[@]}" | sort -u)
fi
for mod in ${MARK_MODS[@]+"${MARK_MODS[@]}"}; do
    [ -n "$mod" ] || continue
    if [[ ! "$mod" =~ ^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$ ]]; then
        echo "FAIL: declaration names a malformed module path: $mod"
        fail=1
        continue
    fi
    if [ -n "${OI_SCOPE[$mod]:-}" ] && [ -n "${DORMANT[$mod]:-}" ]; then
        echo "FAIL: $mod carries both an @only-in and an @dormant declaration (${OI_AT[$mod]}, ${DORM_AT[$mod]}); keep exactly one"
        fail=1
    fi
    scope="${OI_SCOPE[$mod]:-}"
    case "$scope" in
        '') : ;;
        precision:binary64|precision:f32) : ;;
        target:kotlin|target:rust|target:swift) : ;;
        *) echo "FAIL: $mod: @only-in scope must be precision:binary64, precision:f32, target:kotlin, target:rust or target:swift (got '$scope' in ${OI_AT[$mod]})"
           fail=1 ;;
    esac
    dormant="${DORMANT[$mod]:-}"
    case "$dormant" in
        '') : ;;
        kotlin|rust|swift) : ;;
        *) echo "FAIL: $mod: @dormant target must be kotlin, rust or swift (got '$dormant' in ${DORM_AT[$mod]})"
           fail=1 ;;
    esac
done
if [ "$fail" -ne 0 ]; then
    echo "roots guard: FAILED"
    exit 1
fi

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

# note_cp_for: record a classpath dir for the global union (root-floor and
# declaration existence, coverage) AND for the top-level file it came from
# (per-file existence check).  $1 = top file, $2 = dir (relative or absolute).
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
    # F9 (Claude review): .current/.dev are haxelib install pointers, git-ignored and absent from
    # clean exports; a clean checkout falls through to the repo-as-library
    # branch below (PIT-399).
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
    elif [ -f "$repo/haxelib.json" ] && command -v node >/dev/null 2>&1 \
         && [ "$(node -e 'try{console.log(require(process.argv[1]).name||"")}catch(e){console.log("")}' "$repo/haxelib.json" 2>/dev/null)" = "$lib" ]; then
        # The checked-out tree may BE the library itself (this repository
        # is the boring haxelib; haxe resolves `-lib boring` through a
        # .haxelib/boring/.dev pointer, which is git-ignored and therefore
        # absent from clean exports such as `git archive` trees).  When no
        # dev/current pointer exists but the repo's own haxelib.json names
        # this library, contribute the repo's own classPath: that is what
        # haxe sees for a source checkout of the package, and it keeps the
        # guard's verdict independent of unversioned local state (PIT-399).
        proj="$repo"
        hj="$repo/haxelib.json"
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
# root-floor modules only.
make_cp_index <(printf '%s\n' ${CP_ALL[@]+"${CP_ALL[@]}"}) "$tmpd/idx.all"

# F9 (Claude review): fallback index switches to git ls-files '*.hx'.
# Repo-wide fallback index: every tracked .hx under the repo (git ls-files, so
# untracked build output and local junk are excluded) as dotted module names.
# Built once; membership is a single grep.
git -C "$repo" ls-files '*.hx' |
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

# ------------------------------------- declaration verification (2) --------
# A declaration is honoured only when the tree agrees with it: the module
# resolves, every bundle on the declared side roots it, and no bundle outside
# the declared side roots it.
module_path() {
    local m="$1" rel d
    rel="${m//.//}.hx"
    for d in ${CP_ALL[@]+"${CP_ALL[@]}"}; do
        if [ -f "$d/$rel" ]; then
            printf '%s\n' "$d/$rel"
            return 0
        fi
    done
    if [ -f "$repo/$rel" ]; then
        printf '%s\n' "$repo/$rel"
        return 0
    fi
    return 1
}

bundle_roots_module() {
    local bid="$1" mod="$2" mp d scan
    if grep -qxF -- "$mod" "$tmpd/bundle.$bid.roots" 2>/dev/null; then
        return 0
    fi
    [ -s "$tmpd/bundle.$bid.scan" ] || return 1
    mp="$(module_path "$mod")" || return 1
    while IFS= read -r scan; do
        [ -n "$scan" ] || continue
        for d in "$repo/$scan" "$(dirname "$repo/${B_ROOTS_FILE[$bid]:-}")/$scan"; do
            [ -d "$d" ] || continue
            d="$(cd "$d" && pwd)"
            case "$mp" in "$d"/*) return 0 ;; esac
        done
    done < "$tmpd/bundle.$bid.scan"
    return 1
}

declare -A VERIFIED=()
for mod in ${MARK_MODS[@]+"${MARK_MODS[@]}"}; do
    [ -n "$mod" ] || continue
    if ! src="$(module_path "$mod")"; then
        echo "FAIL: declaration for $mod does not resolve to any .hx on the guarded classpaths or anywhere under $repo"
        fail=1
        continue
    fi
    where="${OI_AT[$mod]:-${DORM_AT[$mod]:-}}"
    if [ -z "${BUNDLE_ROOTS_FILE[$where]:-}" ]; then
        echo "FAIL: $mod: the declaration in $where is not a bundle rootsFile; declare it in one of the rootsFile entries of boring.json so the guard and the consistency check read the same line"
        fail=1
        continue
    fi
    rooting=""
    for bid in ${B_TARGET[@]+"${!B_TARGET[@]}"}; do
        if bundle_roots_module "$bid" "$mod"; then
            rooting="$rooting $bid"
        fi
    done
    scope="${OI_SCOPE[$mod]:-}"
    if [ -n "$scope" ]; then
        dim="${scope%%:*}"
        value="${scope#*:}"
        if [ -z "$rooting" ]; then
            echo "FAIL: $mod is declared @only-in: $scope in ${OI_AT[$mod]}, but no bundle roots it; the declaration is stale"
            fail=1
            continue
        fi
        bad=""
        for bid in $rooting; do
            if [ "$dim" = "target" ]; then
                if [ "${B_TARGET[$bid]}" != "$value" ]; then
                    bad="$bad $bid(target ${B_TARGET[$bid]})"
                fi
            else
                if [ "${B_PRECISION[$bid]}" != "$value" ]; then
                    bad="$bad $bid(precision ${B_PRECISION[$bid]})"
                fi
            fi
        done
        if [ -n "$bad" ]; then
            echo "FAIL: $mod is declared @only-in: $scope in ${OI_AT[$mod]}, but it is also rooted by bundle(s):$bad"
            fail=1
            continue
        fi
        VERIFIED["$mod"]="$scope"
        declared_onlyin=$((declared_onlyin + 1))
    else
        dormant="${DORMANT[$mod]}"
        if [ -n "$rooting" ]; then
            echo "FAIL: $mod is declared @dormant: $dormant in ${DORM_AT[$mod]}, but bundle(s):$rooting root it; drop the marker and declare @only-in instead"
            fail=1
            continue
        fi
        if ! grep -q "@:test" "$src" 2>/dev/null; then
            echo "FAIL: $mod is declared @dormant: $dormant in ${DORM_AT[$mod]}, but ${src#"$repo"/} declares no @:test"
            fail=1
            continue
        fi
        # The body must be EXACTLY one top-level conditional block: it opens
        # with "#if <target>_output", that block's "#end" closes it, nothing
        # compiles after the closing "#end", and no top-level "#else"/"#elseif"
        # branch exists (a branch would compile part of the module on another
        # target).  Comment-only lines are ignored.
        shape_first=""
        shape_opens=0
        shape_depth=0
        shape_topelse=0
        shape_after=0
        shape_closed=0
        while IFS= read -r line || [ -n "$line" ]; do
            line="${line#"${line%%[![:space:]]*}"}"
            line="${line%"${line##*[![:space:]]}"}"
            case "$line" in
                ""|"//"*) continue ;;
            esac
            if [ -z "$shape_first" ]; then
                shape_first="$line"
            fi
            case "$line" in
                "#if"|"#if "*)
                    if [ "$shape_depth" -eq 0 ]; then
                        shape_opens=$((shape_opens + 1))
                    fi
                    shape_depth=$((shape_depth + 1))
                    continue ;;
                "#end"|"#end "*)
                    if [ "$shape_depth" -gt 0 ]; then
                        shape_depth=$((shape_depth - 1))
                    fi
                    if [ "$shape_depth" -eq 0 ]; then
                        shape_closed=1
                    fi
                    continue ;;
                "#else"|"#else "*|"#elseif"|"#elseif "*)
                    if [ "$shape_depth" -eq 1 ]; then
                        shape_topelse=1
                    fi
                    continue ;;
            esac
            if [ "$shape_closed" -eq 1 ]; then
                shape_after=1
            fi
        done < "$src"
        if [ "$shape_first" != "#if ${dormant}_output" ]; then
            echo "FAIL: $mod is declared @dormant: $dormant in ${DORM_AT[$mod]}, but its body does not open with '#if ${dormant}_output' (first code line: '$shape_first')"
            fail=1
            continue
        fi
        if [ "$shape_opens" -ne 1 ] || [ "$shape_depth" -ne 0 ] || [ "$shape_topelse" -ne 0 ] || [ "$shape_after" -ne 0 ]; then
            echo "FAIL: $mod is declared @dormant: $dormant in ${DORM_AT[$mod]}, but its body is not exactly one '#if ${dormant}_output' block with nothing outside it (top-level #if blocks: $shape_opens, unclosed: $shape_depth, top-level #else: $shape_topelse, code after the closing #end: $shape_after)"
            fail=1
            continue
        fi

        VERIFIED["$mod"]="dormant:$dormant"
        declared_dormant=$((declared_dormant + 1))
    fi
done

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

# ------------------------------------------------------------- per target ---
# The global union is only used for root-floor/declaration existence and for
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

    # A verified @only-in: precision:<side> declaration is the only thing that
    # can authorise one side of the pair missing a root the other side has; a
    # target: declaration is deliberately not enough here.
    while IFS= read -r mod; do
        [ -n "$mod" ] || continue
        at="$(awk -F'\t' -v m="$mod" '$1 == m { print $2 ":" $3; exit }' "$tmpd/roots.base")"
        if [ "${VERIFIED[$mod]:-}" = "precision:binary64" ]; then
            declared_asym=$((declared_asym + 1))
            echo "DECLARED: $f32_name omits root module $mod (base-only, at $at); it carries a verified @only-in: precision:binary64 declaration in ${OI_AT[$mod]}"
        else
            echo "FAIL: $f32_name omits root module $mod (present in $base_name at $at); the f32 bundle would lose a root that the base bundle compiles (declare it @only-in: precision:binary64 next to a root line if that is deliberate)"
            fail=1
        fi
    done < "$tmpd/only.base"
    while IFS= read -r mod; do
        [ -n "$mod" ] || continue
        at="$(awk -F'\t' -v m="$mod" '$1 == m { print $2 ":" $3; exit }' "$tmpd/roots.f32")"
        if [ "${VERIFIED[$mod]:-}" = "precision:f32" ]; then
            declared_asym=$((declared_asym + 1))
            echo "DECLARED: $base_name omits root module $mod (f32-only, at $at); it carries a verified @only-in: precision:f32 declaration in ${OI_AT[$mod]}"
        else
            echo "FAIL: $base_name omits root module $mod (present in $f32_name at $at); the base bundle would compile a root the f32 bundle does not (declare it @only-in: precision:f32 next to a root line if that is deliberate)"
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
        if [ -n "${VERIFIED[$mod]:-}" ]; then
            unrooted_decls=$((unrooted_decls + 1))
            where="${OI_AT[$mod]:-${DORM_AT[$mod]}}"
            echo "DECLARED: $mod declares @:test in ${SCAN_MODULES[$mod]} but is a root of neither $base_name nor $f32_name; verified declaration ${VERIFIED[$mod]} in $where"
        else
            echo "FAIL: $mod declares @:test in ${SCAN_MODULES[$mod]} but is a root of neither $base_name nor $f32_name; an @:test module missing from both files is a regression unless a verified @only-in/@dormant declaration covers it"
            fail=1
        fi
    done

done

# Existence of every module pinned by the root floor
# (union of all guarded classpaths + repo-wide fallback).
declare -A CHECKMOD=()
for fl in ${FLOOR_MODULES[@]+"${FLOOR_MODULES[@]}"}; do
    CHECKMOD["${fl#*$'\t'}"]=1
done
for m in ${CHECKMOD[@]+"${!CHECKMOD[@]}"}; do
    if ! resolve_module "$m"; then
        echo "FAIL: root-floor module $m does not resolve to any .hx on the guarded classpaths or anywhere under $repo"
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
echo "roots guard: PASS ($declared_onlyin verified @only-in declaration(s); $declared_dormant verified @dormant module(s); $declared_asym declared pair asymmetry(ies) in force; $unrooted_decls declared unrooted @:test module(s); $dup_lines duplicate root line(s) reported; $floor_pins pinned root(s) in root-floor)"
exit 0
