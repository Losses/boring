#!/usr/bin/env bash
# Focused evidence fixture: bind generated outputs to the compiler modules that
# Haxe actually parsed, not merely to the repository revision.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
cd "$ROOT" || exit 2
HAXE="${HAXE:-/nix/store/98pb92k7pi6g5cifmg872jn18kghaxw5-haxe-4.3.7/bin/haxe}"
HAXELIB="${HAXELIB:-$(dirname "$HAXE")/haxelib}"
export PATH="$(dirname "$HAXE"):$PATH"
RUN_PARENT="$ROOT/out/compiler-bytes-provenance/runs"
mkdir -p "$RUN_PARENT" || exit 2
RUN="$(mktemp -d "$RUN_PARENT/run-XXXXXXXX")" || exit 2
OUT="$RUN/generated"
mkdir -p "$OUT" || exit 2
LOG="$RUN/compile.log"
LOADED_ROOT="${COMPILER_ROOT:-$ROOT/packages/compiler}"
EXPECTED_ROOT="$ROOT/packages/compiler"

# haxe -v emits Parsed <absolute .hx> for the modules used by this invocation.
# This is stronger than haxelib path: it is emitted by the compiler during the
# load itself. Keep only compiler-package paths for the identity record.
"$HAXE" -lib reflaxe -cp "$LOADED_ROOT" -cp "$HERE" -main Main -js "$OUT/out.js" \
    --macro "Intercept.run(['tests/haxe/compiler-bytes-provenance'])" \
    -D source-map -v >"$LOG" 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then
    cat "$LOG"
    exit "$rc"
fi

python3 - "$LOG" "$RUN/compiler-modules.sha256" "$LOADED_ROOT" "$EXPECTED_ROOT" <<'PY'
import hashlib, os, re, sys
log, manifest, loaded_root, expected_root = sys.argv[1:]
loaded_root = os.path.realpath(loaded_root)
expected_root = os.path.realpath(expected_root)
paths = []
for line in open(log, encoding="utf-8", errors="replace"):
    m = re.match(r"Parsed (/.+\.hx)\s*$", line)
    if m:
        p = os.path.realpath(m.group(1))
        if p.startswith(loaded_root + os.sep) and p not in paths:
            paths.append(p)
if not paths:
    raise SystemExit("no loaded compiler modules were reported by haxe -v")
with open(manifest, "w") as f:
    for p in sorted(paths):
        rel = os.path.relpath(p, loaded_root)
        expected = os.path.join(expected_root, rel)
        actual_hash = hashlib.sha256(open(p, 'rb').read()).hexdigest()
        expected_hash = hashlib.sha256(open(expected, 'rb').read()).hexdigest()
        f.write(f"path={p}\nsha256={actual_hash}\nexpected-path={expected}\nexpected-sha256={expected_hash}\n")
        if p != os.path.join(expected_root, rel) or actual_hash != expected_hash:
            raise SystemExit(f"FAIL: compiler module identity mismatch: {p} sha256={actual_hash} expected={expected_hash}")
PY
identity_rc=$?
if [ "$identity_rc" -ne 0 ]; then
    cat "$RUN/compiler-modules.sha256" 2>/dev/null || true
    exit "$identity_rc"
fi

# E1 is retained as a resolver observation; it is not substituted for the
# compiler's Parsed evidence above.
"$HAXELIB" path boring >"$RUN/haxelib-path-boring.txt" 2>&1
printf 'haxe=%s\nhaxelib=%s\n' "$HAXE" "$HAXELIB" >"$RUN/toolchain.txt"
sha256sum "$OUT"/out.js "$OUT"/out.js.map >"$RUN/generated-output.sha256"
cat "$RUN/compiler-modules.sha256" >>"$RUN/generated-output.sha256"
printf 'compiler-module-manifest=%s\noutput-manifest=%s\n' \
    "$RUN/compiler-modules.sha256" "$RUN/generated-output.sha256" >"$RUN/binding.txt"
printf 'PASS run=%s\n' "$RUN"
exit 0
