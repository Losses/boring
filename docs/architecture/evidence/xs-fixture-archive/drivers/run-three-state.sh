#!/usr/bin/env bash
# run-three-state.sh — re-measure the PIT-248 three-state readings and the
# PIT-297 pre-fix discriminator on a clean e1c65975 tree carrying the
# archived xs-* fixtures.
#
# usage: bash run-three-state.sh <TARGET_TREE> <EV_DIR>
#   TARGET_TREE  a checkout at e1c65975 with .haxelib set up and the fixtures
#                restored via RESTORE.sh (HAXELIB_PATH is pointed at it here)
#   EV_DIR       directory that receives the raw evidence logs
#
# What it does:
#   1. records the toolchain versions;
#   2. verifies the restore is intact (RESTORE.sh --check on TARGET_TREE);
#   3. for each compiler state (pristine / as-reviewed / frozen-57ee4997):
#        - swaps the four rustcompiler files from the archived
#          compiler-states/ snapshot (pristine comes from `git show e1c65975`),
#        - prints the resulting 4-file sha256 state anchor,
#        - runs each fixture's gen/rust.hxml (haxe, cwd = TARGET_TREE) and,
#          for full-mode fixtures, `cargo build --offline` in the generated
#          tree with a FRESH CARGO_TARGET_DIR, logging `Compiling generated`
#          count so a cache replay cannot masquerade as a run;
#   4. for xs-testmod, greps the generated boring/value_exception.rs for the
#      ValueExceptionFault(Box<...>) leak marker (the PIT-248 leak-3 check);
#   5. runner-collection probes: `haxe tests/haxe/compile.hxml` (the repo's
#      JS test build) and `bun test tests/haxe/` on the fixture-restored tree;
#   6. restores the pristine compiler files and proves the tree is clean.
#
# No measured command is ever piped: each measured command redirects to its
# own stdout/stderr files and its exit code is captured before anything else
# runs. `grep -c` counts run on already-logged stderr files, not on live
# command output.
set -uo pipefail

TOP=/home/losses/Development/tq-workspace
ARCHIVE=$TOP/dc-warn/out/xs-fixture-archive
REPO=$TOP/boring-wt-architecture
EXPECT_REV=e1c6597514634fd347d392709793cc19bd96c9a2

TARGET=${1:?usage: run-three-state.sh <TARGET_TREE> <EV_DIR>}
EV=${2:?usage: run-three-state.sh <TARGET_TREE> <EV_DIR>}
TARGET=$(cd -- "$TARGET" && pwd)
SCRATCH=$TOP/dc-warn/out/xs-archive/scratch
mkdir -p "$EV" "$SCRATCH"

export HAXELIB_PATH=$TARGET/.haxelib
export XDG_CACHE_HOME=$SCRATCH/cache
mkdir -p "$XDG_CACHE_HOME"

SRC_REL=packages/compiler/reflaxe/rust/rustcompiler
SRC=$TARGET/$SRC_REL

echo "=== run-three-state $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
{
  echo "target=$TARGET"
  echo "ev=$EV"
  echo "haxe=$(command -v haxe) $(haxe --version 2>&1 | head -1)"
  echo "cargo=$(command -v cargo) $(cargo --version 2>&1 | head -1)"
  echo "rustc=$(command -v rustc) $(rustc --version 2>&1 | head -1)"
  echo "bun=$(command -v bun) $(bun --version 2>&1 | head -1)"
  echo "target-head=$(git -C "$TARGET" rev-parse HEAD)"
  echo "haxelib-boring-dev=$(cat "$TARGET/.haxelib/boring/.dev")"
  echo "haxelib-reflaxe-dev=$(cat "$TARGET/.haxelib/reflaxe/.dev")"
} > "$EV/env.txt"

if [ "$(git -C "$TARGET" rev-parse HEAD)" != "$EXPECT_REV" ]; then
  echo "FATAL target is not at e1c65975: $(git -C "$TARGET" rev-parse HEAD)" >&2
  exit 91
fi

# --- 0. restore integrity -------------------------------------------------
bash "$ARCHIVE/RESTORE.sh" --check "$TARGET" > "$EV/01-restore-check.log" 2>&1
RC=$?
echo "restore-check rc=$RC"
[ $RC -eq 0 ] || { echo "FATAL restore check failed rc=$RC" >&2; exit 92; }

state_hashes() {
  ( cd "$TARGET" && sha256sum "$SRC_REL/Compiler.hx" "$SRC_REL/RustDecl.hx" \
      "$SRC_REL/RustEmissionState.hx" "$SRC_REL/RustExpr.hx" )
}

set_state() { # $1 = pristine|as-reviewed|frozen
  case $1 in
    pristine)
      for f in Compiler.hx RustDecl.hx RustEmissionState.hx RustExpr.hx; do
        git -C "$TARGET" show "e1c65975:$SRC_REL/$f" > "$SRC/$f"
      done ;;
    as-reviewed)
      for f in Compiler.hx RustDecl.hx RustEmissionState.hx RustExpr.hx; do
        cp -p "$ARCHIVE/compiler-states/as-reviewed/$f" "$SRC/$f"
      done ;;
    frozen)
      for f in Compiler.hx RustDecl.hx RustEmissionState.hx RustExpr.hx; do
        cp -p "$ARCHIVE/compiler-states/frozen-57ee4997/$f" "$SRC/$f"
      done ;;
    *) echo "FATAL unknown state $1" >&2; exit 93 ;;
  esac
  {
    echo "state=$1 $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    state_hashes
  } > "$EV/compiler-state.$1.txt"
  cat "$EV/compiler-state.$1.txt"
}

