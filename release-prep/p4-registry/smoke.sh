#!/usr/bin/env bash
# Registry availability smoke for the boring dependency pull/install path.
# Pulls every dependency boring declares into one clean haxelib repository.
#
# Usage: smoke.sh [repo-dir]
# Env: BORING_REV overrides the boring git revision (default below).
set -u
REPO="${1:-/tmp/boring-p4-registry}"
REV="${BORING_REV:-766361a15913b2fcfe59cc823a4a6e3c05370fea}"

rm -rf "$REPO"
mkdir -p "$REPO"
haxelib setup "$REPO" >/dev/null

echo "== format 3.8.0 (lib.haxe.org) =="
haxelib install format 3.8.0 || { echo "FAIL: format"; exit 1; }

echo "== formatter 1.18.0 (lib.haxe.org) =="
haxelib install formatter 1.18.0 || { echo "FAIL: formatter"; exit 1; }

echo "== reflaxe (lib.haxe.org, latest stable) =="
haxelib install reflaxe || { echo "FAIL: reflaxe"; exit 1; }

echo "== boring (github git install) =="
haxelib git boring https://github.com/Losses/boring "$REV" || { echo "FAIL: boring"; exit 1; }

echo "== final library list =="
haxelib list
