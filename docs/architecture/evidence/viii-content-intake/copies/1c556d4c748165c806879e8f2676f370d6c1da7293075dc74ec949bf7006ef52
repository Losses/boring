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
  只是被绕过。**CI 当前不运行任何收集 `tests/**` 的命令**（`ci.yml` 的 26 个
  脚本中为 0），因此 50 个 `tests/ts` 文件与两个 Swift 夹具不产生计数。
- ⇒ 记录的形态必须是"**已知基线失败 + 显式 PIN**"，**不得**命名为"零诊断满足"：
  `tests/swift-gap-boundary/gap-boundary.test.ts:44` 的属主裁定即为本契约的落地。

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

## 未决

- **`switchExpression` 的目的地**：条件 3 要求给它显式目的地参数
  （绑定路由 `v.t`、参数路由用被调方参数），`sw.t` 仅作无契约时的兜底。
  实现席在跑（`out/switchexpr-destination`）。**该席必须报告"输出未变"是
  合法结果**，不得为让修改显得必要而制造行为差异。
- **单返回快速路径**（`functionLiteralInner`）从未应用边界转换：
  `lambda-fix-xcheck` 的 P1 探针在两棵树逐字节相同且都失败。属残留缺口。
- **J 类迁移**的契约未定义。
