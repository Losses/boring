#!/usr/bin/env bash
# Enter the development shell.
#
# On macOS the Swift toolchain lives outside the store, so its identity is an
# evaluation input: BORING_DARWIN_SWIFT_STAMP carries the first line of
# "swift --version" into the derivation hash, and the evaluation has to be
# impure for the environment variable to reach it. Without the stamp the
# swift-system derivation records a host-unstamped toolchain and the devShell
# reports the difference on every entry.
#
# Usage: bash tools/dev-shell.sh [-c 'command']
set -euo pipefail
if [ "$(uname -s)" = Darwin ]; then
  export BORING_DARWIN_SWIFT_STAMP="$(/usr/bin/swift --version 2>&1 | head -1)"
  exec nix develop --impure "$@"
fi
exec nix develop "$@"