#!/usr/bin/env bash
# 承重断言脚本：重跑 t-mum29cli-9c9w 的宽松/严格对照，核对 rc 与 warning 计数。
# 用法: ./verify.sh <dart-bin> <cargo-bin>
#   例: ./verify.sh /nix/store/vsv6nwqv7g9vdkyj2paxa9g8vki0svvy-dart-3.13.3/bin/dart \
#                  /nix/store/agfrkw7lvckq29w4dp0i3jfrhxjmgv3q-rust-default-1.98.0/bin/cargo
# 退出码: 0 = 全部断言通过; 1 = 任一断言失败。
# 只读：不修改仓库；受控样本在 /tmp，用完清理。
set -u

DART="${1:?usage: verify.sh <dart-bin> <cargo-bin>}"
CARGO="${2:?usage: verify.sh <dart-bin> <cargo-bin>}"
# cargo needs rustc on PATH
RUSTC_DIR="$(cd "$(dirname "$CARGO")" && pwd)"
export PATH="$RUSTC_DIR:$PATH"
FAIL=0

# ---------- Dart 受控样本 ----------
DART_SAMPLE=$(mktemp -d)
mkdir -p "$DART_SAMPLE/lib"
cat > "$DART_SAMPLE/lib/sample.dart" <<'EOF'
// Controlled sample: one unused local variable -> dart lint warning
int compute(int x) {
  final unused = x * 2; // unused_local_variable
  return x + 1;
}
EOF
DART_HASH=$(sha256sum "$DART_SAMPLE/lib/sample.dart" | cut -d' ' -f1)
[ "$DART_HASH" = "fcfb91ed50b518e8905f44f8ae6bfb74ab4d32a7f117168b49d573c4d85807ae" ] \
  || { echo "FAIL dart sample hash mismatch: $DART_HASH"; FAIL=1; }

"$DART" analyze --no-fatal-warnings "$DART_SAMPLE" >/tmp/wg-verify-dart-loose.log 2>&1
DART_LOOSE_RC=$?
"$DART" analyze --fatal-warnings "$DART_SAMPLE" >/tmp/wg-verify-dart-strict.log 2>&1
DART_STRICT_RC=$?
DART_WARN=$(grep -cE '^warning' /tmp/wg-verify-dart-loose.log)

[ "$DART_LOOSE_RC" = "0" ] || { echo "FAIL dart loose rc=$DART_LOOSE_RC (expect 0)"; FAIL=1; }
[ "$DART_STRICT_RC" = "2" ] || { echo "FAIL dart strict rc=$DART_STRICT_RC (expect 2)"; FAIL=1; }
[ "$DART_WARN" = "1" ] || { echo "FAIL dart warning count=$DART_WARN (expect 1)"; FAIL=1; }
echo "dart: loose rc=$DART_LOOSE_RC strict rc=$DART_STRICT_RC warnings=$DART_WARN"

# ---------- Rust 受控样本（注入到生成树副本）----------
RUST_TREE=$(mktemp -d)
cp -r reference/rust/gen/. "$RUST_TREE/"
cat >> "$RUST_TREE/runtime/u_string.rs" <<'EOF'

// CONTROLLED WARNING INJECTION (audit t-mum29cli-9c9w): unused variable
pub fn controlled_unused_var_probe() -> u32 {
    let unused_controlled = 42u32;
    0
}
EOF
RUST_HASH=$(sha256sum "$RUST_TREE/runtime/u_string.rs" | cut -d' ' -f1)
[ "$RUST_HASH" = "a5835cbc20dc2acb482feba2493ae6f09a0e2a7a7e8396369b096669752acadf" ] \
  || { echo "FAIL rust injected hash mismatch: $RUST_HASH"; FAIL=1; }

"$CARGO" check --manifest-path "$RUST_TREE/Cargo.toml" >/tmp/wg-verify-rust-loose.log 2>&1
RUST_LOOSE_RC=$?
RUSTFLAGS="-D warnings" "$CARGO" check --manifest-path "$RUST_TREE/Cargo.toml" >/tmp/wg-verify-rust-strict.log 2>&1
RUST_STRICT_RC=$?
# 指名生成树内文件的 --> 引用行计数（不含汇总/插入符/上下文行）
RUST_WARN=$(grep -E '^\s+--> ' /tmp/wg-verify-rust-loose.log | grep -cE 'runtime/|boring/|haxe/|registry/|std/')
RUST_INJECTED=$(grep -c 'unused_controlled' /tmp/wg-verify-rust-loose.log)

[ "$RUST_LOOSE_RC" = "0" ] || { echo "FAIL rust loose rc=$RUST_LOOSE_RC (expect 0)"; FAIL=1; }
[ "$RUST_STRICT_RC" = "101" ] || { echo "FAIL rust strict rc=$RUST_STRICT_RC (expect 101)"; FAIL=1; }
[ "$RUST_WARN" = "5" ] || { echo "FAIL rust warning count=$RUST_WARN (expect 5)"; FAIL=1; }
[ "$RUST_INJECTED" -ge 1 ] || { echo "FAIL injected warning not found"; FAIL=1; }
echo "rust: loose rc=$RUST_LOOSE_RC strict rc=$RUST_STRICT_RC warnings=$RUST_WARN injected=$RUST_INJECTED"

rm -rf "$DART_SAMPLE" "$RUST_TREE"

if [ "$FAIL" = "0" ]; then
  echo "ALL ASSERTIONS PASS"
else
  echo "ASSERTION FAILURES PRESENT"
fi
exit "$FAIL"