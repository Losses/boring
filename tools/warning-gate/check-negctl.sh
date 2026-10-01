#!/usr/bin/env bash
# Real-compiler negative control for the rc wiring in check.sh.
#
# check-selftest.sh drives check() with hand-built rc files: it pins the
# ADJUDICATION but cannot show that a real compiler failure reaches it. This
# control closes that gap on real binaries:
#
#   1. copy the checked-in reference/kotlin/gen (and, when available,
#      reference/rust/gen) into a mktemp -d - never into the repository tree;
#   2. inject one syntax error into that copy;
#   3. run the real kotlinc / kotlinc -Werror / cargo check /
#      RUSTFLAGS=-D warnings cargo check invocations the gate itself runs, and
#      keep their rc and their logs;
#   4. feed those real rc/log files to BOTH revisions of the adjudication -
#      the pre-wiring one and the tree's current one;
#   5. assert PRE-FIX = PASS (the defect: a tree that does not compile passed)
#      and POST-FIX = FAIL, with the failure carried by an rc message and NOT
#      by a warning-count message.
#
# Scope note: check.sh cannot run standalone here - dart, swift and tsc are not
# installed, and it would need all five generated trees - so the four other
# columns are supplied as clean stubs (rc 0/0, empty logs) and this control is
# about the column(s) under injection reaching the verdict. Each stub is
# labelled in the transcript. Nothing outside $TMP is written.
#
# Usage: tools/warning-gate/check-negctl.sh [options]
#   --gen <dir>       kotlin/gen to copy         (default $ROOT/reference/kotlin/gen)
#   --rust-gen <dir>  rust/gen to copy           (default $ROOT/reference/rust/gen)
#   --no-rust         skip the rust leg even if its tree is present
#   --pre-fix <file>  pre-wiring check.sh        (default: git show <anchor>^:...)
#   --gate <file>     gate under test            (default $ROOT/tools/warning-gate/check.sh;
#                     point it at a reverted copy to mutation-test this control)
#   --keep            keep the temp tree and print where it is
# Env: KOTLINC_BIN (default kotlinc), CARGO_BIN (default cargo),
#      NEGCTL_PRE_FIX_COMMIT (default 9086bf78, the commit that added the wiring)
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
POST_GATE=$ROOT/tools/warning-gate/check.sh
KOTLINC_BIN=${KOTLINC_BIN:-kotlinc}
CARGO_BIN=${CARGO_BIN:-cargo}
PRE_FIX_COMMIT=${NEGCTL_PRE_FIX_COMMIT:-9086bf78}
GEN=$ROOT/reference/kotlin/gen
RUST_GEN=$ROOT/reference/rust/gen
PRE_GATE=""
DO_RUST=1
KEEP=0

while [ $# -gt 0 ]; do
  case "$1" in
    --gen) GEN=$2; shift 2 ;;
    --rust-gen) RUST_GEN=$2; shift 2 ;;
    --no-rust) DO_RUST=0; shift ;;
    --pre-fix) PRE_GATE=$2; shift 2 ;;
    --gate) POST_GATE=$2; shift 2 ;;
    --keep) KEEP=1; shift ;;
    -h | --help) sed -n '2,35p' "$0"; exit 0 ;;
    *) echo "check-negctl: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

echo "check-negctl: argv='$0' '$*'"
echo "check-negctl: cwd=$PWD"
echo "check-negctl: root=$ROOT"
echo "check-negctl: post-fix gate=$POST_GATE sha256=$(sha256sum "$POST_GATE" | awk '{print $1}')"

TMP=$(mktemp -d)
if [ "$KEEP" = 1 ]; then
  trap 'echo "check-negctl: kept temp tree: $TMP"' EXIT
else
  trap 'rm -rf "$TMP"' EXIT
fi

# ---------------------------------------------------------------- pre-fix gate
if [ -z "$PRE_GATE" ]; then
  PRE_GATE=$TMP/check.pre-fix.sh
  if ! git -C "$ROOT" show "$PRE_FIX_COMMIT^:tools/warning-gate/check.sh" >"$PRE_GATE" 2>"$TMP/prefix.err"; then
    echo "check-negctl: FATAL: cannot read the pre-wiring check.sh from $PRE_FIX_COMMIT^:"
    sed 's/^/  /' "$TMP/prefix.err"
    echo "check-negctl: pass --pre-fix <file> with a copy of the pre-wiring gate."
    exit 2
  fi
fi
echo "check-negctl: pre-fix gate=$PRE_GATE sha256=$(sha256sum "$PRE_GATE" | awk '{print $1}')"
echo "check-negctl: kotlinc=$($KOTLINC_BIN -version 2>&1 | head -1)"
echo "check-negctl: cargo=$($CARGO_BIN --version 2>&1 | head -1)"

