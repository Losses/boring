#!/usr/bin/env bash
# tq-warnings.sh — per-target diagnostic histogram for the non-Rust targets.
#
# One reading answers one question: which diagnostic families does each target
# emit, and how many of each. Nothing here changes code; it regenerates the
# trees first (a reading taken against a stale tree is not a reading, PIT-29)
# and then counts what the target toolchain says.
#
# usage:
#   bash tq-warnings.sh measure <label>        # regenerate + count -> <label>.tsv
#   bash tq-warnings.sh count   <label>        # count only, keep the trees
#   bash tq-warnings.sh diff    <base.tsv> <cur.tsv>
#
# Every reading records both repository revisions and the generator revision.
# The generator revision is the boring checkout this tiqian worktree resolves
# through .haxelib/boring/git, and it decides what the generated code contains.
set -u
W=/home/losses/Development/tq-workspace
BORING_WT="${BORING_WT:-$W/boring-wt-warnstd}"
TIQIAN_WT="${TIQIAN_WT:-$W/tiqian-wt-warnstd}"
L="$W/.tq-logs/warnstd"
SHIM=/tmp/swift-shim/swiftc-shim.sh
export XDG_CACHE_HOME="$W/.nix-cache"
export PATH=/tmp/swift-shim/bin:$PATH
export BORING_SWIFT_SYSTEM_PACKAGE="${BORING_SWIFT_SYSTEM_PACKAGE:-/tmp/swift-shim/system-package}"
export SDKROOT="${SDKROOT:-/tmp/composed-sdk}"
mkdir -p "$L" /tmp/warnstd

# nix develop must start inside a checkout that carries the flake, so every
# call names that directory explicitly.
nd() { local d="$1"; shift; ( cd "$d" && nix develop -c bash -c "$*" ); }

# ---------------------------------------------------------------- generation
gen_boring() {
  local id
  nd "$BORING_WT" "haxe tools/bundle/driver.hxml" > "$L/gen-driver.log" 2>&1 \
    || { echo "driver build failed" >&2; return 1; }
  for id in ts kotlin kotlin-f32 dart swift swift-f32; do
    rm -rf "$BORING_WT/reference/$id/gen" "$BORING_WT/reference/$id/gen-tests"
    nd "$BORING_WT" "bun out/bundle/driver.js gen $id" > "$L/gen-boring-$id.log" 2>&1
    printf 'gen boring %-12s rc=%s' "$id" "$?" >&2
    printf ' files=%s\n' "$(find $BORING_WT/reference/$id -name '*.*' 2>/dev/null | wc -l)" >&2
  done
}

gen_tiqian() {
  local id
  for id in kotlin-f32 kotlin-f64 ts swift-f32 swift-f64 dart; do
    rm -rf "$TIQIAN_WT/engine-haxe/out/$id/gen" "$TIQIAN_WT/engine-haxe/out/$id/gen-tests"
    nd "$TIQIAN_WT" "bun $BORING_WT/out/bundle/driver.js gen $id" > "$L/gen-tiqian-$id.log" 2>&1
    printf 'gen tiqian %-12s rc=%s' "$id" "$?" >&2
    printf ' files=%s\n' "$(find $TIQIAN_WT/engine-haxe/out/$id -name '*.*' 2>/dev/null | wc -l)" >&2
  done
}

# ------------------------------------------------------------------- counting
# Family normalisation: type names and numbers differ per site and would split
# one family into hundreds of rows; the message text is what recurs.
norm() { sed -E "s/'[^']*'/'<T>'/g; s/[0-9]+/<N>/g" | sed 's/[[:space:]]*$//'; }
# kotlinc prepends an environmental warning when its working directory is a git
# checkout with changes ("Git tree '...' is dirty"). It is not a diagnostic of the
# compiled code, and it appears or disappears with the state of the checkout, so
# left in it moves the histogram by one per target (PIT-58's sibling).
env_noise() { grep -v "Git tree .* is dirty"; }
# kotlinc prepends an environmental warning when its working directory is a git
# checkout with changes ("Git tree '...' is dirty").  It is not a diagnostic of
# the compiled code and it appears and disappears with the state of the
# checkout, so it would otherwise move the histogram by one per target (PIT-58's
# sibling: cargo prints the same kind of line).
env_noise() { grep -v "Git tree .* is dirty"; }

