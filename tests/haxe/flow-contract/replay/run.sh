#!/usr/bin/env bash
# Thin replay caller for the flow contract groups A and C.
#
# It is only a caller. Subprocess capture stays in the existing evidence probe
# (tests/bundle-child-evidence/probe), stage membership stays in the shared
# checker (tests/support/stage-check.sh), and every verdict decision stays in
# the typed interpretation owner (verdict.ts). The probe build itself is the one
# child that runs before the probe exists, so it is captured directly, with its
# command, status and streams retained.
#
# Run inside the repository Nix environment:
#   nix develop -c bash tests/haxe/flow-contract/replay/run.sh
set -euo pipefail

# --- root and working directory -------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPLAY="$(cd "$SCRIPT_DIR" && pwd)"
ROOT="$(cd "$REPLAY/../../../.." && pwd)"
if [ ! -f "$ROOT/boring.json" ] || [ ! -d "$ROOT/tests/haxe/flow-contract" ]; then
    echo "refusing to run: $ROOT does not hold the boring repository" >&2
    exit 2
fi
cd "$ROOT"
# The output root defaults to the ignored tree of this checkout. The
# FLOW_CONTRACT_OUT override exists so a fresh output root can be demonstrated
# without moving or deleting retained attempts.
OUT="${FLOW_CONTRACT_OUT:-out/flow-contract}"
SHARED_STAGE_CHECK="$ROOT/tests/support/stage-check.sh"

for tool in haxe kotlinc cargo rustc java bun haxelib sha256sum find diff; do
    if ! command -v "$tool" > /dev/null 2>&1; then
        echo "refusing to run: $tool is not on the PATH of this environment" >&2
        exit 2
    fi
done
if [ ! -f "$REPLAY/verdict.ts" ]; then
    echo "refusing to run: the typed interpretation owner is missing" >&2
    exit 2
fi

# --- exclusive fresh attempt output ---------------------------------------
# The output root is created first, so a clean checkout reaches the attempt
# allocation; the attempt directory itself is still created exclusively.
mkdir -p "$OUT"
STAMP="$(date +%s%3N)"
ATTEMPT=""
for suffix in "" "-2" "-3" "-4" "-5"; do
    candidate="$OUT/replay-$STAMP-$$$suffix"
    if mkdir "$candidate" 2> /dev/null; then
        ATTEMPT="$candidate"
        break
    fi
done
if [ -z "$ATTEMPT" ]; then
    echo "refusing to run: no fresh attempt directory could be created under $OUT" >&2
    exit 2
fi
echo "attempt directory: $ATTEMPT"
mkdir -p "$ATTEMPT/plans" "$ATTEMPT/reports" "$ATTEMPT/evidence-parent" "$ATTEMPT/bootstrap" "$ATTEMPT/entries" \
    "$ATTEMPT/membership"
: > "$ATTEMPT/stage-results.jsonl"
: > "$ATTEMPT/membership/state.tsv"

# The declared stage list is copied into the attempt before any stage runs, and
# every later decision reads the frozen copy, never the live source manifest.
cp "$REPLAY/stages.json" "$ATTEMPT/manifest-declared.json"

# --- directly captured bootstrap children ---------------------------------
# A pre-probe child cannot run through the probe, so its command, status and
# streams are retained here.
run_captured() {
    local name="$1"
    shift
    printf '%s\n' "$*" > "$ATTEMPT/bootstrap/$name.cmd"
    set +e
    "$@" > "$ATTEMPT/bootstrap/$name.stdout" 2> "$ATTEMPT/bootstrap/$name.stderr"
    local status=$?
    set -e
    printf '%s\n' "$status" > "$ATTEMPT/bootstrap/$name.status"
    return "$status"
}

