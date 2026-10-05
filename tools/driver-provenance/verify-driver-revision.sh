#!/usr/bin/env bash
#
# P09 B2 driver source-revision provenance verifier.
#
# WHAT THIS SCRIPT CHECKS -- this chain and nothing else:
#
#   1. a Tiqian flake.lock pins the boring github input at a revision and a
#      narHash (nodes.boring.locked.rev / nodes.boring.locked.narHash), and the
#      original input records the same revision;
#   2. the nix store source tree the pinned boring-driver derivation builds from
#      (flake.nix packages.<system>.driver, buildPhase
#      "haxe packages/driver/driver.hxml") hashes, NAR-wise, to that narHash;
#   3. rebuilding packages/driver/driver.hxml in a private copy of that tree
#      with the derivation's haxe exits 0; and
#   4. the rebuilt out/driver/driver.js sha256 equals the recorded pinned
#      artifact hash and, when --artifact is given, is byte-identical to the
#      installed share/boring/driver.js.
#
# A PASS means the recorded pinned driver.js is reproducible from the Boring
# source revision the flake lock names.  It says nothing about generation,
# tests, or driver behaviour, and it does not decide whether that revision is
# the one a consumer should run.  It is not a substitute for fixed-matrix
# acceptance.
#
# Run it under "nix develop <boring-repo>" (that supplies haxe 4.3.7); it also
# needs nix, python3 and sha256sum.
#
# EXIT STATUS  0 PASS, 1 FAIL, 2 usage error.

set -u

usage() {
  cat <<'USAGE'
usage: verify-driver-revision.sh --flake-lock <path> --source <dir>
       --expected-driver-sha256 <sha256> [--expected-rev <40-hex>]
       [--artifact <path>] [--workdir <dir>] [--rm]

  --flake-lock                  Tiqian flake.lock that pins the boring input
  --source                      nix store source tree the pinned driver builds from
  --expected-driver-sha256      recorded sha256 of share/boring/driver.js
  --expected-rev                optional: require flake.lock boring rev to equal this
  --artifact                    optional: installed share/boring/driver.js to cmp
  --workdir                     optional: scratch dir (default: mktemp -d)
  --rm                          remove the scratch dir on PASS
USAGE
}

flake_lock=
source_tree=
expected_sha=
expected_rev=
artifact=
workdir=
remove_after=0
haxe_bin=$(printenv HAXE_BIN)
[ -n "$haxe_bin" ] || haxe_bin=haxe

while [ $# -gt 0 ]; do
  case "$1" in
    --flake-lock) flake_lock=$2; shift 2 ;;
    --source) source_tree=$2; shift 2 ;;
    --expected-driver-sha256) expected_sha=$2; shift 2 ;;
    --expected-rev) expected_rev=$2; shift 2 ;;
    --artifact) artifact=$2; shift 2 ;;
    --workdir) workdir=$2; shift 2 ;;
    --rm) remove_after=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "usage error: unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

for pair in "flake-lock:$flake_lock" "source:$source_tree" "expected-driver-sha256:$expected_sha"; do
  name=$(printf '%s' "$pair" | cut -d: -f1)
  value=$(printf '%s' "$pair" | cut -d: -f2-)
  if [ -z "$value" ]; then echo "usage error: --$name is required" >&2; usage; exit 2; fi
done
[ -f "$flake_lock" ] || { echo "FAIL: flake.lock not readable: $flake_lock" >&2; exit 1; }
[ -d "$source_tree" ] || { echo "FAIL: source tree not a directory: $source_tree" >&2; exit 1; }
for tool in python3 nix sha256sum cmp; do
  command -v "$tool" >/dev/null 2>&1 || { echo "FAIL: $tool not found on PATH" >&2; exit 1; }
done
if ! command -v "$haxe_bin" >/dev/null 2>&1; then
  echo "FAIL: haxe not found on PATH ($haxe_bin); run under nix develop of the Boring repo" >&2
  exit 1
fi

fail=0
say() { echo "$*"; }
chk() { # chk <label> <actual> <expected>
  if [ "$2" = "$3" ]; then say "OK   $1 = $2"
  else say "FAIL $1: actual=$2 expected=$3"; fail=1; fi
}