count_kotlin() { # <label> <dirs...>
  local label="$1"; shift
  local dirs=() d
  for d in "$@"; do [ -d "$d" ] && dirs+=("$d"); done
  [ "${#dirs[@]}" -eq 0 ] && return 0
  local log="$L/count-$label-kotlinc.log"
  rm -rf "/tmp/warnstd/$label.jar"
  nd "$BORING_WT" "kotlinc -J-Xmx6g \$(find ${dirs[*]} -name '*.kt') -d /tmp/warnstd/$label.jar" > "$log" 2>&1
  grep 'warning:' "$log" | env_noise | sed 's/^.*warning: //' | norm | sort | uniq -c | sort -rn \
    | awk -v t="$label" '{c=$1; $1=""; sub(/^ /,""); printf "%s\tkotlin\t%s\t%d\n", t, $0, c}'
  printf 'kotlin %-16s warnings=%s errors=%s\n' "$label" \
    "$(grep 'warning:' "$log" | env_noise | wc -l)" "$(grep -cE '(^| )error: ' "$log")" >&2
  # A compile that stops on errors reports few or no warnings; that zero is not a
  # clean tree (PIT-35/PIT-125). Mark it in the histogram so it can never be read
  # as "this target got to zero".
  local kerr; kerr="$(grep -cE '(^| )error: ' "$log")"
  [ "$kerr" -gt 0 ] && printf '%s\tkotlin\t#COMPILE-ERRORS\t%s\n' "$label" "$kerr"
}

count_ts() { # <label> <tsconfig>
  local label="$1" cfg="$2"
  local log="$L/count-$label-tsc.log"
  # Pin the compiler: `bun x tsc` now fetches TypeScript 7.0.2, which resolves
  # .ts-specifier imports differently from the 5.9.3 the frozen baseline was
  # taken with — the same tree then reports 563 extra TS2307 "cannot find
  # module .../X.ts" and the column stops being comparable with its own
  # baseline (observed 2026-09-27: baseline 744 -> 625, of which 563 TS2307).
  # Prefer a repo-local tsc, exactly like tiqian's ts-gate.sh does.
  local tsc=""
  local c
  for c in "$(dirname "$cfg")/../../../../node_modules/.bin/tsc" "$BORING_WT/node_modules/.bin/tsc"; do
    [ -x "$c" ] && { tsc="$c"; break; }
  done
  if [ -z "$tsc" ]; then
    printf 'ts %-20s NO-PINNED-TSC (reading skipped; install typescript in a repo-local node_modules)\n' "$label" >&2
    printf '%s\tts\t#NO-PINNED-TSC\t1\n' "$label"
    return 0
  fi
  ( cd "$(dirname "$cfg")" && "$tsc" -p "$(basename "$cfg")" ) > "$log" 2>&1
  printf '# tsc=%s (%s)\n' "$tsc" "$("$tsc" --version 2>/dev/null | tail -1)" >> "$log"
  grep -oE 'TS[0-9]+' "$log" | sort | uniq -c | sort -rn \
    | awk -v t="$label" '{c=$1; printf "%s\tts\t%s\t%d\n", t, $2, c}'
  printf 'ts %-20s errors=%s (%s)\n' "$label" "$(grep -c 'error TS' "$log")" "$("$tsc" --version 2>/dev/null | tail -1)" >&2
}

