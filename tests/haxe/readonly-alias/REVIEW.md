# REVIEW — 独立审阅：普通只读视图共享别名证据（五目标）

审阅对象：run `out/readonly-alias/runs/ro-cuvbPSXy`（判定 `failed`，
`differences 0 / not-reached 2 / target-failures 1`）。本审阅区分四类事实：
Rust 克隆位置（局部初始化 / 返回位置）、Swift 当前共享视图、目标工具链限制、
decode 边界（独立契约，非本夹具范围）。所有引用行均可在 run 目录内复算。

## 1. 结论摘要

| 目标 | gen | compile | run | compare | 观察 |
|------|-----|---------|-----|---------|------|
| Haxe oracle | 0 | 0 | 0 | identical | 参照系：702/3301/56/123/564:1494 |
| TypeScript | 0 | 0 | 0 | identical | 共享引用，与参照一致 |
| Kotlin | 0 | 0 | 0 | identical | 共享可变列表，与参照一致 |
| Swift | 0 | 0 | 0 | identical | 共享 backing 视图，与参照一致 |
| Dart | 0 | 0 | 0 | identical | 共享列表，与参照一致 |
| Rust | 0 | 101 | not-reached | not-reached | 生成代码两处 emitter 缺陷（§3.6）；克隆位置模型见生成源码 |

除 Rust 外四目标的运行输出与 authored `expected.txt` 逐行一致
（`stages/run-<t>/stdout` 与 `stages/compare-<t>/` 的 diff 为空）。
`differences 0`：没有任何目标产生"可编译但语义不同"的观察；
Rust 的缺失是编译期缺口，按 `not-reached` 记录而非语义差异。

## 2. 输入与身份

- worktree `boring-wt-audit-ro-alias`，branch `audit/readonly-alias-evidence`，
  HEAD 见 `identity/base`（c9e2cff9 系）；工具链版本见 `identity/` 各阶段。
- `input-hashes-before/after.txt` 一致（manifest 未漂移）。
- 各生成树摘要：`<t>-tree.sha256`；harness 副本哈希：`stages/compile-<t>/gen/harness.sha256`。

## 3. 逐目标机制审阅

### 3.1 Haxe oracle（参照）
`stages/haxe-oracle-run/stdout` 恰为五行 expected 值；
`stages/haxe-oracle-expect` 与 `expected.txt` diff 为空。
值域由 feature-18 共享读语义推出：alias 经视图回读 7 并见 push（702）；
passed 返回参数视图、回写 33 后读 33（3301）；escaped 为副本（56）；
rebind 绑定不跟随（123）；boundary 调用后 holder 回写 99 经共享视图可见（564:1494）。

### 3.2 TypeScript — 共享引用
生成 `ts/gen/roalias/ReadOnlyAliasOracle.ts`（run 树）：
- alias：`const view = mutable;`（同一数组引用，无拷贝）
- passThrough：`passThrough(values: readonly number[]): readonly number[] { return values; }`
  （返回参数本身）
- rebind：`let values = [1, 2, 3]; const view = values; values = [9, 8, 7];`
  （重新赋值不移动旧数组；view 指向旧引用）
观察 702/3301/56/123/564:1494，与参照一致。`readonly` 仅是类型面，
运行时容器共享 —— 与 spec 普通转换语义一致。

### 3.3 Kotlin — 共享可变列表
生成 `kotlin/gen/roalias/ReadOnlyAliasOracle.kt`：
- alias：`var mutable = mutableListOf<Int>(1); val view = mutable`
- rebind：`values = mutableListOf<Int>(9, 8, 7)`（view 保留原列表）
观察与参照一致。

### 3.4 Dart — 共享列表
生成 `dart/gen/lib/roalias/read_only_alias_oracle.dart`：
- alias：`final mutable = [1]; final view = mutable;`
- passed：`passThrough(source)` 返回参数视图后 `source[0] = 33`
观察与参照一致。

### 3.5 Swift — 当前共享视图
生成 `swift/gen/roalias/ReadOnlyAliasOracle.swift`：
- alias：`let view: ReadOnlyArray<Int32> = ReadOnlyArray(mutable)`
- passThrough：`func passThrough(_ values: ReadOnlyArray<Int32>) -> ReadOnlyArray<Int32> { return values }`
- rebind：`let view = ReadOnlyArray(values); values = TiqianArray<Int32>([9, 8, 7])`
生成 `swift/gen/Runtime.swift` 中的视图类（对应源
`packages/compiler/reflaxe/swift/swiftcompiler/SwiftRuntime.hx:486` 的发射）：
- `public final class ReadOnlyArray<Element>: RandomAccessCollection`
- `private let backing: TiqianArray<Element>`
- `public init(_ backing: TiqianArray<Element>) { self.backing = backing }`

