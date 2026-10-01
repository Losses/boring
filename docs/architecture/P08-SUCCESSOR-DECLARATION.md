# P08 SUCCESSOR CANDIDATE DECLARATION

> **DRAFT / PREPARATION ONLY / NOT YET DECLARED.**
>
> 本文件是 R3.1 的**可批注草案**，不是声明本身。在顶部标注改为 DECLARED 且
> 冻结记录落盘之前，本文件不产生任何候选身份，P08 后继候选**不存在**可指对象。
>
> 依灾害报告 §2 R3（`audit-reports/disaster-report-and-recovery-plan-2026-10-01.md`；仓外注记 2026-10-01：该路径为工作区级文件，位于 `/home/losses/Development/tq-workspace/audit-reports/`，不在 boring 仓内，`git ls-files --error-unmatch` 不解析），
> 本声明的定稿前置条件是 **R1 与 R2 全部完成**；此前不得在任何台账、裁定文件或
> 本文件中把本草案当作已声明/已冻结的候选引用。
>
> 候选内容身份核对日期：2026-10-01（读数基点 `f6f7e3d3` =
> `arch/agent-guided-governance` 当时 HEAD；`git merge-base --is-ancestor` 均在
> `f6f7e3d3` 上复核）。

---

## 1. 候选构成的逐项身份

依 `MANAGEMENT-RULING-245.md` 点 2/3：修复必须并入**一个**清晰识别的新候选、
一并冻结；`449444cf` 属后继候选内容，永远不得引作 `c8ae0054` 已被修复的证据。

| 成分 | revision | 身份 | `git merge-base --is-ancestor <sha> f6f7e3d3` |
|---|---|---|---|
| 前候选谱系基 | `c8ae0054d8b1937cf05c0dd849c268807ae19b8f` | fix(swift): lambda return contract, with the block destination it exposes | rc=0（在） |
| lambda 快速路径修复 | `449444cf` | fix(swift): apply destination conversion on the single-statement lambda fast path | **rc=0（在）** |
| S1 源提交 | `cd70eb12` | fix(swift): do not emit statements after one that diverges（引入 `stmtDiverges`，发射端剔除发散后死语句，`-c -WMO` 诊断 1→0） | **rc=0（在）** |
| S1 上线合并 | `e550fa52` | merge: prep/p08-s1-unreachable-return into arch/agent-guided-governance | **rc=0（在）** |

即：**谱系 = `c8ae0054` + `449444cf` + S1（`cd70eb12` 经 `e550fa52` 在线）**，
三个承重 revision 在基点 `f6f7e3d3` 全部可寻址且为祖先。候选 revision 本身
（声明所冻结的单个 commit）**尚未存在**——冻结属 R3.2。

## 2. 声明所依据的裁定原文（引用，不转述）

**RULING-245（`docs/architecture/MANAGEMENT-RULING-245.md`，Operative points 2/3/4）：**

> 2. **A fix that changes generated text is a change of candidate content**, even
>    when run semantics are unchanged. Clearing the unreachable trailing `return`
>    therefore **cannot** be booked as "clearing the diagnostic" on the original
>    candidate: it requires a **new candidate**, a re-freeze, and **both**
>    independent reviews again, with the independence requirements still met.
>
> 3. **The lambda single-statement fast-path defect already exists in `c8ae0054`**,
>    so repairing it likewise requires a new candidate, a re-freeze, and both
>    reviews. If both repairs are to be kept, they belong in **one** clearly
>    identified new candidate frozen together.
>
> 4. … Progress, if any, requires preparing a new candidate that contains the
>    necessary repairs; until that candidate is frozen, P08 must not be described
>    as unblocked.

**BUILD-PHASE-DIAGNOSTIC-RULING.md（技术裁定，协调者补注）：** 对 `c8ae0054`
维持「P08 NOT PASSED / REJECTED，最终」；S1（`cd70eb12`）经独立复现确认
`swiftc -c -WMO` 诊断 1→0（计数须按 `<path>:<line>:<col>: (warning|error):`
形状计数）；「在获得管理层确认前……不得提名 S1」——本文件即该确认落地前的
**准备**，提名动作属 R3.1 定稿。

**两份独立复核的验收要求**（RULING-245 + review 2 条件，见
`dc-warn/out/p08-review-2/REPORT.md`，[INHERITED]）：任何接受必须指名
revision 哈希、该 revision 上实测的 `swiftc -c -WMO` 诊断数 = **0**、以及
fixture 自带自动化 `-c` 断言存在且通过的那个 revision。

## 3. 尚未完成的两步（声明 → 可评审之间的空隙）

1. **冻结（R3.2）**：在 R1/R2 落地后的 HEAD 上执行
   `bun run gate:verify -- <revision>` 出 R2/R3 包，然后写 RE-FREEZE 记录，
   冻结包含 §1 全部内容的单个候选 revision 并 `git rev-parse` 留档。**本草案
   §1 的三个 rc 只证明成分在线，不等于冻结。**
2. **两份互不相同的独立复核（R3.3）**：两席互不相同、均未参与实现与冻结，
   复核同一冻结 revision；两份 VERDICT 均 ACCEPT 后 P08 才可视为通过。
   定稿前 P08 维持 NOT PASSED / REJECTED，最终，不得在任何台账改写。
