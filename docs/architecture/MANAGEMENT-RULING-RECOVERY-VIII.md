# Management ruling — Recovery VIII 管理评审裁定（对 MANAGEMENT-REVIEW-REQUEST-2026-10-01 的答复）

> **队长核准，随本文件提交生效。**
> 本裁定草案写于 `.tq-logs/viii/management-ruling-recovery-viii-DRAFT.md`，经独立复核
> （`.tq-logs/viii/r23-draft-substantive-review.md`）接受，由队长亲核后核准入仓。

---

## 0. 席位与权限边界（先行声明，贯穿全文）

- **席位**：本轮正式管理评审席（Recovery VIII 管理评审），答复
  `boring/docs/architecture/MANAGEMENT-REVIEW-REQUEST-2026-10-01.md`。
- **本席不是 Sol**，不冒充任何历史轮号（005/065/137/215/245），不虚构 Sol 签名。
  本席依据恢复计划 R2.3 授予的程序性授权、以本轮管理评审席身份出具裁定。
- **日期**：2026-10-02 (America/Toronto)。
- **产品**：`boring`，分支 `arch/agent-guided-governance`，当前 HEAD `090f7b59`。
- **模型身份**：DeepSeek Harness 子代理，模型 `deepseek-v4-pro-0813-oc`。

**授权原文（verbatim，本席据以行事，不捏造权限）：**

> `audit-reports/disaster-report-and-recovery-plan-2026-10-01.md:95` — R2.3 —
> *"更新台账条件 1/2/4 行反映已完成工作；**发起下一轮 Sol 管理评审**确认
> （RULING-137 所说 "later explicit ruling" 由程序自身的评审机制出具，不需要项目
> 属主扮演法官）"*

> `MANAGEMENT-RULING-137.md:32-35` — *"Until condition 4 is satisfied and **a later
> explicit ruling says otherwise**: do not nominate, do not declare a pass, and do
> not change its status."*

> `MANAGEMENT-REVIEW-REQUEST-2026-10-01.md:16-17` — *"The next round number belongs
> to the review that answers this request, not to the seat filing it."*

恢复计划 R2.3 明文规定："later explicit ruling" 由**程序自身的评审机制**出具，
不要求项目属主扮演法官。本席即是该程序评审机制在本轮的执行席。据此本席有权出具
本裁定；请求文件 §0 亦确认「下一个轮号属于答复该请求的评审」。

---

## 1. 读入与依据

本席读入并核对：

- `MANAGEMENT-REVIEW-REQUEST-2026-10-01.md`（R2.3-b 席位 2026-10-01 提出）
- `MANAGEMENT-RULING-137.md`（条件 4 NOT SATISFIED；禁令 :32-35）
- `MANAGEMENT-RULING-245.md`（旧候选 `c8ae0054` 永久 REJECT；后继须新候选+re-freeze+双独立复核）
- `GATE-LEDGER.md`（HEAD `090f7b59`，:28-30 记录后继 `2ba5766b` 已冻结；:71-74 条件 1/2/4 行）
- `REFREEZE-SUCCESSOR.md`（R3.2 冻结 `2ba5766b`）
- `docs/architecture/evidence/condition-1-2-generation/r22-three-way-check-REPORT.md`（条件 1/2 三向检查，仓内）
- `docs/architecture/evidence/condition-4-entry-gate/README.md`（条件 4 仓内证据入口）
- `docs/architecture/evidence/condition-4-entry-gate/evidence/package-shell-adjudication-REPORT.md`（执行者裁定报告）
- `docs/architecture/evidence/condition-4-entry-gate/evidence/verify-eec707b9-REPORT.md`（独立五主张核验报告）

本轮复验记录（`.tq-logs/viii/r22-condition4-review.md`、`.tq-logs/viii/r22-condition12-review.md`、
`.tq-logs/viii/r23-management-review.md`）为**辅助记录**，不在产品仓内；本裁定引用仓内
等效证据路径。

关键事实链（本席据其裁定）：

1. **条件 1/2/4 的 entry-gate 证据形式均已满足**：三向检查对 `2aadcb69`（条件 1/2）
   与 `eec707b9`（条件 4）均独立复验四要求全部 CONFIRMED；`gate:verify` PASS
   （1455/0/RC=0，两独立运行 file-list sha256 `551628d3…` 一致）。
