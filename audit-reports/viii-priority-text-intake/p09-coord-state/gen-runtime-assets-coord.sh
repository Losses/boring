#!/usr/bin/env bash
# Runtime-asset manifest for execution root execution-option-c-coord.
# Same structure/format as p09-e1c65975/runtime-assets.json (runtime-assets-v1).
# Usage: bash gen-runtime-assets-coord.sh <repo-root>
set -euo pipefail
R="${1:?repo root}"
ROOT="$R/publication-staging/execution-option-c-coord"
OUT="$R/publication-staging/p09-coord-state/runtime-assets.json"
python3 - "$ROOT" "$OUT" "$R" <<'PY'
import json, hashlib, os, glob, sys
root, out_path, repo = sys.argv[1:4]
patterns = [".haxelib/*/.dev", ".haxelib/*/.current", "haxelib.json",
            "extraParams.hxml", "defines.json", "boring.json"]
entries, seen = [], set()
for pat in patterns:
    for full in sorted(glob.glob(os.path.join(root, pat))):
        if not os.path.isfile(full): continue
        rel = os.path.relpath(full, root)
        if rel in seen: continue
        seen.add(rel)
        h = hashlib.sha256(open(full, "rb").read()).hexdigest()
        kind = ("haxelib-dev-pointer" if rel.endswith("/.dev")
                else "haxelib-current-pin" if rel.endswith("/.current")
                else "build-config")
        entries.append({"path": rel, "sha256": h, "kind": kind,
                        "content": open(full).read().strip()})
doc = {"format": "runtime-assets-v1", "execution_root": root, "repo_root": repo,
       "note": "Runtime loader/mapping assets only; source files are covered by option-c-source-before.json (1431 entries) in this directory.",
       "count": len(entries), "assets": entries}
json.dump(doc, open(out_path, "w"), indent=2, ensure_ascii=False)
print(f"wrote {len(entries)} runtime assets -> {out_path}")
for e in entries: print(f"  [{e['kind']}] {e['path']} = {e['content'][:70]}")
PY