count_dart() { # <label> <gen dir> [<tests dir>]
  # Both dart surfaces are counted, and they are analysed in ONE context: the
  # generated test tree imports the library tree, so analysing gen-tests alone
  # reports ~1816 uri_does_not_exist that have nothing to do with warnings.
  # Counting gen alone was also a scope hole — the milestone's criterion is
  # "0 diagnostics per target" while every other counter here already includes
  # the test surface (kotlin passes gen+gen-tests, ts counts both through its
  # tsconfig, swift has a tests step). Rows land under <label> (paths under
  # gen/) and <label>-tests (paths under gen-tests/).
  local label="$1" dir="$2" testdir="${3:-}"
  [ -n "$label" ] && [ -d "$dir" ] || return 0
  local log="$L/count-$label-dart.log"
  # The generated tree lives on the rclone mount, and dart analyze read stale
  # content there (the same tree gave 672 then 725). Mirror to local disk first
  # (PIT-178); the same rule applies to any counter that reads through the mount.
  local mirror="/tmp/warnstd/analyze-$label"
  rm -rf "$mirror"; mkdir -p "$mirror/gen"
  cp -a "$dir"/. "$mirror/gen"/ 2>/dev/null || true
  if [ -n "$testdir" ] && [ -d "$testdir" ]; then
    mkdir -p "$mirror/gen-tests"
    cp -a "$testdir"/. "$mirror/gen-tests"/ 2>/dev/null || true
  fi
  nd "$BORING_WT" "dart analyze $mirror" > "$log" 2>&1
  local ld prefix
  for ld in "$label" "$label-tests"; do
    if [ "$ld" = "$label-tests" ]; then prefix=gen-tests; else prefix=gen; fi
    [ -d "$mirror/$prefix" ] || continue
    grep -E "^ *(error|warning|info) - $prefix/" "$log" | sed -E 's/.* - ([a-z_]+)$/\1/' | sort | uniq -c | sort -rn \
      | awk -v t="$ld" '{c=$1; $1=""; sub(/^ /,""); printf "%s\tdart\t%s\t%d\n", t, $0, c}'
    printf 'dart %-18s issues=%s errors=%s\n' "$ld" \
      "$(grep -cE "^ *(error|warning|info) - $prefix/" "$log")" "$(grep -cE "^ *error - $prefix/" "$log")" >&2
  done
}

count_swift() { # <label> <lib gen dir> [<tests dir>] [<module name>]
  local label="$1" libdir="$2" testdir="${3:-}" mod="${4:-TiqianEngine}"
  local log="$L/count-$label-swift.log" build=/tmp/warnstd/swift-$label
  rm -rf "$build"; mkdir -p "$build"
  # The library step emits the module the test tree imports. Compiling the test
  # tree first stops at "no such module", and a stopped compile reports one
  # error and zero warnings, which reads as a clean tree (PIT-125/PIT-144).
  if [ -d "$libdir" ]; then
    "$SHIM" -swift-version 5 -emit-library -emit-module -module-name "$mod" \
      -I "$BORING_SWIFT_SYSTEM_PACKAGE" -L "$BORING_SWIFT_SYSTEM_PACKAGE" \
      $(find "$libdir" -name '*.swift' | sort) -o "$build/lib$mod.so" > "$log" 2>&1
    grep 'warning:' "$log" | sed 's/^.*warning: //' | norm | sort | uniq -c | sort -rn \
      | awk -v t="$label" '{c=$1; $1=""; sub(/^ /,""); printf "%s\tswift\t%s\t%d\n", t, $0, c}'
    printf 'swift %-22s lib warnings=%s errors=%s\n' "$label" \
      "$(grep -c 'warning:' "$log")" "$(grep -c ': error:' "$log")" >&2
  fi
  if [ -n "$testdir" ] && [ -d "$testdir" ]; then
    local tlog="$L/count-$label-tests-swift.log"
    "$SHIM" -swift-version 5 -I "$build" -L "$build" -l"$mod" -I "$BORING_SWIFT_SYSTEM_PACKAGE" -L "$BORING_SWIFT_SYSTEM_PACKAGE" -lSystemPackage \
      $(find "$testdir" -name '*.swift' | sort) -o "$build/runtests" > "$tlog" 2>&1
    grep 'warning:' "$tlog" | sed 's/^.*warning: //' | norm | sort | uniq -c | sort -rn \
      | awk -v t="$label-tests" '{c=$1; $1=""; sub(/^ /,""); printf "%s\tswift\t%s\t%d\n", t, $0, c}'
    printf 'swift %-22s tests warnings=%s errors=%s\n' "$label" \
      "$(grep -c 'warning:' "$tlog")" "$(grep -c ': error:' "$tlog")" >&2
  fi
}