2. **条件 1/2 的 R4 执行者报告+独立复核报告已入仓**（commit `922d2a4b`，`implementer-REPORT.md`
   + `independent-reviewer-REPORT.md`，sha256sum 4/4 OK）。
3. **条件 4 的 R4 双报告已入仓**（merge `84eff599`，`package-shell-adjudication-REPORT.md`
   + `verify-eec707b9-REPORT.md`，sha256sum 15/15 OK）；spec ruling 内容已解决
   （`stale expectation, not product defect`，三配置 exit 0/1/0 可复现）。
4. **后继候选 `2ba5766b` 已冻结**（R3.2，`REFREEZE-SUCCESSOR.md`；`GATE-LEDGER:28-30`）。
5. **后继候选的双独立 ACCEPT 复核 = 0/2**。现有 R3.3-a（组件技术主张）与
   R3.3-b（冻结点/字节复核）均**不是** RULING-245 点 2 要求的「对同一冻结 revision
   的两份独立复核」。

---

## 2. 逐条裁定（ACCEPT / REJECT）

### 条件 1（clean-input 重复生成字节一致）— **ACCEPT（SATISFIED）**

entry-gate 四要求独立 CONFIRMED；技术主张（5 次 clean 生成唯一哈希）由执行者报告+
独立复核报告 CONFIRMED 且已入仓。RULING-137 从未对条件 1 的「satisfied」作过
裁定，故本席在此裁定：**条件 1 satisfied。**

### 条件 2（MathNaNTestSupport 条目稳定）— **ACCEPT（SATISFIED）**

entry-gate 四要求独立 CONFIRMED；技术主张（405/absent 稳定、字节同一测试反复通过）
CONFIRMED 且已入仓；`GATE-LEDGER:72` 的 `:338` 行号引文经独立复验精确。本席裁定：
**条件 2 satisfied。**

### 条件 4（package-shell.test.ts:249 的独立 spec ruling）— **ACCEPT（SATISFIED）**

原恢复计划 R2.1/R2.2 指出的报告入仓及独立核验缺口现已闭合：两报告已入仓、
15/15 校验通过、三向检查 CONFIRMED。RULING-137:17-19 仅记录当时 NOT SATISFIED，
不在此追加其未明述理由。本裁定即 RULING-137 预留的 "later explicit ruling"：
**条件 4 satisfied，推翻 RULING-137:17-19 的 NOT SATISFIED。**

---

## 3. RULING-137:32-35 禁令 — **解除（LIFTED）**

RULING-137:32-35 的禁令解除是两个**并列**条件，缺一不可：

1. **condition 4 satisfied** — 本裁定 §2 已裁定 satisfied，条件①满足。
2. **a later explicit ruling says otherwise** — 本裁定即该 later explicit ruling，
   条件②满足。

两条件均满足，故 **RULING-137:32-35 的禁令解除**：不再以该禁令禁止提名/声明/改状态。

**本裁定解除的仅限 `:32-35` 所列限制。RULING-137 的其余范围约束均**维持生效**、不为
本裁定所动，逐条显式保留：**

1. **条件 3 的合成限制（:11-16）**：条件 3 状态保持
   `EXERCISED (SYNTHETIC FLAKE-SHAPED INPUT; NO REAL FLAKE OBSERVED)`，措辞不变，
   不得被描述为「观察到真实 flake」。
2. **R2/R3 证据包不入 tars（:20-25）**：三个 ~32MB tars 不提交的决定**仍然 APPROVED
   且继续有效**，除非再生条件、校验和或独立性主张日后被认定无效。
3. **:37-38 的其余范围约束**：禁止新实现、新测试、新证据归档、历史改写（超出准备
   与 condition-4 验证之外的部分），仍按原裁定生效。本项不禁止本裁定链和原恢复计划
   R3 双独立复核所必需的审查报告与执行证据；该例外不授权新功能开发、泛化测试或额外
   归档普查。

**另明确（不自动接受 P08、不改变标准）：** 禁令解除≠后继候选被接受。
RULING-245 是一条**独立**的候选接受链（见 §4），P08 后继候选要真正走到提名/声明，
仍须满足 RULING-245 点 2/4。禁令链与候选接受链不可混写。

