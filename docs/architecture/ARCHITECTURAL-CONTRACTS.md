# 架构契约

分类（`PROBLEM-CLASSIFICATION.md`）说清"哪一类失败归谁"；本文件说清
**接口两端各自承诺什么**，即：一个位置在什么条件下必须交出什么。

## 契约 1：目的地由组合传入（D 类）

**规则**：转换站点必须拿到**目的地**（目标类型），不得从编译器实例状态推断。

**现状事实**（已核实，候选树 `SwiftExpr.hx` 7041 行）：
- `currentReturnType` 是 `SwiftExpr` 的**实例字段**（`:218`），唯一写入在 `:544`
  （`functionBody`，来自成员的 `TFun` 返回），`:563` 清除。
- `functionLiteral`（`:2338-2345`）只保存/恢复 `currentFuncReturnsOptional`，
  **不重绑** `currentReturnType`。
- 正确的值在 lambda 内是 **`f.t`**（`:2349` 已用它打印闭包头）。

**契约形式**：
```
转换站点(value, destination, fallback) -> 文本
其中 destination 由该位置所属的组合提供：
  - 成员体      -> 成员的返回类型
  - lambda 体   -> lambda 的返回类型 (f.t)
  - 内联块/匿名 helper -> 该块自己的结果类型（不是外层 lambda 的）
  - 绑定路由    -> 被绑定变量的类型 (v.t)
  - 参数路由    -> 被调方声明的参数类型
```
**最后一条是本会话的教训**：`blockExpression` 的块有自己的目的地；
把它当成 lambda 的返回契约会**注入错误转换**（`lambda-fix-xcheck` 的 P4 回归，
`mx/MXProbe.swift:19:12`，`cannot convert 'ReadOnlyArray<Int32>' to closure
result type 'TiqianArray<Int32>'`）。

## 契约 2：nil-merge 的中间目的地由组合提供（C 类边界 × D 类目的地）

**规范原文**（`docs/compiler-policy-interfaces.md:171-173`，逐字）：
> "A nil-merge with a required final result passes an **optional intermediate
> destination** to the optional left operand's conversion."

**落地**：`prepare(operand, destinationType, override)` 的第三输入
`destinationOptionalOverride`（`SwiftArrayBoundary.hx:173`）。
- `override == null` ⇒ 规划器按目的地自身的可选性裁决（三条 REFUSED 行的默认语境）
- `override == true` ⇒ 组合声明"此处接受可选中间结果" ⇒ 该格子转为转换
  （`MapOptionalMutableArrayView` `:200-202` 等）

**契约边界**：`override` 是**组合的义务**，不是操作数的属性，也不是豁免。
`RECORD.md` 的三条 REFUSED 行因此在记录里被限定为 **PLANNER-CELL ONLY**
（CORRECTION 13）。

## 契约 3：warning 计入验收（F 类）

**约束性标准**：`docs/specs/style/02-translator-implementation-standard.md`
- `:78` *"Generated code compiles **without warnings** on every target … A
  translation that produces a warning is an emitter defect **with the same
  severity as a translation that produces wrong output**."*
- `:80` *"…counts the warning lines in the target suite output that name files
  under the generated trees; **the count is zero**."*

**推论（本会话已作出并落笔，TCN-156）**：
- warning **计入**；**基线失败要记录，但不豁免**（`work-plan:417`）。
- ⇒ **必须有套件在跑**：没有套件收集 ⇒ 不产生计数 ⇒ 标准无法被满足，
  只是被绕过。**该缺口已接线**（`9f26e1ef`）：`ci.yml` 增加 `collected-suite`
  job，每次运行入口 `bun run test` 并报告收集域（303 文件，其中 249 个来自
  生成树 `reference/ts/gen-tests`）。该 job 阻塞、无 `continue-on-error`；
  基线 `1001 pass / 32 fail / 8 errors` 记于 `BASELINE-FAILURES.md`，尚未清偿。
- ⇒ 记录的形态必须是"**已知基线失败 + 显式 PIN**"，**不得**命名为"零诊断满足"：
  `tests/swift-gap-boundary/gap-boundary.test.ts:44` 的属主裁定即为本契约的落地。