RC_OK=0
note() { echo "check-negctl: $*"; }

# The adjudication functions live at file scope in check.sh, which runs the five
# compilers as it is sourced, so extract them by a documented awk range (the same
# one check-selftest.sh uses) and drive them over a prepared $OUT.
extract_logic() {
  awk '/^run\(\) \{/{p=1} p && /^# Keep the loose invocation/{p=0} p' "$1"
}

# adjudicate <gate> <out-dir> <kotlin-base> -> transcript on stdout, rc = verdict
adjudicate() {
  local gate=$1 out=$2 kbase=$3
  (
    OUT=$out
    FAIL=0
    UNMEASURED=0
    ALLOW_UNMEASURED=0
    ROOT=$TMP
    LOGIC=$(extract_logic "$gate")
    case "$LOGIC" in
      *'check() {'*) : ;;
      *) echo "could not extract check() from $gate"; exit 2 ;;
    esac
    eval "$LOGIC"
    check dart 46
    check kotlin "$kbase"
    check rust 4
    check swift 0
    check typescript 0
    if [ "$FAIL" -eq 0 ]; then
      echo "VERDICT: WARNING GATE PASS"
    else
      echo "VERDICT: WARNING GATE FAIL"
    fi
    exit "$FAIL"
  )
}

# stub_clean <out> <col> - one clean column with rc 0/0 and an empty log.
stub_clean() {
  : >"$1/$2.loose"
  : >"$1/$2.strict"
  printf '0\n' >"$1/$2.loose.rc"
  printf '0\n' >"$1/$2.strict.rc"
}

# ------------------------------------------------------------------- assertions
ASSERT_PASS=0
ASSERT_FAIL=0
assert() { # assert <label> <expected> <actual>
  if [ "$2" = "$3" ]; then
    echo "ok     $1 [$3]"
    ASSERT_PASS=$((ASSERT_PASS + 1))
  else
    echo "NOT OK $1: expected '$2', got '$3'"
    ASSERT_FAIL=$((ASSERT_FAIL + 1))
  fi
}

case "$(extract_logic "$PRE_GATE")" in
  *'compile FAILED (rc='*) assert "pre-fix gate carries no rc wiring" absent present ;;
  *) assert "pre-fix gate carries no rc wiring" absent absent ;;
esac
case "$(extract_logic "$POST_GATE")" in
  *'compile FAILED (rc='*) assert "post-fix gate carries the rc wiring" present present ;;
  *) assert "post-fix gate carries the rc wiring" present absent ;;
esac

# --------------------------------------------------------------- build the OUT
if [ ! -d "$GEN" ]; then
  note "FATAL: kotlin generated tree not found: $GEN"
  note "       (it is git-ignored; pass --gen <dir> pointing at a checked-in checkout)"
  exit 2
fi

OUT=$TMP/out
mkdir -p "$OUT"
KTDIR=$TMP/kt
mkdir -p "$KTDIR"
cp -a "$GEN" "$KTDIR/gen"
cat >"$KTDIR/gen/ZzInjectedSyntaxError.kt" <<'KT'
package boring.injected

