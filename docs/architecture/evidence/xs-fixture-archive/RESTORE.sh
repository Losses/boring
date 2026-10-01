#!/usr/bin/env bash
# RESTORE.sh — put the archived xs-* regression fixtures back onto a clean
# e1c65975 checkout, verifying every byte by sha256 before it is used.
#
# Why this exists: the xs-* fixture family is NOT tracked in the repository
# (git ls-files 'tests/haxe/xs-*' is empty at e1c65975). Without this archive a
# fresh clone cannot reproduce the PIT-248 readings at all.
#
# usage:
#   RESTORE.sh [TARGET_REPO]            restore fixtures into TARGET_REPO
#   RESTORE.sh --check [TARGET_REPO]    verify only, write nothing
#   RESTORE.sh --any-rev [TARGET_REPO]  allow a target not at e1c65975
#
# TARGET_REPO defaults to $PWD. Fixtures land at TARGET_REPO/tests/haxe/<fixture>/...
#
# Guarantees:
#   * safe to run repeatedly  — a destination that already matches is left alone
#   * fails loudly            — any sha256 mismatch (archive side or destination
#                               side) aborts with a non-zero exit and names the
#                               offending file
#   * never deletes           — only creates or overwrites fixture files
#   * verbatim                — bytes are copied, never "fixed"
set -uo pipefail

ARCHIVE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
MANIFEST="$ARCHIVE_DIR/RESTORE.sha256"
EXPECT_REV=e1c6597514634fd347d392709793cc19bd96c9a2
EXPECT_REV_SHORT=e1c65975

MODE=restore
ALLOW_ANY_REV=0
TARGET=""
for arg in "$@"; do
  case "$arg" in
    --check)     MODE=check ;;
    --any-rev)   ALLOW_ANY_REV=1 ;;
    -h|--help)   sed -n '2,25p' "${BASH_SOURCE[0]}"; exit 0 ;;
    -*)          echo "RESTORE: unknown option: $arg" >&2; exit 2 ;;
    *)           if [ -n "$TARGET" ]; then echo "RESTORE: more than one target given" >&2; exit 2; fi
                 TARGET=$arg ;;
  esac
done
TARGET=${TARGET:-$PWD}
TARGET=$(cd -- "$TARGET" 2>/dev/null && pwd) || {
  echo "RESTORE: FAIL target directory does not exist" >&2; exit 2; }
DEST_ROOT="$TARGET/tests/haxe"

echo "RESTORE: archive  = $ARCHIVE_DIR"
echo "RESTORE: target   = $TARGET"
echo "RESTORE: mode     = $MODE$([ $ALLOW_ANY_REV = 1 ] && echo ' (any-rev)')"

[ -f "$MANIFEST" ] || { echo "RESTORE: FAIL manifest missing: $MANIFEST" >&2; exit 2; }

# --- 0. the target must be the revision whose behaviour we are reproducing ----
if [ -d "$TARGET/.git" ] || [ -f "$TARGET/.git" ]; then
  HEAD=$(git -C "$TARGET" rev-parse HEAD 2>/dev/null)
  if [ "$HEAD" != "$EXPECT_REV" ]; then
    if [ "$ALLOW_ANY_REV" = 1 ]; then
      echo "RESTORE: WARN target HEAD is ${HEAD:-<unknown>}, not $EXPECT_REV_SHORT (allowed by --any-rev)"
    else
      echo "RESTORE: FAIL target HEAD is ${HEAD:-<unknown>}, expected $EXPECT_REV_SHORT" >&2
      echo "RESTORE:      pass --any-rev to override, or check out $EXPECT_REV_SHORT" >&2
      exit 3
    fi
  else
    echo "RESTORE: target HEAD = $EXPECT_REV_SHORT OK"
  fi
else
  echo "RESTORE: WARN target is not a git checkout; revision guard skipped"
fi

# --- 1. verify the archive against the manifest before trusting any byte ------
echo "RESTORE: step 1/3 verifying archive against RESTORE.sha256 ..."
if ! ( cd "$ARCHIVE_DIR" && sha256sum -c --strict --quiet RESTORE.sha256 ); then
  echo "RESTORE: FAIL archive does not match RESTORE.sha256 (see above) — refusing to restore" >&2
  exit 4
fi
N=$(grep -c . "$MANIFEST")
echo "RESTORE: archive OK ($N files)"

# --- 2. copy each fixture file verbatim --------------------------------------
echo "RESTORE: step 2/3 $([ "$MODE" = check ] && echo 'checking' || echo 'restoring') $N files into $DEST_ROOT ..."
created=0; uptodate=0; replaced=0; REPLACED_LIST=""
while read -r want rel; do
  [ -n "${rel:-}" ] || continue
  src="$ARCHIVE_DIR/$rel"
  dst="$DEST_ROOT/$rel"
  if [ -e "$dst" ]; then
    have=$(sha256sum "$dst" | awk '{print $1}')
    if [ "$have" = "$want" ]; then
      uptodate=$((uptodate+1)); continue
    fi
    if [ "$MODE" = check ]; then
      echo "RESTORE: CHECK-FAIL $rel present but hash differs" >&2
      echo "RESTORE:            want $want" >&2
      echo "RESTORE:            have $have" >&2
      exit 5
    fi
    replaced=$((replaced+1)); REPLACED_LIST="$REPLACED_LIST  $rel (was $have)\n"
  fi
  if [ "$MODE" = restore ]; then
    mkdir -p -- "$(dirname -- "$dst")" || { echo "RESTORE: FAIL mkdir for $rel" >&2; exit 6; }
    cp -p -- "$src" "$dst" || { echo "RESTORE: FAIL copy $rel" >&2; exit 6; }
  fi
  [ -e "$dst" ] && created=$((created+1))
done < "$MANIFEST"

# --- 3. verify the destination -------------------------------------------------
echo "RESTORE: step 3/3 verifying restored files by sha256 ..."
bad=0
while read -r want rel; do
  [ -n "${rel:-}" ] || continue
  dst="$DEST_ROOT/$rel"
  if [ ! -e "$dst" ]; then
    echo "RESTORE: FAIL missing after restore: $rel" >&2; bad=$((bad+1)); continue
  fi
  have=$(sha256sum "$dst" | awk '{print $1}')
  if [ "$have" != "$want" ]; then
    echo "RESTORE: FAIL hash mismatch: $rel" >&2
    echo "RESTORE:      want $want" >&2
    echo "RESTORE:      have $have" >&2
    bad=$((bad+1))
  fi
done < "$MANIFEST"

if [ "$bad" != 0 ]; then
  echo "RESTORE: FAIL $bad file(s) did not verify — archive is NOT trusted" >&2
  exit 7
fi

echo "RESTORE: wrote=$created already-correct=$uptodate replaced-divergent=$replaced verified=$N"
if [ "$replaced" != 0 ]; then
  echo "RESTORE: NOTE the following pre-existing files differed and were overwritten verbatim:"
  printf "%b" "$REPLACED_LIST"
fi
echo "RESTORE: OK all $N files verified by sha256 at $DEST_ROOT"
exit 0