# --- content identity of the selected input closure -----------------------
hash_closure() {
    {
        find tests/haxe/flow-contract -type f -print0 | sort -z | xargs -0 sha256sum
        find tests/bundle-child-evidence -type f -print0 | sort -z | xargs -0 sha256sum
        find tools/bundle -type f -name '*.hx' -print0 | sort -z | xargs -0 sha256sum
        find packages/compiler -type f -name '*.hx' -print0 | sort -z | xargs -0 sha256sum
        find samples -type f -name '*.hx' -print0 | sort -z | xargs -0 sha256sum
        if [ -f "$SHARED_STAGE_CHECK" ]; then
            sha256sum "$SHARED_STAGE_CHECK"
        fi
        sha256sum haxelib.json defines.json extraParams.hxml boring.json
    }
}

# --- the actual boring class path must belong to this checkout -------------
haxelib path boring > "$ATTEMPT/bootstrap/boring-path.raw" 2> "$ATTEMPT/bootstrap/boring-path.err"
boringPath="$(grep -E '^/' "$ATTEMPT/bootstrap/boring-path.raw" | head -1)"
if [ -z "$boringPath" ] || [[ "$boringPath" != "$ROOT/"* ]]; then
    cp "$REPLAY/stages.json" "$ATTEMPT/manifest-declared.json" 2> /dev/null || true
    cat "$ATTEMPT/bootstrap/boring-path.raw" >&2
    echo "refusing to run: the boring class path does not belong to $ROOT" >&2
    exit 2
fi
reflaxePath="$(haxelib path reflaxe | grep -E '^/' | head -1)"
{
    echo "boring class path: $boringPath (inside this checkout: yes)"
    echo "reflaxe class path: ${reflaxePath:-none} (external dependency)"
    echo "shared stage checker: $SHARED_STAGE_CHECK"
    if [ -f "$SHARED_STAGE_CHECK" ]; then
        echo "shared stage checker present: yes"
    else
        echo "shared stage checker present: no (this revision does not carry it)"
    fi
} > "$ATTEMPT/bootstrap/class-paths.txt"
stageLine() {
    bun "$REPLAY/verdict.ts" stage-line --stage "$1" --state "$2" --detail "$3" \
        --results "$ATTEMPT/stage-results.jsonl" --states "$ATTEMPT/membership/state.tsv"
}

stage_state() {
    awk -F '\t' -v id="$1" '$1 == id { print $2; found = 1 } END { if (!found) print "missing" }' \
        "$ATTEMPT/membership/state.tsv" 2> /dev/null || echo "missing"
}
stageLine "boring-path-check" "ok" "bootstrap/class-paths.txt"

# --- evidence probe, compiled once for this attempt -----------------------
mkdir -p "$ATTEMPT/probe"
sed "s#^-js out/bundle-child-evidence/evidence-probe.js\$#-js $ATTEMPT/probe/evidence-probe.js#" \
    tests/bundle-child-evidence/probe/probe.hxml > "$ATTEMPT/probe.hxml"
diff tests/bundle-child-evidence/probe/probe.hxml "$ATTEMPT/probe.hxml" > "$ATTEMPT/probe.hxml.diff" || true
if run_captured probe-build haxe "$ATTEMPT/probe.hxml"; then
    stageLine "bootstrap-probe" "ok" "bootstrap/probe-build.status"
else
    stageLine "bootstrap-probe" "failed" "the probe build ended nonzero; the command, status and streams are retained"
    echo "the evidence probe could not be built; later stages are not reached" >&2
    exit 1
fi

