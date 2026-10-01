#!/usr/bin/env bash
# Runner for task t-munibdo3-jwqi (module-keyed read sites). Never pipes a measured command.
#   bash run-matrix.sh <phase-tag> [fixture ...]
set -u
WT=/home/losses/Development/tq-workspace/boring-wt-modkey
OUT=/home/losses/Development/tq-workspace/dc-warn/out/rust-module-keyed
PHASE=$1; shift
LOG=$OUT/evidence/raw
mkdir -p "$LOG"
[ "$(cd "$WT" && pwd)" = "$WT" ] || { echo "WRONG WT"; exit 90; }
export HAXELIB_PATH=$WT/.haxelib
export XDG_CACHE_HOME=$OUT/scratch/cache
mkdir -p "$XDG_CACHE_HOME"
{
  echo "phase=$PHASE fixtures=$*"
  echo "--- compiler state ---"
  ( cd "$WT" && sha256sum packages/compiler/reflaxe/rust/rustcompiler/Compiler.hx \
      packages/compiler/reflaxe/rust/rustcompiler/RustDecl.hx \
      packages/compiler/reflaxe/rust/rustcompiler/RustEmissionState.hx \
      packages/compiler/reflaxe/rust/rustcompiler/RustExpr.hx \
      packages/compiler/reflaxe/rust/rustcompiler/RustType.hx )
} > "$LOG/$PHASE.state.txt"
for FIX in "$@"; do
  STAMP=$(date +%H%M%S%N)
  GENREL=$OUT/scratch/gen-$PHASE-$STAMP/$FIX
  TGT=$OUT/scratch/target-$PHASE-$STAMP-$FIX
  cd "$WT" || exit 90
  haxe tests/haxe/$FIX/gen/rust.hxml -D rust-output=$GENREL \
      >"$LOG/$PHASE-$FIX.gen.stdout" 2>"$LOG/$PHASE-$FIX.gen.stderr"
  GENRC=$?
  CARGORC=SKIP
  if [ $GENRC -eq 0 ]; then
    cd "$GENREL" || exit 90
    CARGO_TARGET_DIR=$TGT cargo build --offline \
        >"$LOG/$PHASE-$FIX.cargo.stdout" 2>"$LOG/$PHASE-$FIX.cargo.stderr"
    CARGORC=$?
    grep -c 'Compiling generated' "$LOG/$PHASE-$FIX.cargo.stderr" > "$LOG/$PHASE-$FIX.compiling-count.txt"
  fi
  printf '%s %s gen=%s cargo=%s genrel=%s\n' "$PHASE" "$FIX" "$GENRC" "$CARGORC" "$GENREL" \
      | tee -a "$LOG/$PHASE.results.txt"
done
exit 0