**补充（`t-muo92xms-s28t` 裁定，`1a486ebd`；见 `rulings/BUILD-PHASE-DIAGNOSTIC-RULING.md`）：
"用哪个工具"与"能看见哪类诊断"必须分开说明。**
`:78` 的主句是全称的（"on every target"），但枚举工具时只写 *"the Swift type-checker"*。
该窄化留下一个洞：**`swiftc -typecheck` 不跑 SILGen，在基线态也报 0 条**，
故它对 `Gap.swift:117` 的 `will never be executed` **既不能证实也不能证伪**；
真正能看见它的只有 `-c`（含 `-whole-module-optimization`）与 `-o`。
⇒ **裁定：构建期诊断计入 `:78/:80`**。若按字面只认"类型检查器"，"零警告"退化为
**空判据**（真实发射器缺陷全部隐性通过，而下游编译二进制的 CI 仍会撞上它）。
**计数纪律**：按 `file:line:col: severity` **形状**计，不要用 `grep -c 'warning:'`
—— Swift 还会打印插入符/上下文行，会把 1 条数成 2 条（PIT-336）。
**同类推广**：对每个目标都要问一遍"现有命令是否**看不见**它能报的诊断"——
本会话同族的一例是 `cargo check` 与 `cargo build` 的警告面不同。

## 契约 4：生成输出的验收判据必须能观察到被测性质

**规则**：一个验收检查必须**在该性质被破坏时会失败**。

**本会话的三处反例**（同一缺口，三种成因）：
| 项 | 为何观察不到 |
|---|---|
| `branchBoundary` 夹具 | 两分支等长，消费者只打印长度 |
| 缺失返回形态 | **`swiftc -typecheck` 不跑 SILGen，不报告 "missing return"** |
| 拼接类修复 | 生成树 pre/post 逐字节相同（无法区分"没改"与"改对"） |

**⇒ 落地的判据**（`LAYERED-VERIFICATION.md` 会展开）：
1. 断言必须比"没坏"更严：例如 `1:1:present` 而非 `1:present`
2. **剥离 `return` 的形态必须用 `swiftc -c`，不能用 `-typecheck`**
3. 拼接类修改必须用**判别性后端**（故意取错分支/故意返回错值）证明会 FAIL

## 契约 5：修复不得改变别类行为

**落地方式**：修复后对**全量驱动**重生成并做整树对比，**路径归一化后逐字节相同**
是必要条件。四处已提交修复都满足（W1：19 驱动、仅 2 行差异且为预期；
lambda：19 驱动、diff 为空）。

**限界**：整树相同**不能**证明修复正确，只能证明**没有波及别处**；
"生成成功"、"类型检查通过"、"运行正确"是三个不同强度，必须分开陈述。

## 契约 6：一个判断只能有一个来源；能从事实派生的，不得另行判定

**规则**：当某件事"是否成立"会影响输出时，该判断必须**只有一个权威来源**。
若它可以**从已经发生的事实派生**（文件是否真的写出、声明是否真的发射），
就**必须派生**，不得让第二处代码**独立地**再判一次。

**为什么**：判据与事实**并行判定**时，两者可以不一致，而**不一致在通过态下不可见**。
这与契约 4 是同一族但不同层：契约 4 说"检查要能观察到被破坏的性质"，
本条说"**判据本身不能与它所描述的事实脱钩**"。

**实测（Rust 目标 `state.shimsUsed`）**：
| 量 | 值 |
|---|---|
| 写点（各自认为"某 shim 被用到了"） | **28 处**，散在 `RustDecl.hx` / `RustExpr.hx` / `RustImports.hx` |
| 读点（据此决定某 resident 是否发射） | **15 处** |
| 规定"哪条路径必须写"的契约 | **无** |

（写点分布：`RustExpr.hx` 23、`RustImports.hx` 3、`RustDecl.hx` 2；
读点分布：`Compiler.hx` 13、`RustImports.hx` 1、`RustEmissionState.hx` 1。
量于 `aceda352`，判据为"行形状"：左侧赋值、下标赋值，或 `push|add|set|insert|remove|clear`。）

⇒ 这个全局被**当两种意思用**："业务引用到了某 extern"（意图层）与
"某 resident 该不该写出 `.rs`"（发射层）。**两层不等价，且无人负责保证等价。**
产物是 `runtime/mod.rs` 声明了一个从未写出的模块（`E0583`）：
**声明走一条判据、文件发射走另一条，两条的写入面不重合。**

**两条修法路线，判据不同**：
- **补写点**：每发现一条未覆盖的路径就在该路径上再写一次判据
  （master 在 `RustImports.requireType` 尾部加的一处即属此类）。
  正确性押在"**写点覆盖完整**"上；而写点数量**无法穷举验证**，新增路径即退化。
- **从事实派生**：让发射函数**返回它是否真的写了文件**，由调用方记录，
  声明列表**从该记录生成**（本分支 `94eace13`：`emitResidentModule` 返回 `Bool`
  ⇒ `emittedResidentMods` ⇒ `runtimeMods`）。正确性押在"**声明来自事实**"上，
  **可验证且不随新增路径退化**。

**⇒ 落地判据**：
1. 出现"两处代码做同一判断"时，先分清是**同层重复**还是**写侧/读侧**；
   两侧都要的，**必须指定哪一侧是正确性来源**。
2. 问"**有没有契约规定谁必须写**"。若答案是"没有 + 写点远多于读点"，
   真实缺陷**不是缺一次合并**，而是判据缺少唯一来源。
