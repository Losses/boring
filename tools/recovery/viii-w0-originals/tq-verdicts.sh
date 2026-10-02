#!/usr/bin/env bash
# tq-verdicts.sh — run the six tiqian bundles and compare their per-case verdicts
# with the frozen baseline.
#
# usage:
#   bash tq-verdicts.sh run     <label> [boring-wt] [tiqian-wt]
#   bash tq-verdicts.sh compare <label>
#
# "run" generates nothing: it assumes the bundle trees are already generated
# from the checkout you mean to test (the generator revision is whatever that
# tiqian worktree's .haxelib/boring/git resolves to, and it is printed).
# Kotlin/TS/Dart go through the bundle driver; Swift cannot, because the driver
# builds its test executable under the generated tree and the rclone scratch
# disk refuses to execute anything (chmod +x has no effect there), so Swift is
# compiled into /tmp by the shim and run from there.
#
# The comparison is per case id, never by count: a target that swaps one pass
# for another keeps its total (PIT-2).
set -u
W=/home/losses/Development/tq-workspace
L="${W}/.tq-logs/warnstd/verdicts"
BASE="${W}/dc-warn/warn/warnstd/verdict-baseline"
export XDG_CACHE_HOME="${W}/.nix-cache"
export PATH=/tmp/swift-shim/bin:$PATH
export BORING_SWIFT_SYSTEM_PACKAGE=${BORING_SWIFT_SYSTEM_PACKAGE:-/tmp/swift-shim/system-package}
export SDKROOT=${SDKROOT:-/tmp/composed-sdk}
IDS="kotlin-f32 kotlin-f64 ts dart swift-f32 swift-f64"

run_bundle() { # <id> <boring-wt> <tiqian-wt> <outdir>
  local id="$1" BO="$2" TI="$3" OUT="$4"
  case "$id" in
    swift-*)
      local B=/tmp/warnstd/verdict-$id
      rm -rf "$B"; mkdir -p "$B"
      /tmp/swift-shim/swiftc-shim.sh -swift-version 5 -emit-library -emit-module -module-name TiqianEngine \
        -I /tmp/swift-shim/system-package -L /tmp/swift-shim/system-package \
        $(find "$TI/engine-haxe/out/$id/gen" -name '*.swift' | sort) -o "$B/libTiqianEngine.so" > "$B/lib.log" 2>&1
      local lrc=$?
      /tmp/swift-shim/swiftc-shim.sh -swift-version 5 -I "$B" -L "$B" -lTiqianEngine -I "$BORING_SWIFT_SYSTEM_PACKAGE" -L "$BORING_SWIFT_SYSTEM_PACKAGE" -lSystemPackage \
        $(find "$TI/engine-haxe/out/$id/gen-tests" -name '*.swift' | sort) -o "$B/runtests" > "$B/tests.log" 2>&1
      local trc=$?
      rm -f "$OUT/$id.jsonl"
      LD_LIBRARY_PATH="$B" BORING_TEST_RESULTS="$OUT/$id.jsonl" BORING_TEST_TIMEOUT_MS=600000 \
        timeout 7200 "$B/runtests" > "$B/run.log" 2>&1
      local rrc=$?
      printf '%-11s lib=%s tests=%s run=%s records=%s\n' "$id" "$lrc" "$trc" "$rrc" \
        "$( [ -f "$OUT/$id.jsonl" ] && wc -l < "$OUT/$id.jsonl" || echo 0)"
      ;;
    *)
      ( cd "$TI" && nix develop -c bash -c "bun $BO/out/bundle/driver.js test $id" ) > "$OUT/$id.log" 2>&1
      local rc=$?
      [ -f "$TI/engine-haxe/out/test-results/$id.jsonl" ] && cp "$TI/engine-haxe/out/test-results/$id.jsonl" "$OUT/$id.jsonl"
      printf '%-11s rc=%s records=%s\n' "$id" "$rc" "$( [ -f "$OUT/$id.jsonl" ] && wc -l < "$OUT/$id.jsonl" || echo 0)"
      ;;
  esac
}

do_run() {
  local label="$1" BO="${2:-$W/boring-wt-warnstd}" TI="${3:-$W/tiqian-wt-warnstd}"
  local OUT="$L/$label"
  rm -rf "$OUT"; mkdir -p "$OUT"
  echo "### label=$label boring=$(git -C "$BO" rev-parse --short HEAD) tiqian=$(git -C "$TI" rev-parse --short HEAD) generator=$(git -C "$TI/.haxelib/boring/git" rev-parse --short HEAD) at=$(date -Is)"
  local id
  for id in $IDS; do run_bundle "$id" "$BO" "$TI" "$OUT"; done
  echo "### 结果目录 $OUT"
}

do_compare() {
  local label="$1" OUT="$L/$1"
  [ -d "$OUT" ] || { echo "没有 $OUT"; exit 2; }
  python3 - "$BASE" "$OUT" <<'PY'
import json, sys, pathlib
base, cur = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
def load(p):
    d = {}
    for line in p.read_text().splitlines():
        if not line.strip(): continue
        o = json.loads(line); d[o.get("id")] = o.get("verdict")
    return d
bad = 0
for name in ["kotlin-f32","kotlin-f64","ts","dart","swift-f32","swift-f64"]:
    b, c = base/("%s.jsonl"%name), cur/("%s.jsonl"%name)
    if not c.exists():
        print("%-11s 缺结果文件" % name); bad = 1; continue
    B, C = load(b), load(c)
    lost = sorted(set(B) - set(C)); gained = sorted(set(C) - set(B))
    changed = [(k, B[k], C[k]) for k in sorted(set(B) & set(C)) if B[k] != C[k]]
    line = "%-11s base=%d now=%d 丢失=%d 新增=%d 判定变化=%d" % (name, len(B), len(C), len(lost), len(gained), len(changed))
    print(line)
    for k, x, y in changed[:8]:
        print("   变化 %s: %s -> %s" % (k, x, y))
        if y in ("fail", "timeout") or x in ("pass",) and y != "pass":
            bad = 1
    if lost:
        print("   丢失 id 例:", lost[:3]); bad = 1
    if gained:
        print("   新增 id 例:", gained[:3])
print("### 结论:", "有回归" if bad else "与基线逐条一致")
sys.exit(bad)
PY
}

case "${1:-}" in
  run)     do_run "${2:?label}" "${3:-}" "${4:-}" ;;
  compare) do_compare "${2:?label}" ;;
  *) echo "usage: tq-verdicts.sh run <label> [boring-wt] [tiqian-wt] | compare <label>" >&2; exit 2 ;;
esac
