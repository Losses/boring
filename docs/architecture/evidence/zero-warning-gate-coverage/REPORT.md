# 审计：五目标零警告门禁的真实覆盖（t-mum29cli-9c9w）

> 工作分支 `audit/zero-warning-gate-coverage`，base `e8648488`。
> 判定对象：`docs/specs/style/02-translator-implementation-standard.md:78/:80` 的零警告验收，
> 是否被验证链真实拒绝（而非"退出码 0 即通过"）。
> 优先审视 Dart analyzer 与 Rust rustc，与 `BUILD-PHASE-DIAGNOSTIC-RULING.md` 的
> "type-checker 空判据"陷阱同源。

## 结论（Executive Summary）

**当前验证链不会拒绝目标编译器的警告。** 五目标现有命令全部"退出码 0 即通过"，
即使生成树内存在大量既有警告（Dart 46、Kotlin 59、Rust 4），也全部 rc=0。
唯一的警告门禁（CI `collected-suite` 作业）只扫描 `bun run test` 的日志，
而该日志**从不运行** `cargo test` / `dart analyze` / `kotlinc` / `rustc` 于生成树，
其 grep 域 `reference/[a-z0-9-]+/gen` 在通过态下为空。因此：

- **Dart**：现有 `dart analyze --no-fatal-warnings`（package.json:21）显式关闭 fatal-warnings，
  46 条既有警告 rc=0。严格 `--fatal-warnings` 会把任何 warning 变成 rc=2。
- **Rust**：现有 `cargo test`（package.json:12）/`cargo check` 无 `-D warnings`，
  4 条既有警告 rc=0。严格 `RUSTFLAGS="-D warnings"` 会把任何 warning 变成 rc=101。
- **Kotlin**：现有 `kotlinc`（package.json:11）无 `-Werror`，59 条既有警告 rc=0。
- 受控对照（同一生成树，人为引入 1 条警告）：宽松 rc=0 / 严格 rc≠0，两步直读 rc 见 §3。

**零警告目前靠什么保证？** 靠人工/评审，不靠自动门禁。CI 的 `collected-suite` 门禁
（ci.yml:638-641）只对 `bun run test` 日志做 `grep -iE 'warn'` + `grep reference/.../gen`，
该日志不含五目标编译器对生成树的编译输出（见 §4 缺口分析）。

## ① 规范 + 五目标现有命令 + 严格度矩阵（含行号依据）

### 规范（docs/specs/style/02-translator-implementation-standard.md）

- `:78`（第 78 行）："Generated code compiles without warnings on every target:
  kotlinc, rustc, the TypeScript compiler, the Dart analyzer, and the Swift type-checker.
  A translation that produces a warning is an emitter defect with the same severity as a
  translation that produces wrong output."
- `:80`（第 80 行）："Acceptance for any emitter change counts the warning lines in the
  target suite output that name files under the generated trees; the count is zero."

### 五目标现有命令（package.json 行号）

| 目标 | 现有命令（package.json） | 行号 | 默认把 warning 当失败？ | 严格开关 |
|---|---|---|---|---|
| Rust | `cargo test` | :12 | 否（rc=0，4 条既有警告） | `RUSTFLAGS="-D warnings"` → rc=101 |
| Dart | `dart analyze --no-fatal-warnings reference/dart/gen` | :21 | **否，显式 `--no-fatal-warnings`**（rc=0，46 条既有警告） | `dart analyze --fatal-warnings` → rc=2 |
| Kotlin | `kotlinc $(find reference/kotlin/gen -name '*.kt') ... -include-runtime` | :11 | 否（rc=0，59 条既有警告） | `-Werror`（未实测，见 §5） |
| Swift | `swift build --product ...`（test:swift） | :19 | 否 | `-warnings-as-errors`（未实测） |
| TypeScript | `tsc -p .`（typecheck） | :29 | 否（tsconfig 无 `noEmitOnError` 关联警告开关） | `tsc --noEmitOnError`（未实测） |

> 注：`test:rust`（:12）与 `test:stage1:rust`（:18）都跑 `cargo test`，无 `-D warnings`。
> `test:dart`（:21）显式带 `--no-fatal-warnings`，是五目标中唯一**显式关闭**警告即失败的。

### 严格度矩阵（实测）

| 命令 | 受控 warning 存在时 rc | 依据 |
|---|---|---|
| `dart analyze --no-fatal-warnings`（现有） | **0** | dart-sample-loose.log |
| `dart analyze --fatal-warnings`（严格） | **2** | dart-sample-strict.log |
| `cargo check`（现有，无 -D warnings） | **0** | rust-inject-loose.log |
| `RUSTFLAGS="-D warnings" cargo check`（严格） | **101** | rust-inject-strict.log |

## ② 受控 warning 样本 + 同树宽松/严格对照

