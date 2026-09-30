# Management ruling, round 5 (post-reset) — contract 3 downgraded, and a ledger gate required

Retained verbatim because it is binding. Operative points:

1. **Contract 3 is downgraded** from "achieved" to **"the gate is implemented; its
   run reliability is not achieved"**. The design and verifiability verdict is not
   withdrawn - the gate still fails on a missing log, an unparseable count, or a
   count deviating from the baseline - but it can also go red for a pre-existing
   npm-artifact non-determinism unrelated to any change under review, so its red
   light cannot be attributed and it is not usable as stable management evidence.
   Four conditions restore full achievement, all verified from committed content
   rather than by manual cleanup or a lucky re-run.
2. **Priority: repair the artifact non-determinism FIRST**, before preparing a new
   P08 candidate - because a new candidate must be frozen and reviewed in an
   environment that is attributable and reproducible, and otherwise the review's
   result can be polluted by unrelated archive-byte drift. P08 stays sealed:
   `c8ae0054` is NOT PASSED / REJECTED; no fix may be appended to it, it may not be
   reinterpreted, and no review of it may be opened. Fixing the flake does not
   change that rejection.
3. **The ledger's root cause is a missing process, not merely a discipline lapse.**
   Any ledger entry claiming "on the line / delivered / frozen" must carry: a
   traceable commit hash (uncommitted work may only be marked `in-flight`), a clean
   working-tree proof for that hash, the candidate content/checksums exported
   independently from that commit or from an explicit freeze archive, and a
   claim-versus-commit consistency check by both executor and reviewer. Before any
   status transition, a non-implementer performs a three-way
   `HEAD` / commit-hash / freeze-archive check; if it fails, the entry goes back.
   Oral delivery, workspace presence, or a later commit may not retroactively
   authorize a claim.

# 第 5 轮管理技术审阅裁定

## ① 契约 3 是否因既存制品 flake 受损

**裁定：契约 3 的设计与可验证性判定不撤销，但“已达成”必须降级为“闸门实现达成、运行可靠性未达成”。**

闸门仍然具备应有的失败能力：缺失、不可解析、偏少或偏多时会失败。因此，这个新事实不证明契约 3 的判别逻辑失效，也不允许把它改判为未实现。

但是，`collected-suite` 会因与被测改动无关的既存、可重复触发的 npm 制品非确定性而红，导致红灯无法归因。这样的闸门不能作为稳定的管理证据使用；因此不能继续无条件宣称契约 3 已完整交付。`package-shell.test.ts:249` 的确定性断言失败另记为产品/规格缺口，不得被错误归类为超时或用 flake 掩盖。

### 恢复完整“达成”所需的完成条件

以下条件须全部满足，并以提交后的内容验证，而非依靠手工清理或重跑碰运气通过：

1. 在同一固定工作树和相同依赖/工具链下，连续多次从干净输入生成 npm tgz；每次归档的字节内容和校验和完全一致。
2. 每次生成的 `MathNaNTestSupport.{js,d.ts}` 条目均稳定，不能再在 `407/405` 间摇摆；`package-artifacts.test.ts:333` 连续重复运行通过。
3. `collected-suite` 连续重复运行不再因该制品 flake 失败；日志能区分真实产品/规格失败与环境/超时失败。
4. 对 `package-shell.test.ts:249` 给出独立的规格裁定：要么修复并以测试证明，要么明确记录为仍未清偿的基线缺口；不得把它算作本 flake 的完成证据。

## ② 下一步优先级

**先修 CI 闸门所依赖的制品非确定性，再准备 P08 新候选。**

理由是：新候选必须在可归因、可复现的验证环境中冻结和复核；若先做候选，复核结果可能被无关的归档字节漂移污染，无法判断候选本身是否改变了结果。P08 仍保持封存状态：`c8ae0054` 是 `NOT PASSED / REJECTED`，不得追加修复、不得重解释、不得开启该候选的复核。完成 flake 修复也不改变该拒绝；之后若推进 P08，只能把必要修复放入新的候选，重新冻结并重走双独立复核。

## ③ 台账把未提交工作写成主线的根因

**裁定：主要是流程缺失，表现为纪律失守。** 单靠要求人员“更谨慎”不足以防止再次发生；台账缺少一个不可绕过的候选入账检查。

应新增以下门槛：任何“已落主线/已交付/已冻结”的台账条目，必须同时列出：

- 可追溯的提交哈希（未提交工作只能标为 `in-flight`，不得进入主线状态）；
- 该哈希对应的干净工作树证明；
- 从该提交或明确冻结归档独立导出的候选内容/校验和；
- 执行者与复核者确认的“台账声称与提交实际一致”检查。

在台账状态迁移前，由非实现者执行一次 `HEAD/提交哈希/冻结归档` 三方核对；核对失败就退回，不能以口头交付、工作区存在或后续提交补证来追认。复核席还必须只核验已提交、已冻结对象，不能把在飞工作当成候选证据。

## 下一轮最小动作（唯一指令）

**只建立一个隔离的 CI 制品可复现性修复任务：修复 `MathNaNTestSupport.{js,d.ts}` 在 npm tgz 中的非确定生成，并提交连续多次生成的逐字节一致证据；在该证据通过前，不准备新的 P08 候选、不修改 `c8ae0054`、不开启任何 P08 复核。**

本审阅只写入本文件；不修改仓库或任何既有文件。