lock_fields=$(python3 - "$flake_lock" <<'PY'
import json, sys
with open(sys.argv[1]) as handle:
    doc = json.load(handle)
node = (doc.get("nodes") or {}).get("boring") or {}
locked = node.get("locked") or {}
original = node.get("original") or {}
print(locked.get("rev", ""))
print(locked.get("narHash", ""))
print(original.get("rev", ""))
PY
)
lock_rev=$(printf '%s' "$lock_fields" | sed -n '1p')
lock_nar=$(printf '%s' "$lock_fields" | sed -n '2p')
lock_orig_rev=$(printf '%s' "$lock_fields" | sed -n '3p')
orig_display=$lock_orig_rev
[ -n "$orig_display" ] || orig_display='<absent>'

[ -n "$lock_rev" ] || { echo "FAIL: flake.lock has no nodes.boring.locked.rev" >&2; exit 1; }
[ -n "$lock_nar" ] || { echo "FAIL: flake.lock has no nodes.boring.locked.narHash" >&2; exit 1; }

say "flake.lock:            $flake_lock"
say "boring locked rev:     $lock_rev"
say "boring locked narHash: $lock_nar"
say "boring original rev:   $orig_display"
if [ -n "$lock_orig_rev" ]; then chk "original.rev == locked.rev" "$lock_orig_rev" "$lock_rev"; fi
if [ -n "$expected_rev" ]; then chk "locked.rev == --expected-rev" "$lock_rev" "$expected_rev"; fi

say "source tree:           $source_tree"
actual_nar=$(nix hash path "$source_tree")
chk "source NAR hash == flake.lock narHash" "$actual_nar" "$lock_nar"

hxml="$source_tree/packages/driver/driver.hxml"
[ -f "$hxml" ] || { echo "FAIL: $hxml not found" >&2; exit 1; }
say "driver.hxml sha256:    $(sha256sum "$hxml" | cut -d' ' -f1)"
say "haxe:                  $(command -v "$haxe_bin") $("$haxe_bin" --version)"

if [ -z "$workdir" ]; then
  tmpbase=$(printenv TMPDIR)
  [ -n "$tmpbase" ] || tmpbase=/tmp
  workdir=$(mktemp -d "$tmpbase/driver-provenance.XXXXXX")
fi
mkdir -p "$workdir"
say "workdir:               $workdir"

rm -rf "$workdir/src"
mkdir -p "$workdir/src"
cp -a "$source_tree/." "$workdir/src/"
chmod -R u+w "$workdir/src"

say "build argv:            $haxe_bin packages/driver/driver.hxml"
say "build cwd:             $workdir/src"
( cd "$workdir/src" && "$haxe_bin" packages/driver/driver.hxml ) \
  > "$workdir/build-stdout.log" 2> "$workdir/build-stderr.log"
build_rc=$?
say "build rc:              $build_rc"
say "build stdout bytes:    $(wc -c < "$workdir/build-stdout.log")"
say "build stderr bytes:    $(wc -c < "$workdir/build-stderr.log")"
if [ "$build_rc" -ne 0 ]; then fail=1; fi

built="$workdir/src/out/driver/driver.js"
if [ -f "$built" ]; then
  built_sha=$(sha256sum "$built" | cut -d' ' -f1)
  say "rebuilt driver.js:     $built_sha ($(wc -c < "$built") bytes)"
  chk "rebuilt driver.js sha256 == --expected-driver-sha256" "$built_sha" "$expected_sha"
else
  say "FAIL: rebuild produced no $built"; fail=1
fi

if [ -n "$artifact" ]; then
  if [ -f "$artifact" ]; then
    artifact_sha=$(sha256sum "$artifact" | cut -d' ' -f1)
    say "installed artifact:    $artifact_sha ($artifact)"
    chk "installed artifact sha256 == --expected-driver-sha256" "$artifact_sha" "$expected_sha"
    if [ -f "$built" ]; then
      if cmp -s "$artifact" "$built"; then say "OK   installed artifact == rebuilt (cmp rc=0)"
      else say "FAIL installed artifact != rebuilt (cmp rc=1)"; fail=1; fi
    fi
  else
    say "FAIL: artifact not readable: $artifact"; fail=1
  fi
fi

if [ -s "$workdir/build-stderr.log" ]; then
  say "--- build stderr (informational) ---"
  cat "$workdir/build-stderr.log"
fi

if [ "$fail" -ne 0 ]; then
  say "driver revision provenance: FAIL"
  exit 1
fi
say "driver revision provenance: PASS"
if [ "$remove_after" -eq 1 ]; then rm -rf "$workdir"; fi
exit 0