run_fixture() { # $1=state $2=fixture $3=mode(full|gen)
  local ST=$1 FIX=$2 MODE=$3
  local D="$EV/$ST-$FIX"
  mkdir -p "$D"
  local STAMP; STAMP=$(date +%s%N)
  local GEN="$SCRATCH/gen-$ST-$STAMP/$FIX"
  local TGT="$SCRATCH/tgt-$ST-$STAMP-$FIX"
  ( cd "$TARGET" && haxe "tests/haxe/$FIX/gen/rust.hxml" -D rust-output="$GEN" ) \
      > "$D/gen.stdout" 2> "$D/gen.stderr"
  local GENRC=$?
  printf '%s\n' "$GENRC" > "$D/gen.status"
  if [ "$GENRC" -ne 0 ]; then
    printf '%s\t%s\tgen=%s\tcargo=NOTRUN\n' "$ST" "$FIX" "$GENRC" >> "$EV/results.tsv"
    echo "[$ST/$FIX] gen=$GENRC"
    return 0
  fi
  if [ "$MODE" = full ]; then
    ( cd "$GEN" && CARGO_TARGET_DIR="$TGT" cargo build --offline ) \
        > "$D/cargo.stdout" 2> "$D/cargo.stderr"
    local CARGORC=$?
    printf '%s\n' "$CARGORC" > "$D/cargo.status"
    grep -c 'Compiling generated' "$D/cargo.stderr" > "$D/compiling-count.txt"
    printf '%s\t%s\tgen=%s\tcargo=%s\n' "$ST" "$FIX" "$GENRC" "$CARGORC" >> "$EV/results.tsv"
    echo "[$ST/$FIX] gen=$GENRC cargo=$CARGORC"
  else
    # gen-only; for xs-testmod also count the leak marker in the generated
    # boring/value_exception.rs (PIT-248 leak-3 check).
    printf '%s\t%s\tgen=%s\tcargo=NOTRUN(gen-only)\n' "$ST" "$FIX" "$GENRC" >> "$EV/results.tsv"
    if [ "$FIX" = xs-testmod ]; then
      local LEAK=NOTFOUND
      local F
      while IFS= read -r F; do
        LEAK=$(grep -c 'ValueExceptionFault(Box<' "$F")
        echo "$F leak-count=$LEAK" > "$D/leak-count.txt"
      done < <(find "$GEN" -name value_exception.rs -type f)
      echo "[$ST/$FIX] gen=$GENRC leak=$LEAK"
    else
      echo "[$ST/$FIX] gen=$GENRC"
    fi
  fi
  # keep a small witness of the generated tree's key file (not the whole tree)
  if [ -f "$GEN/lib.rs" ]; then
    ( cd "$GEN" && find . -type f -not -path './target/*' -print0 | sort -z | xargs -0 sha256sum ) \
        > "$D/gen-tree.sha256"
  fi
}

: > "$EV/results.tsv"

# --- 1. pristine (e1c65975 bytes) ------------------------------------------
set_state pristine
run_fixture pristine xs-dead     full
run_fixture pristine xs-deadcoll full
run_fixture pristine xs-twoexc   full
run_fixture pristine xs-testmod  gen

# --- 2. as-reviewed (PIT-248 negctl state = src-postfix, pre-PIT-281) ------
set_state as-reviewed
run_fixture as-reviewed xs-dead     full
run_fixture as-reviewed xs-deadcoll full
run_fixture as-reviewed xs-twoexc   full
run_fixture as-reviewed xs-crossmod full
run_fixture as-reviewed xs-testmod  gen

# --- 3. frozen (board-anchored corrected state; Compiler.hx = 57ee4997...) --
set_state frozen
run_fixture frozen xs-dead     full
run_fixture frozen xs-deadcoll full
run_fixture frozen xs-twoexc   full
run_fixture frozen xs-crossmod full
run_fixture frozen xs-testmod  gen

# --- 4. runner-collection probes (fixtures present, pristine compiler) -----
set_state pristine
echo "=== runner-collection probes ==="
( cd "$TARGET" && haxe tests/haxe/compile.hxml ) > "$EV/10-compile-hxml.log" 2>&1
RC=$?
echo "haxe tests/haxe/compile.hxml rc=$RC"
echo "haxe tests/haxe/compile.hxml rc=$RC" > "$EV/10-compile-hxml.status"
grep -c 'xs-\|xt-' "$EV/10-compile-hxml.log" > "$EV/10-compile-hxml.xs-mentions.txt" || true
( cd "$TARGET" && bun test tests/haxe/ ) > "$EV/11-bun-test-haxe.log" 2>&1
RC=$?
echo "bun test tests/haxe/ rc=$RC"
echo "bun test tests/haxe/ rc=$RC" > "$EV/11-bun-test-haxe.status"

# --- 5. leave the tree clean ------------------------------------------------
set_state pristine
git -C "$TARGET" status --porcelain > "$EV/12-final-git-status.txt"
echo "final git status lines: $(grep -c . "$EV/12-final-git-status.txt" || true)"
state_hashes > "$EV/compiler-state.final.txt"
echo "=== done $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
exit 0