# tsconfig for a generated tiqian tree: boring's own profile, minus the path map
# that only boring's tree needs.
write_tsconfig() { # <tree root with gen/ and gen-tests/>
  cat > "$1/tsconfig.json" <<EOF
{
  "compilerOptions": {
    "target": "ESNext",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "erasableSyntaxOnly": true,
    "lib": ["ESNext"],
    "types": ["bun"],
    "typeRoots": ["$BORING_WT/node_modules/@types"],
    "strict": true,
    "noImplicitAny": true,
    "noUncheckedIndexedAccess": true,
    "noImplicitOverride": true,
    "noFallthroughCasesInSwitch": true,
    "forceConsistentCasingInFileNames": true,
    "noEmit": true,
    "skipLibCheck": true
  },
  "include": ["gen", "gen-tests"]
}
EOF
}

# ------------------------------------------------------------------ harness
# A reading taken while tracked files are modified describes a tree nobody
# committed (PIT-73), and an interrupted run of the repository's own test suite
# leaves source files rewritten: tests/ts/package-artifacts.test.ts stubs
# samples/boring/MathNaNTestSupport.hx and restores it only on the way out
# (PIT-22). Both make the histogram describe a tree that does not exist.
precondition_clean() { # <checkout> <name>
  local d="$1" name="$2" dirty
  dirty="$(git -C "$d" status --porcelain 2>/dev/null | grep -E '^( M|M |MM| D|D |A )' || true)"
  if [ -n "$dirty" ]; then
    echo "### 前置条件不满足：$name 有已跟踪文件的未提交改动，读数会混进它们（PIT-73）：" >&2
    printf '%s\n' "$dirty" | sed 's/^/    /' >&2
    echo "### 终止：先提交或还原；确知原因时用 ALLOW_DIRTY=1 显式跳过。" >&2
    return 2
  fi
}

