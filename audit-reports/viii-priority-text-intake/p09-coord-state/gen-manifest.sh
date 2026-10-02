#!/usr/bin/env bash
# Generate SOURCE_MANIFEST for coordination-state execution root execution-option-c-coord.
# Expected set = git ls-tree -r e1c65975 (1398 paths) with 6 files at coordination-tree
# current bytes, PLUS new fixture paths (coordination tree untracked).
# Source-of-truth for bytes: the new execution root itself (full recompute).
# Usage: bash gen-manifest.sh <repo-root>
set -euo pipefail
R="${1:?repo root}"
ST="$R/publication-staging"
ROOT="$ST/execution-option-c-coord"
OUT="$ST/p09-coord-state/option-c-source-before.json"
INV="$ST/p09-e1c65975/inventory-1398.json"
python3 - "$R" "$ROOT" "$INV" "$OUT" <<'PY'
import json, hashlib, subprocess, sys, os
repo, root, inv_path, out_path = sys.argv[1:5]
inv = json.load(open(inv_path))['files']
tree = 'e1c6597514634fd347d392709793cc19bd96c9a2'
out = subprocess.check_output(['git','-C',os.path.join(repo,'boring'),'ls-tree','-r',tree]).decode()
modes = {}
for line in out.splitlines():
    meta, path = line.split('\t', 1)
    modes[path.replace('"','').encode().decode('unicode_escape')] = meta.split()[0]
NEW = [
    "tests/haxe/dc-null-guard-fallthrough/dcguard/DcGuard.hx",
    "tests/haxe/dc-null-guard-fallthrough/expected.txt",
    "tests/haxe/dc-null-guard-fallthrough/gen/dart.hxml",
    "tests/haxe/dc-null-guard-fallthrough/gen/kotlin.hxml",
    "tests/haxe/dc-null-guard-fallthrough/native/main.dart",
    "tests/haxe/dc-null-guard-fallthrough/run.sh",
    "tests/haxe/try-tail-min/expected.txt",
    "tests/haxe/try-tail-min/gen/rust.hxml",
    "tests/haxe/try-tail-min/native/harness.rs",
    "tests/haxe/try-tail-min/trytailmin/MinOracle.hx",
    "tests/haxe/swift-rt-probe/expected.txt",
    "tests/haxe/swift-rt-probe/gen/swift.hxml",
    "tests/haxe/swift-rt-probe/probe/Probe.hx",
    "tests/haxe/swift-rt-probe/native/native-main.swift",
    "tests/haxe/swift-rt-plain/expected.txt",
    "tests/haxe/swift-rt-plain/gen/swift.hxml",
    "tests/haxe/swift-rt-plain/plain/Plain.hx",
    "tests/haxe/swift-rt-plain/native/native-main.swift",
    "tests/haxe/try-tail/expected.txt",
    "tests/haxe/try-tail/gen/dart.hxml",
    "tests/haxe/try-tail/gen/kotlin.hxml",
    "tests/haxe/try-tail/gen/rust.hxml",
    "tests/haxe/try-tail/gen/swift.hxml",
    "tests/haxe/try-tail/gen/ts.hxml",
    "tests/haxe/try-tail/native/harness.rs",
    "tests/haxe/try-tail/native/main.dart",
    "tests/haxe/try-tail/native/main.js",
    "tests/haxe/try-tail/native/Main.kt",
    "tests/haxe/try-tail/native/native-main.swift",
    "tests/haxe/try-tail/oracle.hxml",
    "tests/haxe/try-tail/run-stages.sh",
    "tests/haxe/try-tail/trytail/TryTailOracle.hx",
    "tests/support/stage-check-control.sh",
]
result, missing = [], []
for path in sorted(list(inv) + NEW):
    full = os.path.join(root, path)
    if not os.path.isfile(full):
        missing.append(path); continue
    h = hashlib.sha256(open(full,'rb').read()).hexdigest()
    # mode: fixtures are not in the e1c65975 tree -> read from filesystem
    mode = modes.get(path)
    if mode is None:
        mode = '100755' if os.access(full, os.X_OK) else '100644'
    result.append({"path": path, "sha256": h, "mode": mode})
assert not missing, missing
os.makedirs(os.path.dirname(out_path), exist_ok=True)
json.dump(result, open(out_path,'w'), indent=2, ensure_ascii=False)
print(f"wrote {len(result)} entries -> {out_path}")
PY
