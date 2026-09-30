# 跨目标问题分类（A–F = 编译器职责）

本文件把 Boring 各目标（TypeScript、Kotlin、Rust、Swift、Dart）上反复出现的失败
归到有限几类**编译器职责**上。分类的用途不是统计，而是回答一个问题：
**一个新失败应该由哪一层负责，因而应该在哪里修、在哪里验证。**

## 分类的根据

分类取自本程序的既有记录，不是新造：
`docs/investigations/architecture-round-1/` 的调查、两席架构咨询
（`dc-warn/out/sol-architecture-consult/{SOL2-ARCH-ANSWER.md,ASTRA-ANSWER.md}`）、
`CODEX-AUDIT.md`，以及本会话四处已修复缺陷的机制。

## A–F 六类职责

| 类 | 职责 | 输入事实 | 拥有者 | 越界时的典型症状 |
|---|---|---|---|---|
| **A** | **源事实提取** | AST 上的类型、注解、字面量 | 前端 | 把未注解的推断当作事实 |
| **B** | **表示选择** | 该类型在目标语言里用什么形态 | 目标后端 | 同一 Haxe 类型在不同位置发出不同形态 |
| **C** | **边界转换** | 源与目标之间是否需要包装/解包 | 边界层 | 包装缺失或重复包装 |
| **D** | **目的地推导** | 这个位置需要一个什么类型 | **包围它的组合** | 借用无关的返回类型（**见 lambda 缺陷**） |
| **E** | **效果与生命周期** | 求值次数、惰性、别名、生命周期 | 组合 + 后端 | 重复求值、别名突变 |
| **F** | **诊断与抑制** | 生成的代码是否合法、有无 warning | 后端 | warning 被当作可接受 |

## 为什么 D 类必须有明确属主（本会话的核心教训）

lambda 缺陷（`dc-warn/out/lambda-return-contract/`）的机制是：
`currentReturnType` 是**成员**的返回类型，`functionLiteral` 不重绑它，
于是所有"返回位"站点读到的都是**外层函数**的类型。

**这不是 B 类（表示选择）错误，也不是 C 类（转换缺失）：**
转换代码本身是对的，错的是**它参照的目的地**。

⇒ **D 类的属主是"包围该位置的组合"**，而不是被包围的表达式，
也不是外层函数。Sol 的表述：*"Composition owns intermediate requirements"*
（`docs/compiler-policy-interfaces.md:169`）。

⇒ **判据**：若把同一个表达式放进不同的组合里会得到不同（但各自正确）的输出，
则该位置上**必须**由组合传入目的地，**不得**从全局状态推断。

## 各目标上的已知实例（映射，非清单）

| 类 | 实例 | 记录位置 |
|---|---|---|
| A | Kotlin：消费方读推断事实而非声明事实 | `out/kotlin-local-presence-facts` |
| B | Rust：`String` vs `UString` 宿主串表示 | 提交 `40cf0ad0` |
| B | Swift：`[Int32] = Array(...)` vs `ReadOnlyArray<Int32> = ReadOnlyArray(...)` | 提交 `9c9548ef` |
| C | Swift：只读数组边界包装（SW04） | `out/sw04-fix-wt` |
| D | Swift：lambda 返回契约借用成员类型 | 提交 `d14aae11`（**带回归，见下**）|
| D | Swift：`switchExpression` 从 `sw.t` 派生目的地 | `out/switchexpr-destination`（在跑）|
| E | Swift：`switchStatement` 剥离臂 `return` ⇒ 控制流出错（W1） | 提交 `d14aae11` |
| F | 全部：warning 计入验收（标准 `:78`/`:80`） | 记录 TCN-156 |

## 分类的使用规则

1. **定位到类，再定位到站点。** 只报"某文件某行错"不算定位。
2. **一处的修复不得改变别类的行为。** 四处已提交修复都做了全量生成树对比，
   逐字节相同是**必要条件**。
3. **类的属主与站点所在位置可以不同**（D 类就是如此）——
   这正是需要显式契约的原因。
4. **失败分类必须带归属**：候选之责 / 既存仓库状态 / 缺失文档
   （P10 记录的教训，`out/p10-reflection/ACCEPTANCE-REFLECTION.md`）。

## 本分类尚未覆盖的

- **J 类迁移**（legacy Kotlin → Haxe）的失败未归入 A–F；
  CODEX-AUDIT 指出 "complete J migration were not established"。
- **命名一致性**（ReadOnlyArray 命名违规）属于 F 还是独立类，未裁定。
- 各目标的实例表**不完整**：只列了本会话有记录的那些，
  不是各目标全部已知失败的清单。
