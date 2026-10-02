#!/usr/bin/env bash
# Full recompute verification: manifest vs new execution root vs expected set.
set -uo pipefail
R=/home/losses/Development/tq-workspace
ROOT="$R/publication-staging/execution-option-c-coord"
MF="$R/publication-staging/p09-coord-state/option-c-source-before.json"
python3 - "$ROOT" "$MF" "$R" <<'PY'
import json, hashlib, os, subprocess, sys
root, mf, repo = sys.argv[1:4]
doc = json.load(open(mf))
entries = {e['path']: e for e in doc}
# 1) on-disk source files (exclude node_modules symlink + .haxelib runtime assets)
disk = {}
for dp, dn, fn in os.walk(root):
    dn[:] = [d for d in dn if not os.path.islink(os.path.join(dp,d))]
    if os.path.islink(dp): continue
    for f in fn:
        full = os.path.join(dp, f)
        if '/.haxelib/' in full or os.path.islink(full): continue
        disk[os.path.relpath(full, root)] = full
print(f"[1] root source files = {len(disk)}, manifest entries = {len(entries)}")
print("    extra-on-disk:", sorted(set(disk) - set(entries))[:20])
print("    missing-on-disk:", sorted(set(entries) - set(disk))[:20])
# 2) full recompute sha256+mode
bad = []
for p, e in entries.items():
    full = os.path.join(root, p)
    h = hashlib.sha256(open(full,'rb').read()).hexdigest()
    m = '100755' if os.access(full, os.X_OK) else '100644'
    if h != e['sha256'] or m != e['mode']:
        bad.append((p, e['sha256'][:12], h[:12], e['mode'], m))
print(f"[2] full recompute: {len(entries)} checked, mismatches = {len(bad)}")
for b in bad[:10]: print("   ", b)
# 3) expected set = 1398 + 33
inv = json.load(open(os.path.join(repo,'publication-staging/p09-e1c65975/inventory-1398.json')))['files']
NEW = [p for p in entries if p not in inv]
print(f"[3] expected set: base={len(inv)} + new={len(NEW)} = {len(inv)+len(NEW)}; manifest={len(entries)}")
print("    new paths:"); [print("     ", p) for p in sorted(NEW)]
ok = (len(disk)==len(entries)==len(inv)+33) and not bad and not (set(disk)-set(entries)) and not (set(entries)-set(disk))
print("VERDICT:", "PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
PY