# --- compiler and runtime identity, captured through the probe ------------
identity_stage() {
    local tool="$1" args="$2"
    cat > "$ATTEMPT/plans/identity-$tool.json" <<EOF
{
  "mode": "capture",
  "projectPath": "$ROOT/tests/haxe/flow-contract/flow/normalized/FlowCases.hx",
  "evidenceParent": "$ATTEMPT/evidence-parent",
  "maxBufferBytes": 2000000,
  "bundle": "flow-contract-replay",
  "action": "identity",
  "step": "$tool",
  "cmd": "$tool",
  "args": $args,
  "cwd": "$ROOT",
  "overrides": []
}
EOF
    set +e
    bun "$ATTEMPT/probe/evidence-probe.js" "$ATTEMPT/plans/identity-$tool.json" \
        > "$ATTEMPT/reports/identity-$tool.json" 2> "$ATTEMPT/reports/identity-$tool.probe.stderr.log"
    local probeStatus=$?
    set -e
    bun "$REPLAY/verdict.ts" judge --report "$ATTEMPT/reports/identity-$tool.json" \
        --stage "identity-$tool" --results "$ATTEMPT/stage-results.jsonl" \
        --states "$ATTEMPT/membership/state.tsv" --probe-exit "$probeStatus" > /dev/null
}

identity_stage haxe '["--version"]'
identity_stage kotlinc '["-version"]'
identity_stage cargo '["--version"]'
identity_stage rustc '["--version"]'
identity_stage java '["--version"]'
identity_stage bun '["--version"]'

# --- before and after content identity ------------------------------------
hash_closure > "$ATTEMPT/hashes-before.txt"
stageLine "hashes-before" "ok" "hashes-before.txt"

# --- per-attempt generation entries ---------------------------------------
# The owned entries keep their content; only the output-defining lines are
# rewritten, so every attempt generates into its own fresh directory and no
# output is copied afterwards.
attempt_entry() {
    local group="$1" entry="$2"
    local src="$REPLAY/../hxml/$entry"
    local dst="$ATTEMPT/entries/$entry"
    sed -e "s#^-D kotlin-output=.*\$#-D kotlin-output=$ATTEMPT/generated-$group/kotlin#" \
        -e "s#^-D rust-output=.*\$#-D rust-output=$ATTEMPT/generated-$group/rust#" \
        -e "s#^-js .*\$#-js $ATTEMPT/generated-$group/haxe/flow-main.js#" \
        "$src" > "$dst"
    diff "$src" "$dst" > "$ATTEMPT/entries/$entry.diff" || true
    echo "$dst"
}

runner_kt() {
    mkdir -p "$ATTEMPT/kotlin-$1"
    sed "s#@PACKAGE@#$2#" "$REPLAY/kotlin-runner.kt.tmpl" > "$ATTEMPT/kotlin-$1/Runner.kt"
}

runner_cargo() {
    local dir="$ATTEMPT/rust-$1-runner"
    mkdir -p "$dir/src"
    sed -e "s#@RUNNER_NAME@#flow-contract-$1-replay#" \
        -e "s#@CRATE_NAME@#$2#" \
        -e "s#@GENERATED@#$4#" "$REPLAY/cargo-runner.toml.tmpl" > "$dir/Cargo.toml"
    sed -e "s#@CRATE@#$3#" -e "s#@MODULE@#$5#" "$REPLAY/cargo-runner-main.rs.tmpl" > "$dir/src/main.rs"
}