### Dart（同一棵树，人为引入 1 条 `unused_local_variable` lint）

受控样本 `lib/sample.dart`（输入哈希 `fcfb91ed50b518e8905f44f8ae6bfb74ab4d32a7f117168b49d573c4d85807ae`）：

```dart
int compute(int x) {
  final unused = x * 2; // unused_local_variable
  return x + 1;
}
```

- **宽松（现有命令）** `dart analyze --no-fatal-warnings /tmp/wg-dart-sample`
  → **rc=0**，输出 `1 issue found`，含 `warning - lib/sample.dart:3:9 ... unused_local_variable`。
  原始输出：`dart-sample-loose.log`。
- **严格** `dart analyze --fatal-warnings /tmp/wg-dart-sample`
  → **rc=2**，同一条 warning。原始输出：`dart-sample-strict.log`。

**对照可判别：宽松 rc=0 / 严格 rc=2，同一输入、同一条 warning。**

### Rust（同一棵树，人为引入 1 条 `unused variable`）

在生成树副本 `runtime/u_string.rs` 末尾注入受控函数（输入哈希 `a5835cbc20dc2acb482feba2493ae6f09a0e2a7a7e8396369b096669752acadf`）：

```rust
pub fn controlled_unused_var_probe() -> u32 {
    let unused_controlled = 42u32;
    0
}
```

- **宽松（现有命令）** `cargo check --manifest-path <injected>/Cargo.toml`
  → **rc=0**，5 条 warning（4 既有 + 1 注入 `unused_controlled`）。
  原始输出：`rust-inject-loose.log`。
- **严格** `RUSTFLAGS="-D warnings" cargo check --manifest-path <injected>/Cargo.toml`
  → **rc=101**，`error: unused variable: 'unused_controlled'`（5 条 warning 全提升为 error）。
  原始输出：`rust-inject-strict.log`。

**对照可判别：宽松 rc=0 / 严格 rc=101，同一棵树、同一条注入 warning。**

## ③ warning 计数（形状统计，不重复计数）+ 既有 vs 新增

### 计数形状（防 PIT-336 重复计数）

- **Rust**：`^warning` 行含汇总行（`generated N warnings`），且插入符/上下文行（`|`、`-->`）
  不以 `warning` 开头。按**指名生成树内文件的 `-->` 引用行**计数最精确：
  - 基线树（reference/rust/gen）：**4 条**（unused import DerefMut、byte_to_unit never used、
    2× hiding lifetime）→ `rust-baseline-check.log`。
  - 注入树：**5 条**（上述 4 + `unused variable: unused_controlled`）→ `rust-inject-loose.log`。
  - **新增候选警告 = 5 − 4 = 1**（`unused_controlled`）。
- **Dart**：`dart analyze` 每条 warning 独占一行 `warning - <file>:<line>:<col> - ...`，
  无插入符上下文行。按 `^warning` 计数：
  - 生成树 `reference/dart/gen`：**46 条**（既有基线）→ `dart-analyze.log`。
  - 受控样本：**1 条**（新增候选）→ `dart-sample-loose.log`。
- **Kotlin**：`<file>.kt:<line>:<col>: warning:` 形状，无插入符行。
  生成树 `reference/kotlin/gen`：**59 条**（既有基线）→ `kotlin-compile.log`。

### 编译成功 / 警告数量 / 既有基线 / 新增候选（区分）

| 目标 | 命令 | 编译成功(rc) | 警告数 | 既有基线 | 新增候选 |
|---|---|---|---|---|---|
| Rust | cargo check（现有） | 0 | 5（注入树）/4（基线） | 4 | 1（unused_controlled） |
| Dart | analyze --no-fatal-warnings（现有） | 0 | 46（生成树） | 46 | 0 |
| Kotlin | kotlinc（现有） | 0 | 59（生成树） | 59 | 0 |

## ④ 当前验证链会拒绝警告吗？

**不会。** 分三层说明：

1. **五目标现有命令**：全部"退出码 0 即通过"。Dart 显式 `--no-fatal-warnings`，
   Rust/Kotlin 无 `-D warnings`/`-Werror`。生成树内既有警告（Dart 46、Kotlin 59、Rust 4）
   全部 rc=0 通过（实测）。受控注入 1 条新警告，现有命令仍 rc=0。