本裁定不改变 137:11-16 条件 3 的合成证据限制、20-25 不提交三份 tar 的政策、37-38
禁止扩张实施/测试/归档及改写历史的边界；只按恢复计划 R3 授权固定后继双审，不授权
正常治理开发。

---

## 4. RULING-245 的候选接受链 — 仍未完成，后继候选不得提名

| 步骤 | 状态 |
|---|---|
| 新候选冻结（re-freeze） | **已完成**：`2ba5766b`（R3.2） |
| 对**同一冻结 revision** 的两份**互不相同、独立**复核 | **未完成**：现有 R3.3-a（组件技术主张，非对冻结 revision 的复核）与 R3.3-b（冻结点/字节复核）均不构成 RULING-245 点 2 要求的「两份独立复核」 |

**下一步（本裁定明确，非指令取得两 ACCEPT）：** 对同一冻结 revision `2ba5766b` 发起
**两份独立复核**。复核结论**允许是 ACCEPT 或 REJECT**——本裁定不预设、不指令结论。
仅当两份独立复核**实际均为 ACCEPT** 时，后继候选才进入后续清偿（提名/声明/改状态）。
不预设结论。复核结果按原恢复计划 R3.4（:108）处理：双 ACCEPT → 清偿
（P08 判据 2/4、台账更新）；结论分裂（一 ACCEPT + 一 REJECT）→ 升级项目属主；
双 REJECT → 退回对应执行任务、不改冻结字节——**不得**将旧候选 `c8ae0054` 的封存
规则自动套用到新候选 `2ba5766b`。

**结论**：在 `2ba5766b` 取得两份独立 ACCEPT 复核之前，P08 维持 **NOT PASSED /
PREPARABLE / NOT NOMINATE-ABLE**，其状态不得被描述为「已解除阻塞」。禁令的解除不
改变这一状态，因为提名资格的门槛现在落在 RULING-245 的双独立复核上。

---

## 5. 旧候选 `c8ae0054` — 维持永久 REJECT（不变）

RULING-245 点 1/4：`c8ae0054 = P08 NOT PASSED / REJECTED`，**永久、最终**。本裁定不
重开、不修补、不据此推进。任何把 `c8ae0054` 的双 REJECT 当作后继 `2ba5766b`「已有
双审」的读法都是对象错误。本裁定维持该封存状态不变。

---

## 6. 观察项（记录，不在本裁定范围，不改台账）

- `GATE-LEDGER:60` 仍写「a re-freeze is the next step」——此句写于冻结 `2ba5766b`
  落地之前，与 `:28-30` 已记录的 re-freeze 事实矛盾，已过期（核准基线 090f7b59 时
  观察）。本提交同步修复：`next step` 现为对同一冻结 revision 的双独立复核（见
  GATE-LEDGER.md 同提交 diff 及本裁定 §4）。
- `GATE-LEDGER:278` 的「still read `in-flight`」陈旧措辞已由 `090f7b59` 修复，本席
  确认现文为「entry-gate evidence form is independently CONFIRMED」，与 :71-72 一致，
  无残留矛盾。

---

## 7. 结论（一句话）

**条件 1/2/4 均裁定 SATISFIED，RULING-137:32-35 禁令解除；但后继候选 `2ba5766b`
尚未取得对同一冻结 revision 的两份独立复核，故 P08 维持 NOT PASSED / PREPARABLE /
NOT NOMINATE-ABLE，下一步是对 `2ba5766b` 发起两份独立复核（结论可为 ACCEPT/REJECT），
仅实际双 ACCEPT 才进入后续清偿。**

---

## 8. 签署

- **席位**：Recovery VIII 管理评审席（本轮，非 Sol，非历史轮号）
- **模型**：DeepSeek Harness 子代理 / `deepseek-v4-pro-0813-oc`
- **日期**：2026-10-02 (America/Toronto)
- **对象**：`MANAGEMENT-REVIEW-REQUEST-2026-10-01.md`；`boring` HEAD `090f7b59`
- **状态**：队长核准，随本文件提交生效
- **草案原始位置**：workspace 根 `/home/losses/Development/tq-workspace/.tq-logs/viii/management-ruling-recovery-viii-DRAFT.md`（归档提交 `f86de98`）
- **独立复核**：workspace 根 `/home/losses/Development/tq-workspace/.tq-logs/viii/r23-draft-substantive-review.md`（同归档提交 `f86de98`）— 接受