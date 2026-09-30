#!/usr/bin/env bash
# Roots-manifest consistency guard (precision-switch bundles).
#
# Invariant (feature specs 19 and 23): every root module listed in a base
# target's hxml must also be listed in that target's f32 variant, so the
# cross-target test id set stays equal across the precision switch. The f32
# roots lists are hand-maintained; this guard catches the drift that left
# the 2026-09-04..09-26 test modules out of the f32 binaries (see
# dc-warn/out/f32-divergence/REPORT.md).
#
# A pair may carry an explicit exemption in roots-allowlist.json, but every
# entry must state a reason; reasonless exemptions are rejected.
#
# Usage: check-roots-guard.sh [examples-dir]
set -u
here="$(cd "$(dirname "$0")" && pwd)"
examples="${1:-$here/../../examples}"
allowlist="$here/roots-allowlist.json"
fail=0
exemptions=0
list_reason() {
    node -e '
        const fs=require("fs");
        const mod=process.argv[1], target=process.argv[2], p=process.argv[3];
        if(!fs.existsSync(p)) process.exit(0);
        const list=JSON.parse(fs.readFileSync(p,"utf8")).exempt||[];
        const hit=list.find(e=>e.module===mod&&e.target===target);
        if(hit&&hit.reason) console.log(hit.reason);
    ' "$1" "$2" "$3"
}
for target in kotlin rust swift; do
    base="$examples/$target.hxml"
    f32="$examples/$target-f32.hxml"
    ok=1
    for f in "$base" "$f32"; do
        if [ ! -f "$f" ]; then
            echo "FAIL: missing file: $f"
            fail=1; ok=0
        fi
    done
    [ "$ok" -eq 1 ] || continue
    # A roots line is a bare module path: identifier segments joined by dots.
    missing="$(comm -23 \
        <(grep -E '^[A-Za-z_][A-Za-z0-9_.]*$' "$base" | sort -u) \
        <(grep -E '^[A-Za-z_][A-Za-z0-9_.]*$' "$f32" | sort -u))"
    if [ -z "$missing" ]; then
        echo "OK: $target-f32.hxml roots cover $target.hxml"
        continue
    fi
    while IFS= read -r mod; do
        [ -z "$mod" ] && continue
        reason="$(list_reason "$mod" "$target" "$allowlist")"
        if [ -n "$reason" ]; then
            exemptions=$((exemptions+1))
            echo "EXEMPT: $target-f32.hxml may omit $mod -- $reason"
        else
            echo "FAIL: $target-f32.hxml omits root module $mod (present in $target.hxml); add it, or exempt it with a reason in $allowlist"
            fail=1
        fi
    done <<< "$missing"
done
if [ -f "$allowlist" ]; then
    node -e '
        const fs=require("fs");
        const list=JSON.parse(fs.readFileSync(process.argv[1],"utf8")).exempt||[];
        let bad=0;
        for(const e of list){
            if(!e.module||!e.target||!e.reason||!String(e.reason).trim()){
                console.error("FAIL: allowlist entry without module/target/reason: "+JSON.stringify(e));
                bad=1;
            }
        }
        process.exit(bad);
    ' "$allowlist" || fail=1
fi
if [ "$fail" -ne 0 ]; then
    echo "roots guard: FAILED"
    exit 1
fi
echo "roots guard: PASS ($exemptions exemption(s) in force)"