measure() {
  local label="$1" do_gen="$2"
  local tsv="$L/$label.tsv"
  local brevi trevi genrev
  brevi="$(git -C "$BORING_WT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  trevi="$(git -C "$TIQIAN_WT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  genrev="$(git -C "$TIQIAN_WT/.haxelib/boring/git" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  echo "### label=$label boring=$brevi tiqian=$trevi generator=$genrev at=$(date -Is)"
  if [ "@{ALLOW_DIRTY:-0}" != "1" ]; then
    precondition_clean "$BORING_WT" "boring 检出" || exit 2
    precondition_clean "$TIQIAN_WT" "tiqian 检出" || exit 2
  fi
  if [ "$do_gen" = gen ]; then gen_boring; gen_tiqian; fi
  write_tsconfig "$TIQIAN_WT/engine-haxe/out/ts"

  {
    echo "# label=$label boring=$brevi tiqian=$trevi generator=$genrev at=$(date -Is)"
    echo "# surface target family count"
    count_kotlin boring-kotlin     "$BORING_WT/reference/kotlin/gen" "$BORING_WT/reference/kotlin/gen-tests"
    count_kotlin boring-kotlin-f32 "$BORING_WT/reference/kotlin-f32/gen" "$BORING_WT/reference/kotlin-f32/gen-tests"
    count_dart   boring-dart       "$BORING_WT/reference/dart/gen" "$BORING_WT/reference/dart/gen-tests"
    count_swift  boring-swift      "$BORING_WT/reference/swift/gen" "$BORING_WT/reference/swift/gen-tests" Codec
    count_swift  boring-swift-f32  "$BORING_WT/reference/swift-f32/gen" "$BORING_WT/reference/swift-f32/gen-tests" CodecF32
    count_kotlin tiqian-kotlin-f32 "$TIQIAN_WT/engine-haxe/out/kotlin-f32/gen" "$TIQIAN_WT/engine-haxe/out/kotlin-f32/gen-tests"
    count_kotlin tiqian-kotlin-f64 "$TIQIAN_WT/engine-haxe/out/kotlin-f64/gen" "$TIQIAN_WT/engine-haxe/out/kotlin-f64/gen-tests"
    count_dart   tiqian-dart       "$TIQIAN_WT/engine-haxe/out/dart/gen" "$TIQIAN_WT/engine-haxe/out/dart/gen-tests"
    count_swift  tiqian-swift-f32  "$TIQIAN_WT/engine-haxe/out/swift-f32/gen" "$TIQIAN_WT/engine-haxe/out/swift-f32/gen-tests"
    count_swift  tiqian-swift-f64  "$TIQIAN_WT/engine-haxe/out/swift-f64/gen" "$TIQIAN_WT/engine-haxe/out/swift-f64/gen-tests"
} > "$tsv.tmp"

  ( cd "$BORING_WT" && bun run typecheck ) > "$L/count-boring-ts.log" 2>&1
  grep -o 'error TS[0-9]*' "$L/count-boring-ts.log" | sort | uniq -c | sort -rn \
| awk '{c=$1; printf "boring-ts\tts\t%s\t%d\n", $2, c}' >> "$tsv.tmp"
  printf 'ts %-20s errors=%s\n' boring-ts "$(grep -c 'error TS' "$L/count-boring-ts.log")" >&2

count_ts tiqian-ts "$TIQIAN_WT/engine-haxe/out/ts/tsconfig.json" >> "$tsv.tmp"
# The histogram is published in one step: a partially written file reads as a
# real reading with missing rows, which is how a run in flight looks like a target
# that dropped to zero (PIT-29's cousin).
mv -f "$tsv.tmp" "$tsv"
echo "### wrote $tsv rows=$(( $(grep -vc '^#' "$tsv") ))"
  awk -F'\t' '!/^#/ {s[$2]+=$4} END {for (k in s) printf "%s=%d ", k, s[k]; print ""}' "$tsv"
}

diff_mode() {
  local base="$1" cur="$2"
  awk -F'\t' '!/^#/ {k=$1"\t"$2"\t"$3; b[k]+=$4} END {for (k in b) print k"\t"b[k]}' "$base" | sort > /tmp/warnstd/base.key
  awk -F'\t' '!/^#/ {k=$1"\t"$2"\t"$3; c[k]+=$4} END {for (k in c) print k"\t"c[k]}' "$cur"  | sort > /tmp/warnstd/cur.key
  join -t "$(printf '\t')" -a1 -a2 -e0 -o '0,1.4,2.4' /tmp/warnstd/base.key /tmp/warnstd/cur.key \
    | awk -F'\t' '$2!=$3 {d=$3-$2; gsub(/\t/, " | ", $1); printf "%+d\t%s\tbase=%s now=%s\n", d, $1, $2, $3}' \
    | sort -rn > /tmp/warnstd/delta.txt
  if [ -s /tmp/warnstd/delta.txt ]; then
    echo "### family deltas (base -> now)"
    cat /tmp/warnstd/delta.txt
    if grep -qE '^\+' /tmp/warnstd/delta.txt; then
      echo "### exit 2: a family rose or appeared"
      return 2
    fi
  else
    echo "### no family changed"
  fi
  return 0
}

case "${1:-}" in
  measure) measure "${2:?label}" gen ;;
  count)   measure "${2:?label}" nocount ;;
  diff)    diff_mode "${2:?base tsv}" "${3:?current tsv}" ;;
  *) echo "usage: tq-warnings.sh measure <label> | count <label> | diff <base.tsv> <cur.tsv>" >&2; exit 2 ;;
esac
