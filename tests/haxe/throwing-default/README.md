# throwing-default：默认参数中可抛调用的函数失败域观察

任务 `t-mum0wts5-jh3m`（分支 `audit/default-arg-throwing-domain`，base `e8648488`）。
本目录是隔离观察夹具：coalescing default 的默认表达式 E 是一个可抛静态调用，
用省略实参触发，比较 Rust 与 Swift 的函数失败域、调用标记与 try region 吸收。
测量任务，不是目标修复：所有读数都在 `out/throwing-default/<attempt>/`（gitignored）。

## 1. 准入判定（先于一切观察）

B/D 交叉审核（board timeline seq 2/3）担心 spec 22 V16 把默认表达式限制为
纯常量/闭合 coalescing 类，可抛调用可能不在已接受源域内。实测结论：**分两半**。

| 源形状 | 判定 | 原始输出（att-20261001T000709Z） |
|---|---|---|
| 默认位直接放调用 `p:Int = g(2)` | **拒绝**，rc=1 | `PDefaultPosition.hx:15: characters 30-34 : default argument values accept compile-time constants only` |
| coalescing default 内可抛调用（`?value` + `value == null ? throwingFallback(seed) : value`） | **接受**，rc=0，空输出 | `stages/admit-coalescing-throwing/status` = 0 |

条文依据（文档引用，非实测）：

- `docs/specs/features/22-default-argument-expansion.md` L68-74（规则 1）：默认位
  只收常量，"Any other expression in default position is rejected with the named
  error `default argument values accept compile-time constants only`"。
- 同文件 L173-188（Extension Stage A 语法）：coalescing E 的闭合语法**包含**
  static call / instance method call 根，且语法判定不含 fallibility 条件；
  `packages/compiler/DefaultArgExpander.hx` L695-750（`validateCoalescingGrammar`
  规则 6）实测为纯语法匹配，不检查被调函数是否可抛。
- `docs/specs/style/01-haxe-style-standard.md` L65（V16 NonConstantDefault 行）。

所以审核者的担心只对**默认位**成立；本任务问的 coalescing 形状在源域内，
任务前提成立，行不缩减。接受性本身不证明 site 被注册为 coalescing default
（普通三元式也合法）；注册由生成物证明（§3 的 `unwrap_or_else` / `= nil` +
body normalization 都是注册机器的产物）。

## 2. 夹具结构

`throwdef/ThrowingDefaultOps.hx`：

- `throwingFallback(seed)`：可抛被调（seed>10 抛 `ThrowingDefaultException(OverThreshold(seed))`）。
- `resolve(seed, ?value)`：coalescing default，E = `throwingFallback(seed)`（读较早参数）。
- raw 调用层（失败域观察对象，harness 不调用）：`callOmittedSafe`=`resolve(5)`、
  `callOmittedThrowing`=`resolve(20)`、`callExplicit`=`resolve(5, 9)`。
- probe 层（统一 `String` 返回的 region 吸收面，harness 入口）：三个
  `final outcome = try { "ok:"+… } catch (error:ThrowingDefaultException) { "caught:"+… }`。

两个调用形状：**省略实参**（默认求值，可抛调用真实执行）与**显式实参**
（默认不求值，可抛调用不执行）。显式 null 材质化（feature 51）不在本行，
未测。

Haxe oracle（plain Haxe 4.3.7，无 Intercept，spec 22 "Oracle standing"）：

```
omittedSafe=ok:10
omittedThrowing=caught:OverThreshold:20
explicit=ok:9
```

## 3. 观察矩阵（两形状 × 两目标，全部实测）

生成物引用行号以证据副本 `out/throwing-default/att-20261001T000709Z/` 内
`rust-throwing-default-ops.rs` / `swift-ThrowingDefaultOps.swift` 为准（与
`rust/gen/throwdef/`、`swift/gen/throwdef/` 生成树逐字节相同，树哈希在
`rust-tree.sha256` / `swift-tree.sha256`）。

| 维度 | Rust | Swift |
|---|---|---|
| 生成 rc | 0 | 0 |
| `throwingFallback` 失败域 | `Result<u32, ThrowingDefaultFault>`（L25） | `throws`（L25） |
| `resolve` 失败域 | `Result<u32, ThrowingDefaultFault>`（L32）；**但默认路径的失败是 panic**：L33 `value.unwrap_or_else(\|\| …throwing_fallback(seed).unwrap())`，闭包内 `.unwrap()` | `throws`（L32）；默认路径的失败是**正常 error**：L33 `(value == nil ? try throwingFallback(seed) : value!)`，`try` 在三元式内 |
| 省略形（不抛） | `resolve(5, None)?`（L39），默认求值 → 10 | `try resolve(5)`（L39），默认求值 → 10 |
| 省略形（抛） | **panic**：`throwing_default_ops.rs:33:110` 的 `.unwrap()`，进程 rc=101，stdout 截断为 1/3 行 | 抛出 → probe 的 `do/catch` 吸收 → `caught:OverThreshold:20` |
| 显式形 | `resolve(5, Some(9))?`（L47），默认不求值 → 9 | `try resolve(5, 9)`（L47），默认不求值 → 9 |
| 调用标记 | 调用点 `?`（L39/43/47）：对默认路径**失效**（panic 不走 `?`） | 调用点 `try` + 默认表达式内 `try`（L33）：两级都在 |
| region 吸收 | region 降为 `match (\|\| -> Result<…>)()`（L59-64）：**Result 匹配吸收不了 panic**，probe_omitted_throwing 崩溃 | region 降为 `do/catch let error as ThrowingDefaultException` + bare catch rethrow（L74-84）：**吸收成功**，三行全中 oracle |
| 原生编译 rc | 0（4 条 warning 全部来自 runtime/u_string.rs 既有代码，夹具文件 0 条） | 0（1 条生成物 warning，见 §5） |
| 原生运行 rc | **101**（panic） | **0** |
| 与 oracle 比较 | **分歧**（diff 非空：第 2/3 行缺失） | **一致**（3/3 行） |