# run_stage <id> <dependsOn comma list> <action> <step> <cmd> <project> <args json array>
run_stage() {
    local id="$1" deps="$2" action="$3" step="$4" cmd="$5" project="$6" args="$7"
    if [ -n "$deps" ]; then
        local dep blocked=""
        IFS=',' read -ra depList <<< "$deps"
        for dep in "${depList[@]}"; do
            if [ "$(stage_state "$dep")" != "ok" ]; then
                blocked="$blocked $dep=$(stage_state "$dep")"
            fi
        done
        if [ -n "$blocked" ]; then
            stageLine "$id" "not-reached" "not reached; blocked by$blocked"
            echo "  $id: not reached (blocked by$blocked)"
            return 0
        fi
    fi
    cat > "$ATTEMPT/plans/$id.json" <<EOF
{
  "mode": "capture",
  "projectPath": "$project",
  "evidenceParent": "$ATTEMPT/evidence-parent",
  "maxBufferBytes": 20000000,
  "bundle": "flow-contract-replay",
  "action": "$action",
  "step": "$step",
  "cmd": "$cmd",
  "args": $args,
  "cwd": "$ROOT",
  "overrides": []
}
EOF
    set +e
    bun "$ATTEMPT/probe/evidence-probe.js" "$ATTEMPT/plans/$id.json" \
        > "$ATTEMPT/reports/$id.json" 2> "$ATTEMPT/reports/$id.probe.stderr.log"
    local probeStatus=$?
    set -e
    bun "$REPLAY/verdict.ts" judge --report "$ATTEMPT/reports/$id.json" \
        --stage "$id" --results "$ATTEMPT/stage-results.jsonl" \
        --states "$ATTEMPT/membership/state.tsv" --probe-exit "$probeStatus" > /dev/null
    local state
    state="$(bun "$REPLAY/verdict.ts" state --verdict "$ATTEMPT/reports/$id.verdict.json")"
    echo "  $id: $state"
}

# --- group stages -----------------------------------------------------------
for group in a c; do
    if [ "$group" = "a" ]; then
        pkg="flow.normalized"; crate="flow-contract-a"; ident="flow_contract_a"; module="flow::normalized"; dir="normalized"
    else
        pkg="flow.stable"; crate="flow-contract-c"; ident="flow_contract_c"; module="flow::stable"; dir="stable"
    fi
    caseSrc="tests/haxe/flow-contract/flow/$dir/FlowCases.hx"

    echo "group $group:"
    haxeEntry="$(attempt_entry "$group" "group-$group-haxe-ref.hxml")"
    kotlinEntry="$(attempt_entry "$group" "group-$group-kotlin.hxml")"
    rustEntry="$(attempt_entry "$group" "group-$group-rust.hxml")"

    run_stage "$group-admission" "hashes-before" admission haxe haxe "$ROOT/$caseSrc" "[\"${haxeEntry#./}\"]"
    run_stage "$group-reference" "$group-admission" oracle bun bun "$ROOT/$caseSrc" \
        "[\"$ATTEMPT/generated-$group/haxe/flow-main.js\"]"

    run_stage "$group-kotlin-generation" "" generation haxe haxe "$ROOT/$caseSrc" "[\"${kotlinEntry#./}\"]"
    if [ "$(stage_state "$group-kotlin-generation")" = "ok" ]; then
        gen="$ATTEMPT/generated-$group/kotlin"
        find "$gen" -name '*.kt' | sort > "$ATTEMPT/kotlin-$group.membership.txt"
        runner_kt "$group" "$pkg"
        argsJson="[\"-Xallow-kotlin-package\""
        while IFS= read -r file; do
            [ -z "$file" ] && continue
            argsJson+=",\"${file#./}\""
        done < "$ATTEMPT/kotlin-$group.membership.txt"
        argsJson+=",\"$ATTEMPT/kotlin-$group/Runner.kt\",\"-include-runtime\",\"-d\",\"$ATTEMPT/kotlin-$group/app.jar\"]"
        echo "  kotlin membership: $(grep -c '\.kt$' "$ATTEMPT/kotlin-$group.membership.txt") generated files, every one named by the plan"
        run_stage "$group-kotlin-compile" "$group-kotlin-generation" compile kotlinc kotlinc "$ROOT/$caseSrc" "$argsJson"
    else
        stageLine "$group-kotlin-compile" "not-reached" "not reached; blocked by $group-kotlin-generation"
        echo "  $group-kotlin-compile: not reached"
    fi
    # Java is never launched after a compile that did not end ok.
    run_stage "$group-kotlin-run" "$group-kotlin-compile" run java java "$ROOT/$caseSrc" \
        "[\"-cp\",\"$ATTEMPT/kotlin-$group/app.jar\",\"RunnerKt\"]"

    run_stage "$group-rust-generation" "" generation haxe haxe "$ROOT/$caseSrc" "[\"${rustEntry#./}\"]"
    if [ "$(stage_state "$group-rust-generation")" = "ok" ]; then
        gen="$ATTEMPT/generated-$group/rust"
        find "$gen" -type f | sort > "$ATTEMPT/rust-$group.membership.txt"
        runner_cargo "$group" "$crate" "$ident" "$ROOT/$gen" "$module"
        run_stage "$group-rust-build" "$group-rust-generation" compile cargo cargo "$ROOT/$caseSrc" \
            "[\"build\",\"--manifest-path\",\"$ATTEMPT/rust-$group-runner/Cargo.toml\"]"
    else
        stageLine "$group-rust-build" "not-reached" "not reached; blocked by $group-rust-generation"
        echo "  $group-rust-build: not reached"
    fi
    run_stage "$group-rust-run" "$group-rust-build" run cargo-run cargo "$ROOT/$caseSrc" \
        "[\"run\",\"--manifest-path\",\"$ATTEMPT/rust-$group-runner/Cargo.toml\",\"--quiet\"]"
