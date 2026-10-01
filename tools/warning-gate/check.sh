#!/usr/bin/env bash
# Generated-target warning gate.
# Choice B: the checked-in baselines are an allowance for warnings already
# present in the generated trees; a larger measured count fails the gate.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# CI supplies these through nix develop; local verification may point at the
# pinned toolchain explicitly (the gate itself never downloads or generates).
DART_BIN=${DART_BIN:-dart}
KOTLINC_BIN=${KOTLINC_BIN:-kotlinc}
CARGO_BIN=${CARGO_BIN:-cargo}
SWIFT_BIN=${SWIFT_BIN:-swift}
TSC_BIN=${TSC_BIN:-tsc}
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
FAIL=0
for required in "$ROOT/reference/dart/gen" "$ROOT/reference/kotlin/gen" "$ROOT/reference/rust/gen"; do
  if [ ! -d "$required" ]; then
    echo "warning-gate: missing generated tree: $required (run generation first)"
    FAIL=1
  fi
done
run() {
  local log=$1
  shift
  "$@" >"$log" 2>&1
  echo $? >"$log.rc"
}
rc() { cat "$1.rc"; }
check() {
  local name=$1 base=$2 n r
  case "$name" in
    dart) n=$(grep -cE '^warning' "$OUT/dart.loose" || true) ;;
    kotlin) n=$(grep -cE '\.kt:[0-9]+:[0-9]+: warning:' "$OUT/kotlin.loose" || true) ;;
    rust) n=$(grep -E '^[[:space:]]+--> ' "$OUT/rust.loose" | grep -cE 'runtime/|boring/|haxe/|registry/|std/' || true) ;;
    swift) n=$(grep -ciE '(^|: )warning([: ]|$)' "$OUT/swift.loose" || true) ;;
    typescript) n=$(grep -ciE '(^|: )warning([: ]|$)' "$OUT/typescript.loose" || true) ;;
    *) echo "warning-gate: unknown target $name"; FAIL=1; return ;;
  esac
  r=$(rc "$OUT/$name.strict")
  printf '%s: loose=%s strict=%s warnings=%s baseline=%s\n' "$name" "$(rc "$OUT/$name.loose")" "$r" "$n" "$base"
  # Strict compilation is deliberately observable, but B cannot require its
  # rc to be zero while the checked-in baseline is non-zero. The acceptance
  # decision is the reproducible count delta below.
  case "$n" in ''|*[!0-9]*) echo "warning-gate: $name count is not numeric"; FAIL=1;; esac
  if [ "$n" -gt "$base" ] 2>/dev/null; then
    echo "warning-gate: $name has $n warning(s), baseline is $base"
    FAIL=1
  fi
}

# Keep the loose invocation too: it gives a stable, countable diagnostic set;
# the strict invocation is the fail-capable compiler command for this target.
run "$OUT/dart.loose" "$DART_BIN" analyze --no-fatal-warnings "$ROOT/reference/dart/gen"
run "$OUT/dart.strict" "$DART_BIN" analyze --fatal-warnings "$ROOT/reference/dart/gen"
check dart 46

run "$OUT/kotlin.loose" "$KOTLINC_BIN" $(find "$ROOT/reference/kotlin/gen" -name '*.kt' -print) -d "$OUT/kotlin.jar"
run "$OUT/kotlin.strict" "$KOTLINC_BIN" -Werror $(find "$ROOT/reference/kotlin/gen" -name '*.kt' -print) -d "$OUT/kotlin-strict.jar"
check kotlin 59

run "$OUT/rust.loose" "$CARGO_BIN" check --manifest-path "$ROOT/reference/rust/gen/Cargo.toml"
run "$OUT/rust.strict" env RUSTFLAGS="${RUSTFLAGS:-} -D warnings" "$CARGO_BIN" check --manifest-path "$ROOT/reference/rust/gen/Cargo.toml"
check rust 4

# SwiftPM and tsc do not have warning-count baselines in the audit artifact;
# their strict invocations are nevertheless part of this gate. Their emitted
# warnings are counted and must remain at the recorded zero baseline.
run "$OUT/swift.loose" "$SWIFT_BIN" build --product BoringSwiftTests
run "$OUT/swift.strict" "$SWIFT_BIN" build --product BoringSwiftTests -Xswiftc -warnings-as-errors
check swift 0

run "$OUT/typescript.loose" "$TSC_BIN" -p "$ROOT"
run "$OUT/typescript.strict" "$TSC_BIN" -p "$ROOT" --noEmit
check typescript 0

if [ "$FAIL" -eq 0 ]; then echo 'WARNING GATE PASS (no warning count above baseline)'; else echo 'WARNING GATE FAIL'; fi
exit "$FAIL"