fun injectedSyntaxError( {
KT
note "kotlin leg: $(find "$KTDIR/gen" -name '*.kt' | wc -l) .kt files copied from $GEN, syntax error injected into gen/ZzInjectedSyntaxError.kt"

kt_loose_argv=("$KOTLINC_BIN" $(find "$KTDIR/gen" -name '*.kt' -print) -d "$TMP/kt-loose.jar")
"${kt_loose_argv[@]}" >"$OUT/kotlin.loose" 2>&1
KT_LOOSE_RC=$?
"$KOTLINC_BIN" -Werror $(find "$KTDIR/gen" -name '*.kt' -print) -d "$TMP/kt-strict.jar" >"$OUT/kotlin.strict" 2>&1
KT_STRICT_RC=$?
printf '%s\n' "$KT_LOOSE_RC" >"$OUT/kotlin.loose.rc"
printf '%s\n' "$KT_STRICT_RC" >"$OUT/kotlin.strict.rc"
KT_WARN=$(grep -cE '\.kt:[0-9]+:[0-9]+: warning:' "$OUT/kotlin.loose" || true)
note "kotlin leg: loose_rc=$KT_LOOSE_RC strict_rc=$KT_STRICT_RC countable_warnings=$KT_WARN"
note "kotlin leg: loose  argv = $KOTLINC_BIN <$((${#kt_loose_argv[@]} - 3)) .kt files under $KTDIR/gen> -d $TMP/kt-loose.jar"
note "kotlin leg: strict argv = $KOTLINC_BIN -Werror <same files> -d $TMP/kt-strict.jar"

for c in dart swift typescript; do stub_clean "$OUT" "$c"; done
note "stubbed clean (rc 0/0, empty log): dart swift typescript"

# ------------------------------------------------------------------ rust leg
RUST_ACTIVE=0
if [ "$DO_RUST" = 1 ] && [ -d "$RUST_GEN" ]; then
  RTDIR=$TMP/rt
  mkdir -p "$RTDIR"
  cp -a "$RUST_GEN" "$RTDIR/gen"
  printf '\npub mod zz_injected_syntax_error;\n' >>"$RTDIR/gen/lib.rs"
  cat >"$RTDIR/gen/zz_injected_syntax_error.rs" <<'RS'
pub fn injected_syntax_error( {
RS
  "$CARGO_BIN" check --manifest-path "$RTDIR/gen/Cargo.toml" >"$OUT/rust.loose" 2>&1
  RS_LOOSE_RC=$?
  RUSTFLAGS="${RUSTFLAGS:-} -D warnings" "$CARGO_BIN" check --manifest-path "$RTDIR/gen/Cargo.toml" >"$OUT/rust.strict" 2>&1
  RS_STRICT_RC=$?
  printf '%s\n' "$RS_LOOSE_RC" >"$OUT/rust.loose.rc"
  printf '%s\n' "$RS_STRICT_RC" >"$OUT/rust.strict.rc"
  RS_WARN=$(grep -E '^[[:space:]]+--> ' "$OUT/rust.loose" | grep -cE 'runtime/|boring/|haxe/|registry/|std/' || true)
  note "rust leg: loose_rc=$RS_LOOSE_RC strict_rc=$RS_STRICT_RC countable_warnings=$RS_WARN"
  if [ "$RS_LOOSE_RC" -ne 0 ] && [ "$RS_WARN" = 0 ]; then RUST_ACTIVE=1; fi
else
  stub_clean "$OUT" rust
  note "rust leg skipped (no tree at $RUST_GEN); rust stubbed clean"
fi

assert "injected kotlin loose rc is non-zero" yes "$([ "$KT_LOOSE_RC" -ne 0 ] && echo yes || echo no)"
assert "injected kotlin emitted no countable warning" 0 "$KT_WARN"
if [ "$RUST_ACTIVE" = 1 ]; then
  assert "injected rust loose rc is non-zero" yes yes
  assert "injected rust emitted no countable warning" 0 "$RS_WARN"
fi

# --------------------------------------------------- run both gate revisions
echo
note "--- PRE-FIX adjudication over the real injected rc/log files ---"
adjudicate "$PRE_GATE" "$OUT" 59 >"$TMP/pre.txt" 2>&1
PRE_RC=$?
sed 's/^/  /' "$TMP/pre.txt"
echo
note "--- POST-FIX adjudication over the same rc/log files ---"
adjudicate "$POST_GATE" "$OUT" 59 >"$TMP/post.txt" 2>&1
POST_RC=$?
sed 's/^/  /' "$TMP/post.txt"

PRE_VERDICT=$(grep -o 'PASS\|FAIL' "$TMP/pre.txt" | tail -1)
POST_VERDICT=$(grep -o 'PASS\|FAIL' "$TMP/post.txt" | tail -1)
echo
assert "PRE-FIX verdict on a tree that does not compile" PASS "$PRE_VERDICT"
assert "POST-FIX verdict on the same tree" FAIL "$POST_VERDICT"
assert "PRE-FIX exit code" 0 "$PRE_RC"
assert "POST-FIX exit code" 1 "$POST_RC"

if grep -qE 'compile FAILED \(rc=' "$TMP/post.txt"; then RC_DRIVEN=yes; else RC_DRIVEN=no; fi
if grep -qE 'has [0-9]+ warning\(s\), baseline is' "$TMP/post.txt"; then COUNT_MSG=yes; else COUNT_MSG=no; fi
assert "POST-FIX failure message is an rc message" yes "$RC_DRIVEN"
assert "POST-FIX transcript carries no warning-count failure" no "$COUNT_MSG"

echo
if [ "$ASSERT_FAIL" -eq 0 ]; then
  echo "check-negctl: PASS ($ASSERT_PASS assertions) - the gate now fails on a real compile failure"
  echo 'check-negctl: PRE-FIX printed PASS for this tree; that is the defect this control pins.'
  exit 0
fi
echo "check-negctl: FAIL ($ASSERT_FAIL of $((ASSERT_PASS + ASSERT_FAIL)) assertions failed)"
exit 1
