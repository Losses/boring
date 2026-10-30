#!/usr/bin/env bash
# Bucketed gen/check skeleton for tiqian (M4). Generates and checks one
# module bucket in isolation, so a single module can be verified without a
# full engine run.
#
# Usage: bucket-gen-check.sh <boring-worktree> <tiqian-root> <module> [target]
#   module : org.tiqian.core, org.tiqian.layout, org.tiqian.font, ...
#   target : ts (default). The skeleton wires the ts target only; the same
#            bucket roots feed the kotlin, dart, and swift entries unchanged.
set -euo pipefail
BORING="${1:?usage: bucket-gen-check.sh <boring-worktree> <tiqian-root> <module> [target]}"
TIQIAN="${2:?usage: bucket-gen-check.sh <boring-worktree> <tiqian-root> <module> [target]}"
MODULE="${3:?usage: bucket-gen-check.sh <boring-worktree> <tiqian-root> <module> [target]}"
TARGET="${4:-ts}"
OUT="${OUT:-/tmp/tiqian-bucket-$(basename "$MODULE")}"
rm -rf "$OUT"
mkdir -p "$OUT"
cd "$TIQIAN"

# Bucket the root classes: the two runtime types plus every test class under
# the selected package prefix.
awk -v m="$MODULE" '/^runtime\./ || index($0, m ".") == 1' \
  "$TIQIAN/engine-haxe/targets/classes.hxml" > "$OUT/classes.hxml"
echo "[bucket] $MODULE ($TARGET): $(wc -l < "$OUT/classes.hxml") roots"

# The entry copies the ts target configuration but points the boring compiler
# at the supplied worktree (so the compiler ledger stays writable) and emits
# into the bucket output directory.
cat > "$OUT/entry.hxml" <<HXML
-lib reflaxe
-cp $BORING/packages/compiler
-cp $BORING/samples
-cp $BORING/packages/compiler/reflaxe/ts/std-shadow
-cp $BORING/packages/compiler/reflaxe/ts
-cp $TIQIAN/engine-haxe/src
-cp $TIQIAN/engine-haxe/macros
-cp $TIQIAN/engine-haxe/tests
--macro GoldenDataMacros.init()
--macro haxe.macro.Compiler.addGlobalMetadata('org.tiqian', '@:build(std.RecordMember.build())')
--macro Intercept.run(['engine-haxe/src'])
--macro tscompiler.Compiler.use()
-D ts-output=$OUT/ts-gen
-D ts-test-output=$OUT/ts-gen-tests
-D ts-test-runner=bun
-D tiqian_ts
-D runtime-import=@tiqian/runtime
-D runtime-emit=.
-D package-shell=none
HXML
cat "$OUT/classes.hxml" >> "$OUT/entry.hxml"

echo "[gen] haxe $OUT/entry.hxml"
haxe "$OUT/entry.hxml"

echo "[check] bun test $OUT/ts-gen-tests"
(cd "$OUT" && bun test ts-gen-tests/)
