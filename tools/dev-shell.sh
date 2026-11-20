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
# Usage:
#   bash tools/dev-shell.sh                        # interactive shell
#   bash tools/dev-shell.sh boring gen swift --project boring.json
set -euo pipefail
if [ "$(uname -s)" = Darwin ]; then
  export BORING_DARWIN_SWIFT_STAMP="$(/usr/bin/swift --version 2>&1 | head -1)"
  if [ "$#" -eq 0 ]; then
    exec nix develop --impure
  fi
  exec nix develop --impure -c "$@"
fi
if [ "$#" -eq 0 ]; then
  exec nix develop
fi
exec nix develop -c "$@"