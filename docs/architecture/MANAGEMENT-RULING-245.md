# Management ruling, round 245 — the P08 candidate is sealed

Retained verbatim because it is binding on what may and may not be done next.

## Operative points

1. **`c8ae0054` is NOT PASSED / REJECTED, finally.** Both independent reviews
   returned REJECT on the same ground. It may **not** be marked passing, and that
   rejection may **not** be lifted by supplementary explanation, ledger edits,
   repeated measurement, or re-interpreting the build-phase diagnostic. All that
   remains permissible on that candidate is preserving evidence, recording state,
   and stopping.
2. **A fix that changes generated text is a change of candidate content**, even
   when run semantics are unchanged. Clearing the unreachable trailing `return`
   therefore **cannot** be booked as "clearing the diagnostic" on the original
   candidate: it requires a **new candidate**, a re-freeze, and **both**
   independent reviews again, with the independence requirements still met.
3. **The lambda single-statement fast-path defect already exists in `c8ae0054`**,
   so repairing it likewise requires a new candidate, a re-freeze, and both
   reviews. If both repairs are to be kept, they belong in **one** clearly
   identified new candidate frozen together.
4. **Stop and seal `w2-diagnostic-fix`, `verify-c8ae0054` and
   `lambda-fastpath-fix` as they stand. Record `c8ae0054 = P08 NOT PASSED /
   REJECTED`. Do not commit, modify or rewrite that candidate, and do not open a
   new P08 review.** Progress, if any, requires preparing a new candidate that
   contains the necessary repairs; until that candidate is frozen, P08 must not
   be described as unblocked.

## Consequence recorded here because it is easy to misread

The lambda fast-path repair landed on the line as `449444cf` **before** this
ruling arrived. Under point 2 it is **not** a patch to `c8ae0054` — it is part of
the **successor** candidate's content. `c8ae0054` remains the reviewed object and
keeps its REJECT; `449444cf` must never be cited as evidence that `c8ae0054` was
repaired, and any future re-freeze must name a revision that includes it.

# 第 245 轮管理技术审阅裁定

## 依据

已记录并接受以下事实：

- `p08-review-1`（opencode-go）已交付，结论为 `REJECT`，并提出四个确切条件。
- `p08-review-2`（zai-coding-cn）由不同且独立的席位完成，席位未参与 P08 实现及 `c8ae0054` 冻结；其从 git archive 独立导出核验，结论同为 `REJECT`，理由一致。
- 两份复核均确认：在 `swiftc -c` 下，`Gap.swift:117:9` 有恰好一条 build 期诊断；标准要求为零，且不适用豁免。
- 两份复核均确认台账更正准确，且没有把冻结修订中不存在的字节归功于复核席。
- `c8ae0054` 已是被复核的候选；其后的完整性修复、超时预算核验等事实不改变该候选的复核结论。

## 裁定

### 1. P08 的当前最终状态

`c8ae0054` 的 P08 状态为 **NOT PASSED / REJECTED**。两份独立复核均为 `REJECT` 且理由一致，构成该候选的最终复核状态。

在不产生新候选的前提下，不得把 P08 标为通过，也不得以补充说明、台账修订、重复测量或重新解释 build 期诊断来解除该拒绝。原候选上可做的仅限于保存证据、记录状态和停止推进；不得再把任何源码或生成文本修复追加归属于 `c8ae0054`。

### 2. build 期诊断修复的候选归属

清除生成器发射的不可达尾 `return` 会改变生成文本。即使运行语义不变，这也是候选内容的变化，不能作为原候选的“诊断清偿”。

该修复完成后必须形成**新候选**并重新冻结；P08 必须重新走两份独立复核，且复核席位须继续满足独立性要求。原 `c8ae0054` 的 `REJECT` 不得被改写为通过或被追溯覆盖。

### 3. lambda 单语句快速路径缺陷

该缺陷在 `c8ae0054` 上已经存在，属于被复核候选的实质缺陷。修复它会改变候选内容，因此同样必须形成**新候选**、重新冻结，并重新走两份独立复核。不能在原候选上作为事后修补或验证性动作吸收。

若两个修复都要保留，应在同一个明确的新候选中完成后再统一冻结；不得让其中任一修复在未冻结状态下被宣称已解除 P08 阻塞。

## 下一轮最小动作（唯一指令）

**立即停止并封存 `w2-diagnostic-fix`、`verify-c8ae0054`、`lambda-fastpath-fix` 当前工作；记录 `c8ae0054 = P08 NOT PASSED / REJECTED`，不得提交、不得修改或重写该候选，也不得启动新的 P08 复核。**

后续若要推进，只能另行准备包含必要修复的新候选；在新候选冻结前，不得宣称 P08 已解除阻塞。 
