# 两个 Kotlin smart-cast 修复的语义冲突与判定

记录一个**真实的判据冲突**：两项各自正确的修复，在合并时**互相排斥**。
本文件是主 Agent 的架构判定，不是任何一方的执行报告。

参与方（都已并入或在途）：

| 来源 | commit | 主张 |
|---|---|---|
| A | `59afe821`（原 `f4e4c59d`，任务 `t-mup3p3ng-jyhk`） | 守卫打印 `!!` 时把字段 key 写进 `extractedFields`/`nonNullFields`，**但只在 `smartCastableSubject(e)` 时**写。理由：可变的 `var` 字段既不证明主体、也不许可丢掉下一次断言 |
| B | `f4c9f9d7`（任务 `t-mup4e8wh-6dnz`） | `fieldProven` 收窄为 `nonNullFields.exists(key) && fieldSmartCastable(e)`，其中 `fieldSmartCastable = FVar && isFinal && receiverRootStable`。理由：`receiverProven(TField) = fieldProven \|\| rootPresent`，只改 `fieldProven` 会被 `rootPresent` 绕过 |

## 1. 冲突是可测的，不是推测

合并后在 `boring-wt-mainline` 上实测（两次单向隔离，各只改一处）：

| 配置 | `tests/haxe/kotlin-var-field-smartcast`（A 的正控） | `tests/kotlin/smartcast-tfield`（B 的正控） |
|---|---|---|
| 保留 B 的 `fieldSmartCastable` 收窄 | **0 pass / 1 fail** | 1 pass / 0 fail |
| 去掉该收窄 | 1 pass / 0 fail | **0 pass / 1 fail** |

**两者不能同时为真。** 这不是偶发、不是环境、不是测试写错——两侧各自都在抓真缺陷。

## 2. 两侧各自在抓什么

A 的失败断言（`var-field-smartcast.test.ts:60`）：

```
var read must extract:
{ if ((holder.value != null)) { return holder.value.magnitude() } return -1 }
```

—— 可变字段的**守卫**没发 `!!`，于是读路径丢断言。

B 的失败断言（`smartcast-tfield.test.ts:103`，形状 `betweenWrite`）：

```
var a = Holder(Vec(1.0))
if ((a.value != null)) {
    if ((flag)) { a = Holder(null) }   // 守卫与读之间重赋值
    return a.value.magnitude()          // ← 裸点，kotlinc 拒绝
}
```

—— 守卫与读**之间**发生了重赋值，Kotlin 的数据流证明被打断，而发射端仍发裸点。

**两个都是真实的 kotlinc 拒绝。** 它们不是对立的诉求，而是**同一规则的两次独立表达**。

## 3. 判定的根因：同一个判断有两个来源（契约 6）

现在树上有**两个谓词回答同一个问题**（"这个字段访问能不能靠 Kotlin 的 smart-cast 走裸点"）：

- A 的守卫侧：`smartCastableSubject(e)`（`KotlinExpr.hx:3470` 定义，`:2748` 使用）
- B 的读侧：`fieldSmartCastable(e)`（`FVar && isFinal && receiverRootStable`）

两者**描述的是同一条 Kotlin 规则**（字段可 smart-cast ⇔ 字段是 `val` **且**接收者稳定），
却被写成两份独立实现、两处独立调用点。这与 `ARCHITECTURAL-CONTRACTS.md` 契约 6
（"一个判断只能有一个来源；能从事实派生的，不得另行判定"）**直接冲突**，
也与本仓库既有的 PIT-388 / PIT-416 / TCN-162 同一族。

**所以正确的处置不是二选一，而是把两个谓词归一。** 在归一之前，任何"选一个合入"的
做法都会把另一侧变成稳定回归。

## 4. 处置

**当前决定：不合并 B，先把冲突落档。**

理由：B 的改动本身正确且有 PIT-388 背书（它实现的正是 PIT-388 列出的第二条建议），
但它与 A 在**同一谓词**上给出相反答案。在谓词归一之前合并，等于用一次 commit
换掉另一处的正确行为 —— 那不是修复，是回归搬运。

**下一步（需要一次归一，而非一次合并）**：

1. 抽出**唯一的谓词**（例如 `fieldSmartCastable`），让 A 的守卫侧
   （`KotlinExpr.hx:2748` 的 `smartCastableSubject(e)`）与 B 的读侧
   （`fieldProven`）**调用同一个函数**。
2. 该谓词必须同时满足两侧的可观察量：`val && 稳定` ⇒ 可裸点；
   否则两侧都取保守形态（守卫发 `!!`，读保留 `!!`）。
3. 归一后**两个测试必须同时通过**；这才是这一轮的完成判据，
   而不是"某一侧绿了"。
4. `receiverProven \|\| rootPresent` 的绕过问题（B 的 PIT-416）必须在归一里一并解决，
   否则归一只是把冲突挪个位置。

**本记录的用途**：任何后续把 A 或 B 单独合入的动作，都必须先回答"另一侧的
稳定失败怎么处理"；本文件给出的答案是**归一，不是取舍**。
