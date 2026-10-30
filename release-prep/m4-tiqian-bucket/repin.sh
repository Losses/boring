#!/usr/bin/env bash
# One-command .haxelib repin for tiqian. Clears the stale boring git copy,
# copies the files tiqian's Haxe build reads from a boring worktree, and
# repins flake.nix to the requested boring revision.
#
# Usage: repin.sh <boring-worktree> <tiqian-root> <rev>
# Example:
#   repin.sh /path/to/boring /path/to/tiqian 766361a15913b2fcfe59cc823a4a6e3c05370fea
set -euo pipefail
BORING="${1:?usage: repin.sh <boring-worktree> <tiqian-root> <rev>}"
TIQIAN="${2:?usage: repin.sh <boring-worktree> <tiqian-root> <rev>}"
REV="${3:?usage: repin.sh <boring-worktree> <tiqian-root> <rev>}"

GIT_DIR="$TIQIAN/.haxelib/boring/git"
FLAKE="$TIQIAN/flake.nix"

# 1. Drop the stale checkout so no old compiler source survives.
rm -rf "$GIT_DIR"
mkdir -p "$GIT_DIR"

# 2. Copy the files the Haxe build reads. The compiler resolves
#    semantic-exceptions.json through its class path and writes its ledger
#    under the checkout root, so the copy must stay writable.
cp -a "$BORING/packages" "$GIT_DIR/packages"
cp -a "$BORING/samples" "$GIT_DIR/samples"
cp -a "$BORING/haxelib.json" "$GIT_DIR/haxelib.json"
cp -a "$BORING/defines.json" "$GIT_DIR/defines.json"
cp -a "$BORING/boring.json" "$GIT_DIR/boring.json"
cp -a "$BORING/flake.nix" "$BORING/flake.lock" "$GIT_DIR/"

# 3. Record the revision the same way the devShell shellHook does.
printf '%s
' "$REV" > "$GIT_DIR/.boring-flake-revision"

# 4. Repin the flake input URL to the requested revision.
sed -i -E "s#(url = \"github:Losses/boring/)[0-9a-f]+(\";)#\1$REV\2#" "$FLAKE"
echo "repinned $FLAKE to boring $REV"
echo "run 'nix flake lock --update-input boring' in $TIQIAN once the revision is pushed"