2. **CI 唯一警告门禁**（`.github/workflows/ci.yml:638-641`，`collected-suite` 作业）：
   ```
   if [ "$WARN_COUNT" -ne "$EXPECTED_GENERATED_TREE_WARNINGS" ]; then
     echo "::error::... acceptance failure under ...:80 ..."; exit 1
   fi
   ```
   其中 `WARN_COUNT` 来自（ci.yml:350-351）：
   ```
   grep -iE 'warn' "$LOG" | grep -E 'reference/[a-z0-9-]+/gen(-tests)?/' > "$WARN_FILE"
   WARN_COUNT=$(wc -l < "$WARN_FILE")
   ```
   `$LOG` = `bun run test` 的输出（ci.yml:322）。**该命令从不运行** `cargo test` /
   `dart analyze` / `kotlinc` / `rustc` 于生成树（实测 grep 全部 `.test.ts` 无此类调用），
   且收集套件里 swiftc 测试生成到 `out/gen`（非 `reference/*/gen`，见 gap-boundary.test.ts:5、
   readonly-boundary.test.ts:5），不落入门禁 grep 域。因此通过态下 `WARN_COUNT` 恒为 0，
   门禁**空转**——它只证明"bun test 日志里没有指向 reference/*/gen 的 warn 行"，
   与五目标编译器警告无关。

3. **零警告目前靠什么保证？** 靠**人工/评审**，不靠自动门禁。唯一接近严格检查的是
   `tests/swift-readonly-boundary/readonly-boundary.test.ts:83`（`expect(compilerDiagnostics.trim()).toBe("")`，
   swiftc 零诊断），但它只覆盖 Swift 一个夹具，且生成到 `out/gen`，不落入 CI 门禁域。
   `tests/swift-gap-boundary/gap-boundary.test.ts:108-111` 反而**断言**一条既有警告
   （`will never be executed`）**存在**（记录为未豁免基线失败），不是零警告断言。

### 缺口范围

- **Dart**：46 条既有警告 + 任何新警告，现有命令全部放行（`--no-fatal-warnings`）。
  门禁完全看不见。缺口 = 整个 Dart 目标。
- **Rust**：4 条既有警告 + 任何新警告，`cargo test`/`cargo check` 全部放行。
  门禁完全看不见。缺口 = 整个 Rust 目标。
- **Kotlin**：59 条既有警告 + 任何新警告，`kotlinc` 放行。门禁完全看不见。缺口 = 整个 Kotlin 目标。
- **Swift**：`test:swift`（`swift build`）无 `-warnings-as-errors`；仅 readonly-boundary 夹具
  断言零诊断（`out/gen` 域，不入 CI 门禁）。缺口 = 大部分 Swift 生成树。
- **TypeScript**：`tsc -p .` 无警告即失败开关；`test:stage1:ts` 只跑生成测试不 typecheck 生成树。
  缺口 = 整个 TS 目标（tsconfig 无 `noEmitOnError` 关联）。

**结论**：`:78/:80` 的"零警告"在自动验证链上是**空判据**——与 `BUILD-PHASE-DIAGNOSTIC-RULING.md`
判定的 Swift `-typecheck` 空判据同构。现有命令的退出码不携带警告信息，CI 门禁的 grep 域
不含五目标编译器输出。要真实拒绝警告，需在五目标现有命令上加严格开关（Dart `--fatal-warnings`、
Rust `-D warnings`、Kotlin `-Werror`、Swift `-warnings-as-errors`）并把输出接入门禁 grep 域，
或让门禁直接扫描五目标编译日志。

## 承重件入库说明

- 本报告 `REPORT.md` 入库。
- 原始输出日志 8 份入库（`dart-sample-loose/strict.log`、`rust-inject-loose/strict.log`、
  `rust-baseline-check.log`、`rust-cargo-check.log`、`dart-analyze.log`、`kotlin-compile.log`），
  均为受控实验的直读 rc 与原始输出，可复现。
- 断言脚本 `verify.sh` 入库（见同目录），重跑宽松/严格对照并核对 rc 与 warning 计数。
- 受控注入的生成树副本在 `/tmp`（`/tmp/wg-dart-sample`、`/tmp/wg-rust-tree`），
  不入库（生成树是 gitignored 构建产物，规范 `:93` 禁止入库）；输入哈希已在本报告记录，
  脚本从哈希核对注入内容。

## 工具链（实测路径）

- haxe = `/nix/store/98pb92k7pi6g5cifmg872jn18kghaxw5-haxe-4.3.7/bin/haxe`
- cargo/rustc = `/nix/store/agfrkw7lvckq29w4dp0i3jfrhxjmgv3q-rust-default-1.98.0/bin/`
- dart = `/nix/store/vsv6nwqv7g9vdkyj2paxa9g8vki0svvy-dart-3.13.3/bin/dart`
- kotlinc = `/nix/store/rqx09a40a82di944xi6ydjyzx632av28-kotlin-2.4.10/bin/kotlinc`
- swiftc = `/nix/store/6xl7bxha1n1asrxzxb8dnsh9hvnpa00j-swiftc/bin/swiftc`
- 均不在 PATH，需绝对路径调用；生成需 cwd=仓库根 + `HAXELIB_PATH=$PWD/.haxelib`。