3. 验证派生是否**自足**：若不点亮那些写点、仅靠派生仍能保持不变量，
   说明派生独立成立；**若只有某个写点开火才成立**，说明正确性仍依赖
   未协调的写点；**这本身是要报的发现**，即便代码在语法上是对的。

**消融实测（补记，`aceda352`）**：把 master 在 `RustImports.requireType`
尾部的写点整段禁用后重新生成 `examples/rust.hxml`。

| 观测 | 结果 |
|---|---|
| 生成 rc | 0 |
| 生成树差异（排除 cargo 的 `target/`） | **零**：545 个 `.rs` 两侧一致 |
| `runtime/mod.rs` | **逐字节相同** |
| 声明/引用 | 15 / 15，violations = **0** |
| `cargo check` | rc=0，error 计数 0 |

⇒ 该写点在本语料上**完全惰性**，因此"零违规"**既不证明派生自足、
也不证明写点必要**。原因是两条路径对同一组 extern 求值：`Compiler.hx:862`
的发射闸门本身就读 `state.shimsUsed.exists(externModule)`（经 `externsOf`），
与写点用的是同一对 `(isResident, externsOf)`，按构造必然一致。

要真正判定自足，需要一个"只被 `requireType` 触及、而其导入方不触发
extern 点亮"的用例；在那之前此项记为**未决**，不得写成"已验证自足"。

**上文结论已被推翻（更正，独立复现）**：上面那张"整树零差异"的表是**真的，
但它对判断该写点是否必要几乎无信息量**——闸门是对**同一个共享 `shimsUsed`
映射求全局并集**，全量语料里任何一处显式点亮都会让所有 resident 照常发射，
于是写点的缺席被语料本身掩盖。**不能拿全量语料的字节一致当作"惰性"的证据。**

最小反例（写点禁用，只留单一根 `boring.DataClassStringCompare`，
即 `19ae7db6` 与该写点一起加入的那个样本）：

| 观测 | 写点在 | 写点禁用 |
|---|---|---|
| 生成 rc | 0 | 0 |
| `runtime/mod.rs` | 9 条 `pub mod`，含 `sorted_table` | **5 条，`sorted_table` 消失** |
| `boring/data_class_string_compare.rs` | 正常 | 仍 `use crate::runtime::sorted_table::SortedTable;`（:1）、:26 仍调用 |
| `cargo check` | **rc=0** | **rc=101，`error[E0432]: unresolved import`** |

⇒ 该写点是**承重的（load-bearing），不是冗余**，**不得删除**。契约 6 因此有
一条强得多的落地判据：**判断"某写点是否必要"必须在最小根集上做消融，
不能在全量语料上做**——全量语料的通过态会掩盖单点缺陷，与 G 类
"不一致在通过态下不可见"是同一现象。路径：`RustDecl.hx:557` /
`RustType.hx:196-207` 的 `requireType("runtime.SortedTable", …)` 只点亮
`std.SortedMap` 一族，而全量语料里这些键另由 `RustImports.hx:61` 经
`RustType.hx:197/200/203/206` 点亮。

**本条规则的适用边界（补记，实测自 `9081d0d0` 的复核）**：契约 6 要求判据派生自
事实，但**"派生出来的字段"不等于"可以互相代证"**。同一份记录里，
`stdoutAvailable` 派生自宿主 outcome 的流对象是否存在（`ChildEvidence.hx:439`），
`stdoutBytes` 派生自最终写盘缓冲的长度（:505），两者**来源不同**：
健康树 1005 条记录中 236 条同时是 `available=true` 且 `bytes=0`。
因此**不得**用 available 标志位去校验"流确实被保留"，也不得把
available/bytes 一致性当作不变量断言——它在本系统里是正常形态。

同理，**削弱一个断言前必须做变异测试**：把 `stdout>0 && stderr>0` 放宽为
`stdout+stderr>0` 之后，一个"在上限路径静默丢弃 stderr"的真实回归
整套用例 rc=0 全绿（改回旧断言则 rc=1 被捕获）。放宽的依据只能是
"被测对象的保证是什么"，不能是"改完就不再偶发失败"。

## 未决

- **`switchExpression` 的目的地**：条件 3 要求给它显式目的地参数
  （绑定路由 `v.t`、参数路由用被调方参数），`sw.t` 仅作无契约时的兜底。
  实现席在跑（`out/switchexpr-destination`）。**该席必须报告"输出未变"是
  合法结果**，不得为让修改显得必要而制造行为差异。
- **单返回快速路径**（`functionLiteralInner`）从未应用边界转换：
  `lambda-fix-xcheck` 的 P1 探针在两棵树逐字节相同且都失败。属残留缺口。
- **J 类迁移**的契约未定义。