## 4. 失败域结论与机制

**Rust 把 coalescing default 内可抛调用的失败逐出了函数的声明失败域。**
`resolve` 的 `Result` 签名来自 fallibility 扫描（typed body 里 coalescing site
的 TCall 感染，`packages/compiler/reflaxe/rust/rustcompiler/Compiler.hx`
L1244-1340；调用点省略实参时默认内调用另记为传播边，L1279-1340），但渲染端
`RustExpr.defaultErrorSuffix`（`packages/compiler/reflaxe/rust/rustcompiler/RustExpr.hx`
L2675-2689）对 `inClosure` 情形返回 `".unwrap()"`：闭包必须返回具体值，
`?` 无法传播，实现选择了 unwrap（panic）。结果：声明的 Err 路径对默认失败
不可达，`?` 标记失效，try region（Result 匹配）吸收不了 panic。与 Haxe
stage-1 语义（异常传播、region 捕获）在抛出省略形上**跨目标分歧**。

**Swift 把它留在函数的 throws 域内。** `SwiftParameterPlan.coalescingDefaultThrows`
（`packages/compiler/reflaxe/swift/swiftcompiler/SwiftParameterPlan.hx` L98-109）
识别可抛默认，参数降为 `T? = nil` + 入口 body normalization；`SwiftDecl` L986-989
/ `SwiftExpr.throwingCoalescingText`（L356-358）在三元式真臂放 `try`（`??`
右操作数是非抛 autoclosure，所以用显式条件式）。fallibility 扫描
（`SwiftFallibility.scanExpr`，L153-172）让 region 恰好吸收其 catch 命名的类。
B/D 担心的"Swift 漏 try"**实测不成立**：默认表达式内与调用点两级 `try` 都在。

try region 吸收对失败域的影响（实测 + 机制引用）：Swift 的 region 吸收使
probe 层函数对已捕获域不抛（仅 bare catch rethrow 未知域，故签名仍 `throws`）；
Rust 的 region 是 Result 匹配，只吸收 Err，而默认失败走 panic 通道，位于
该机制之外，吸收失败即进程崩溃。两目标的 region 吸收语义在"默认可抛"这一
源形状上不等价。

## 5. 诊断（与失败域分开记录）

Swift 原生编译有 1 条**生成物** warning（att 目录
`swift-redundant-try-warning-count.txt`）：

```
throwdef/ThrowingDefaultOps.swift:34:33: warning: no calls to throwing functions occur within 'try' expression
```

即 `let normalized: Int32 = try value` 的冗余 `try`（`SwiftExpr` L352-354 注释
自述："a `try` marker the statement pipeline adds over the same call is legal
and stays"）。按 `docs/architecture/rulings/BUILD-PHASE-DIAGNOSTIC-RULING.md`
的裁定口径，这是 build 期诊断，**另一件事**，不计入失败域结论；此处仅作为
读数记录。Rust 侧 4 条 warning 均来自 `runtime/u_string.rs` 既有代码，与本
夹具无关。

## 6. 复现

```
nix develop -c bash tests/haxe/throwing-default/run.sh
```

一次调用分配 `out/throwing-default/att-<utc>/`（只增不覆写），15 个阶段
（准入×2、oracle×3、rust×5、swift×5）各自记录 argv/cwd/分流 stdout+stderr/
status；`identity/` 记工具版本与全部夹具输入 sha256；生成树有逐文件哈希
清单。authored 期望钉在 base `e8648488`：Swift 复现 oracle 三行；Rust 在抛出
省略形 panic（rc=101）并截断输出。任何偏离（例如 Rust 不再 panic、或 Swift
不再匹配）记为 observed-differences 保留证据；准入翻转或 oracle 锚断裂才
exit 非零。

## 7. 实测 vs 文档引用

- 实测：§1 两探针 rc 与输出；§3 全部单元格（生成、编译、运行、比较、诊断）；
  §5 warning 原文。
- 文档/代码引用（未运行该代码本身，只读了文本）：§1 的条文行号、§4 的
  发射器机制行号、§5 的裁定文件。
- 未测：显式 null 材质化路径（feature 51）；`recordDefaultCallEdges` 的
  null-provided 分支（Compiler.hx L1326-1339）：本夹具无显式 null 调用点。
