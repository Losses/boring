#!/usr/bin/env bash
# Static verification for the P09 f32 baseline prep (t-mup4nyxh-mlvw).
# Verifies, without generating anything:
#   1. SOURCE_MANIFEST entries: prep inputs/ copy sha256 == recorded candidateSha256, 15/15
#   2. PrintedFloatTests content anchor in manifest == actual sha256 of inputs copy
#   3. status=preparation-only-not-executed and generationStarted=false in both JSON files
#   4. expected.json exempts exactly the 6 PrintedFloatTests ids
#   5. exempted ids match the extra-id-allowlist.json copy exactly
set -euo pipefail
cd "$(dirname "$0")"
fail=0
python3 - <<'EOF' || fail=1
import hashlib, json, sys
man = json.load(open("SOURCE_MANIFEST.json"))
exp = json.load(open("expected.json"))
def sha(p): return hashlib.sha256(open(p,'rb').read()).hexdigest()
assert man["status"] == "preparation-only-not-executed", "status"
assert man["generationStarted"] is False, "generationStarted"
assert exp["status"] == "preparation-only-not-executed", "exp status"
assert exp["generationStarted"] is False, "exp generationStarted"
assert man["sourceManifest"]["entryCount"] == 15
for e in man["sourceManifest"]["entries"]:
    assert e["prepCopySha256"] == sha("inputs/" + e["path"]), e["path"]
    assert e["candidateSha256"] == e["prepCopySha256"], e["path"]
pft = man["printedFloatTests"]
assert pft["contentAnchorSha256"] == sha("inputs/samples/tests/f32/PrintedFloatTests.hx")
assert len(pft["ids"]) == 6
assert exp["exemptedIds"]["ids"] == pft["ids"]
allow = json.load(open("inputs/tools/test-consistency/extra-id-allowlist.json"))
allow_ids = sorted(x["id"] if isinstance(x, dict) else x for x in allow["extras"])
assert allow_ids == sorted(pft["ids"]), allow_ids
assert exp["carryOverFacts"]["p09Verdict"].startswith("NOT PASSED")
assert "NOT executed" in exp["carryOverFacts"]["tiqianGate"]
print("static verify: PASS (15/15 hashes, 6/6 exemption binding, generationStarted=false)")
EOF
[ "$fail" = 0 ] && echo "verify-prep rc=0" || { echo "verify-prep rc=1"; exit 1; }