`TiqianArray` 与 `ReadOnlyArray` 均为 class（引用类型）：视图持有对同一
backing 的引用，写入经原数组可见 —— 当前 Swift emitter 产生共享视图，
运行输出与参照完全一致。这与 D 探针时代（pre-J Swift，alias=101 的快照式
旧发射）不同：本 revision 的 Swift 是共享存储。D 探针中的
guarded-optional / optional-cell 红项是既有 nullable-fallback 问题，
属非目标，不计入本夹具。

### 3.6 Rust — 克隆位置模型与两处 emitter 缺陷
生成 `rust/gen/roalias/read_only_alias_oracle.rs`（run 树）逐位置记录：

- **局部初始化位置 = 克隆**。
  alias：`let mut mutable = vec![1]; let view = (mutable).clone();`
  rebind：`let view = (values).clone(); values = vec![9, 8, 7];`
  与 S 探针的 Rust 观察一致（alias=101 的来源）：克隆后 view 与 mutable
  分离，回写不可见；rebind 的克隆保留原值（123）。
- **返回位置 = 克隆意图，表达式非法（emitter 缺陷 E1）**。
  `pub fn read_only_alias_oracle_pass_through(values: &[u32]) -> Vec<u32> { return (*values).clone(); }`
  rustc E0599：slice 无 `clone` 方法。发射器在返回位置选择了克隆模型
  （若可编译，观察应为 1201 = 副本语义），但对借用 slice 源生成的表达式
  不是合法 Rust。
- **持有者回写位置 = 绑定可变性缺口（emitter 缺陷 E2）**。
  `let result = ...boundary_producer();` 之后 `result.holder.values[1usize] = 99u32;`
  → E0596（`result` 非 `mut`）。生成器未为"稍后经绑定可变"的绑定生成
  `let mut`。
- **boundary 的分离模型（若 E1/E2 修复后的预期观察）**。
  producer：`BoundaryResult::new((view).clone(), (original).clone())` ——
  view 与 holder 均为克隆；调用方回写只影响本地副本 → 564:564（分离），
  与 PIT-195 的价值传递 + Clone 模型一致。
- **escaped = 所有权移动**：`pub fn read_only_alias_oracle_make_view() -> Vec<u32> { let values = vec![5, 6]; return values; }`
  （无需克隆，直接移交所有权；若可编译观察为 56）。

本 run 的 `cargo build` 因 E1/E2 失败（`stages/compile-rust/stderr`，
exit 101），run/compare 记 `not-reached`。**审阅立场**：这不是"所有只读
转换皆失败"的解释 —— 两处是定位明确、可独立修复的生成代码缺陷
（返回位置对 slice 源的 clone 表达式；`let` 与后续可变使用的绑定标记），
其余位置（局部初始化克隆、所有权移动）的发射与 Rust 的语义模型自洽，
且与 S 探针的历史观察互相印证。

## 4. 工具链限制

- **Swift 包装器 / bwrap**：devShell 的 `swiftc` 包装脚本以 bubblewrap 搭建
  FHS 环境；本容器 uid 1000 无 CAP_SYS_ADMIN，`bwrap: setting up uid map:
  Permission denied`。runner 探测包装失败后解析原始 store 工具链
  （swiftc 6.2.4 + FHS rootfs 库 + CRT 对象软链工作目录），全部解析结果与
  包装 stderr 记录于 `swift-toolchain.txt`。Swift 的 compile/run 因此
  真实执行（非跳过）。
- **Dart**：本 run 无遗留限制。前一轮 compile 254 的根因是夹具 harness
  导入名与 emitter 下划线命名不符（`readonly_alias_oracle.dart` →
  `read_only_alias_oracle.dart`），已修正；`dart pub get` 正常。
- **Rust**：见 §3.6（生成代码缺陷，非工具链缺失）。

## 5. Decode 边界（独立契约）

feature-18 的 decode 边界保护（decode 路径上的只读保护）是另一条 spec
契约，不在本夹具范围。本夹具的 `boundary` 形状测的是"producer 返回
视图 + 持有者"之后的生命周期（调用后经 holder 回写是否经共享视图可见，
X 探针 case 4 的 564:1494 参照），与 decode 边界不同题；Rust 对
boundary 的分离观察（§3.6）属于克隆模型推论，不是 decode 保护行为。

## 6. 非目标（未触碰 / 未解释）

- A3 集成树生产发射器、decode 保护、R1–R6 可写位置夹具：未修改。
- D 探针的 Swift nullable-fallback 红项：既有问题，不计入本夹具。
- X 探针（view-lifetime）的未执行状态：本夹具的五形状收束了 S/D/X 的
  探针面（README 有对应表），X 的历史预期值作为参照记录，不重复执行。