done

hash_closure > "$ATTEMPT/hashes-after.txt"
if diff -q "$ATTEMPT/hashes-before.txt" "$ATTEMPT/hashes-after.txt" > /dev/null; then
    stageLine "hashes-after" "ok" "the selected input closure is unchanged"
else
    diff "$ATTEMPT/hashes-before.txt" "$ATTEMPT/hashes-after.txt" > "$ATTEMPT/hashes-after.diff" || true
    stageLine "hashes-after" "changed" "see hashes-after.diff"
fi

# --- comparison and membership --------------------------------------------
set +e
bun "$REPLAY/verdict.ts" compare --attempt "$ATTEMPT" --replay "$REPLAY" \
    --manifest "$ATTEMPT/manifest-declared.json" --exclude comparison,membership > /dev/null
compareStatus=$?
set -e
stageLine "comparison" "$([ "$compareStatus" -eq 0 ] && echo ok || echo failed)" "comparison.txt and comparison.json"

membershipState="failed"
if [ -f "$SHARED_STAGE_CHECK" ]; then
    mkdir -p "$ATTEMPT/membership"
    bun "$REPLAY/verdict.ts" stage-ids --manifest "$ATTEMPT/manifest-declared.json" \
        --results "$ATTEMPT/stage-results.jsonl" --out "$ATTEMPT/membership" --exclude membership > /dev/null
    set +e
    source "$SHARED_STAGE_CHECK"
    stage_check "$ATTEMPT/membership/status.tsv" "$ATTEMPT/membership/expected-stages.txt" \
        "$ATTEMPT/membership/findings.txt"
    membershipStatus=$?
    set -e
    if [ "$membershipStatus" -eq 0 ]; then
        membershipState="ok"
        stageLine "membership" "ok" \
            "prefix membership over the recorded results preceding this check; the shared checker reported no identity finding (membership/scope.txt)"
    else
        membershipState="failed"
        stageLine "membership" "failed" \
            "prefix membership over the recorded results preceding this check; the shared checker reported identity findings in membership/findings.txt"
    fi
else
    membershipState="unavailable"
    stageLine "membership" "unavailable" \
        "tests/support/stage-check.sh is not part of this revision, and no private duplicate was substituted"
fi

bun "$REPLAY/verdict.ts" finalize --attempt "$ATTEMPT" --manifest "$ATTEMPT/manifest-declared.json" \
    --comparison-state "$([ "$compareStatus" -eq 0 ] && echo ok || echo failed)" \
    --membership-state "$membershipState" > /dev/null

echo "attempt complete: $ATTEMPT (comparison exit $compareStatus, membership state $membershipState)"
if [ "$membershipState" != "ok" ] || [ "$compareStatus" -ne 0 ]; then
    exit 1
fi
exit 0

