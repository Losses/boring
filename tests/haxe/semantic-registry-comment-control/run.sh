#!/usr/bin/env bash
set -u

# Comment and string negative controls for SemanticPassRegistry validation.
# The registry must treat a module name that appears only inside a comment
# or only inside a string literal as a nonconsumer, must not confuse the
# module with a longer name that shares its prefix, and must accept a
# target that imports and calls the module. The control runs the real
# registry validation over sandbox copies of the compiler package inside
# this run's output directory.

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
cd "$ROOT" || exit 2
if [ "${IN_NIX_SHELL:-}" = "" ]; then
    exec nix develop -c bash "$HERE/run.sh"
fi

PARENT=out/semantic-registry-comment-control
mkdir -p "$PARENT" || exit 2
RUN="$(mktemp -d "$PARENT/attempt-XXXXXXXX")" || exit 2
printf '%s\n' "$RUN"

INPUTS=(
    packages/compiler/SemanticPassRegistry.hx
    packages/compiler/SemanticExceptionLedger.hx
    "$HERE/run.sh"
)
sha256sum "${INPUTS[@]}" >"$RUN/input-sha256.txt" || exit 2

run_stage() {
    local name="$1"
    shift
    printf '%q ' "$@" >"$RUN/$name.command"
    printf '\n' >>"$RUN/$name.command"
    "$@" >"$RUN/$name.stdout" 2>"$RUN/$name.stderr"
    local status=$?
    printf '%s\n' "$status" >"$RUN/$name.status"
    printf '%s status=%s\n' "$name" "$status"
    return "$status"
}

# Insert a registry row for one synthetic module and copy the prepared
# probe file into the ts target.
add_probe() {
    local sandbox="$1" module="$2" probe="$3"
    python3 - "$sandbox" "$module" "$probe" <<'PYEDIT' || return 1
import sys
root, module, probe = sys.argv[1], sys.argv[2], sys.argv[3]
registry = root + "/packages/compiler/SemanticPassRegistry.hx"
src = open(registry).read()
row = '        {module: "%s", targets: ["ts"]},\n' % module
marker = "    static final consumers:Array<{module:String, targets:Array<String>}> = [\n"
assert marker in src
open(registry, "w").write(src.replace(marker, marker + row))
open(root + "/packages/compiler/reflaxe/ts/tscompiler/" + module + ".hx", "w").write(open(probe).read())
PYEDIT
}

# Sandbox 1, positive control: the untouched package validates.
rm -rf "$RUN/sandbox-real"
mkdir -p "$RUN/sandbox-real/packages/compiler"
cp -r packages/compiler/. "$RUN/sandbox-real/packages/compiler/"
run_stage positive-real-tree \
    haxe -cp "$RUN/sandbox-real/packages/compiler" \
    --macro "SemanticPassRegistry.validate()" || exit 1

# Negative control helper: validation must fail with the registry
# diagnostic for the synthetic module.
expect_reject() {
    local name="$1" sandbox="$2" module="$3"
    run_stage "$name" \
        haxe -cp "$sandbox/packages/compiler" \
        --macro "SemanticPassRegistry.validate()"
    if [ "$?" -eq 0 ]; then
        printf '%s validated as a consumer\n' "$name" >"$RUN/$name.reason"
        return 1
    fi
    grep -q "does not consume registered shared mechanism $module" \
        "$RUN/$name.stderr" || return 1
    return 0
}

# Sandbox 2, negative control: the module name appears only inside a
# comment.
rm -rf "$RUN/sandbox-comment-only"
mkdir -p "$RUN/sandbox-comment-only/packages/compiler"
cp -r packages/compiler/. "$RUN/sandbox-comment-only/packages/compiler/"
cat >"$RUN/probe-comment-only.hx" <<'PROBE' || exit 2
/* CommentOnlyProbe appears here only inside a comment. */
class CommentOnlyProbeHolder {}
PROBE
add_probe "$RUN/sandbox-comment-only" CommentOnlyProbe "$RUN/probe-comment-only.hx" || exit 2
expect_reject negative-comment-only "$RUN/sandbox-comment-only" CommentOnlyProbe || exit 1

# Sandbox 3, negative control: the module name appears only inside a
# string literal.
rm -rf "$RUN/sandbox-string-only"
mkdir -p "$RUN/sandbox-string-only/packages/compiler"
cp -r packages/compiler/. "$RUN/sandbox-string-only/packages/compiler/"
cat >"$RUN/probe-string-only.hx" <<'PROBE' || exit 2
class StringOnlyProbeHolder {
    public static var label:String = "StringOnlyProbe.marker()";
}
PROBE
add_probe "$RUN/sandbox-string-only" StringOnlyProbe "$RUN/probe-string-only.hx" || exit 2
expect_reject negative-string-only "$RUN/sandbox-string-only" StringOnlyProbe || exit 1

# Sandbox 4, negative control: a longer module shares the prefix and is
# imported and called; the listed module itself is absent.
rm -rf "$RUN/sandbox-prefix"
mkdir -p "$RUN/sandbox-prefix/packages/compiler"
cp -r packages/compiler/. "$RUN/sandbox-prefix/packages/compiler/"
cat >"$RUN/probe-prefix.hx" <<'PROBE' || exit 2
import PrefixProbeExtra;
class PrefixProbeHolder {
    public static function marker():String {
        return PrefixProbeExtra.marker();
    }
}
class PrefixProbeExtra {
    public static function marker():String {
        return "PrefixProbeExtra";
    }
}
PROBE
add_probe "$RUN/sandbox-prefix" PrefixProbe "$RUN/probe-prefix.hx" || exit 2
expect_reject negative-prefix-only "$RUN/sandbox-prefix" PrefixProbe || exit 1

# Sandbox 5, positive twin: the same synthetic module with a real import
# and call validates.
rm -rf "$RUN/sandbox-real-probe"
mkdir -p "$RUN/sandbox-real-probe/packages/compiler"
cp -r packages/compiler/. "$RUN/sandbox-real-probe/packages/compiler/"
cat >"$RUN/probe-real.hx" <<'PROBE' || exit 2
import RealProbe;
class RealProbe {
    public static function marker():String {
        return "RealProbe";
    }
}
class RealProbeHolder {
    public static function marker():String {
        return RealProbe.marker();
    }
}
PROBE
add_probe "$RUN/sandbox-real-probe" RealProbe "$RUN/probe-real.hx" || exit 2
run_stage positive-real-probe \
    haxe -cp "$RUN/sandbox-real-probe/packages/compiler" \
    --macro "SemanticPassRegistry.validate()" || exit 1

sha256sum "${INPUTS[@]}" >"$RUN/input-sha256-after.txt" || exit 2
cmp "$RUN/input-sha256.txt" "$RUN/input-sha256-after.txt" || exit 2
printf 'registry comment control passed: %s\n' "$RUN"
