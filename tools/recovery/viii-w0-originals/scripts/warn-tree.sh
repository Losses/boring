#!/usr/bin/env bash
# tq-warn-tree.sh — prepare an independent check-and-measure pair of worktrees
# for one warning flow.
#
#   bash scripts/warn-tree.sh <flow> [boring-base] [tiqian-base]
#
# Creates, from <flow> = kotlin for example:
#   boring-wt-warn-<flow>   branch warn/<flow>   (default base: master)
#   tiqian-wt-warn-<flow>   branch warn/<flow>   (default base: main)
#
# and wires the three inputs a Haxe generation needs but git does not carry
# (tools/setup-haxe-env.sh names them): .haxelib, engine-haxe/baseline-goldens,
# tools/unicode-data. The difference from that script is the generator: the
# boring checkout this pair resolves through .haxelib/boring/git is the pair's
# own boring worktree, so editing a backend here cannot reach the main tiqian
# checkout or the frozen vendored pin (PIT-63).
set -eu
W=/home/losses/Development/tq-workspace
FLOW="${1:?usage: warn-tree.sh <flow> [boring-base] [tiqian-base]}"
BBASE="${2:-master}"
TBASE="${3:-main}"
B="$W/boring-wt-warn-$FLOW"
T="$W/tiqian-wt-warn-$FLOW"

[ -d "$B" ] || git -C "$W/boring" worktree add "$B" -b "warn/$FLOW" "$BBASE"
[ -d "$T" ] || git -C "$W/tiqian" worktree add "$T" -b "warn/$FLOW" "$TBASE"
[ -e "$B/node_modules" ] || ln -s "$W/boring/node_modules" "$B/node_modules"

mkdir -p "$T/.haxelib/boring"
for lib in format formatter reflaxe; do
  [ -e "$T/.haxelib/$lib" ] || cp -a "$W/tiqian/.haxelib/$lib" "$T/.haxelib/$lib"
done
ln -sfn "$B" "$T/.haxelib/boring/git"
printf 'git' > "$T/.haxelib/boring/.current"
printf '%s' "$T/.haxelib/boring/git" > "$T/.haxelib/boring/.dev"

mkdir -p "$T/tools"
for d in "$W"/tiqian/tools/unicode-*; do
  n="$(basename "$d")"
  [ -e "$T/tools/$n" ] || ln -s "$d" "$T/tools/$n"
done
[ -e "$T/engine-haxe/baseline-goldens" ] || \
  ln -s "$W/tiqian/engine-haxe/baseline-goldens" "$T/engine-haxe/baseline-goldens"

# Generated trees and build outputs go to the mounted DataCenter scratch disk,
# not to /home: the mount is kept alive by the rclone-warn systemd user unit,
# and it is where the project keeps leftovers from earlier rounds.
OUT="$W/dc-warn/warn/$FLOW/tiqian-out"
mkdir -p "$OUT"
if [ -d "$T/engine-haxe/out" ] && [ ! -L "$T/engine-haxe/out" ]; then
  mv "$T/engine-haxe/out"/* "$OUT"/ 2>/dev/null || true
  rm -rf "$T/engine-haxe/out"
fi
ln -sfn "$OUT" "$T/engine-haxe/out"

echo "flow=$FLOW"
echo "boring  $B  $(git -C "$B" rev-parse --short HEAD)  branch warn/$FLOW"
echo "tiqian  $T  $(git -C "$T" rev-parse --short HEAD)  branch warn/$FLOW"
echo "generator $B = $(git -C "$T/.haxelib/boring/git" rev-parse --short HEAD)"
