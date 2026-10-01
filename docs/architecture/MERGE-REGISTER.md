# MERGE REGISTER — arch/agent-guided-governance 上 2026-10-01 批次的合入追溯登记

## 0. 目的与口径声明（先读）

本登记记录的是「**已在主干**」这一**事实**，且仅此事实：

- 本登记**不构成签核**，不改变任何看板行状态，不代表任何判据已满足或任何工作已完成。
  「已在主干」与「判据已满足/已完成」是两件必须分开记录的事（灾害报告 §1.2 影响 C：
  状态与事实混同正是本次灾害的成因之一）。
- 看板 `merges` 字段为空是**已知 schema 限制**而非遗漏：现有工具面中 merges 数组的唯一
  写入入口 `wb_merge` 以 `confirm=` 必填、语义是签核、且会把行置为已合并——把它用在
  未经签核的记录上等于伪造签核，落在 doing 行上更会制造被明令禁止的「已完成」假象
  （**PIT-477**）。故本批追溯补记由**时间线 note + 本入库登记**双轨承载。
- 读数基点：`b1188eec..f6f7e3d3`（`git log --oneline --merges` 恰 17 条，见 §4）。
  `f6f7e3d3` 是 2026-10-01 15:37–15:41 EDT 合入批次的顶端提交；`arch/agent-guided-governance`
  此后另有纯文档提交前进（`f8df0ef6`、`7792198e`），不影响本表。
- 表内 17 个 merge sha 对 `f6f7e3d3` 的 `git merge-base --is-ancestor` 逐一核验，**全部 rc=0**。

## 1. 有对应看板行的 12 条合入

| 分支名 | merge sha | 看板行内部 id | 行 status | patch-id 核验 |
|---|---|---|---|---|
| warn/dart3 | `f6f7e3d3` | `t-muhbbydw-w3w4` | doing | 无内容缺失 |
| warn/ts3 | `608bc9b6` | `t-muhbc7gp-sg81` | doing | 无内容缺失 |
| warn/r1 | `d1834102` | `t-muhbc7hk-zvbl` | doing | 无内容缺失 |
| fix/p09-roots-guard-candidate | `7b4aaf8b` | `t-mup5fwpz-xegn` | done | 无内容缺失 |
| integrate/rust-module-keyed-read-sites | `c037054e` | `t-mup59qau-cnqh` | done | 无内容缺失 |
| fix/rust-perchar-units-for-loop | `f256dba2` | `t-mukem10i-n8ll` | done | 无内容缺失 |
| fix/integrity-checker-byte-offset | `2ecc365e` | `t-mun9hxa8-fsmg` | done | 无内容缺失 |
| docs/p10-ledger-reconciliation | `cbb6a0ca` | `t-mup47bdm-av4j` | done | 无内容缺失 |
| audit/variable-bound-loop-eval | `a7c5a9df` | `t-mum0usfn-wwg8` | doing | 无内容缺失 |
| chore/archive-xs-fixture-family | `42b4f7d3` | `t-munejtq3-mj9x` | done | 无内容缺失 |
| prep/p09-f32-baseline-rebuild | `76f3e300` | `t-mup4nyxh-mlvw` | done | 无内容缺失 |
| audit/fallibility-downgrade-from-pit248 | `da21da29` | `t-mungw3ci-0i43` | done | 无内容缺失 |

**口径注（warn/dart3 一条）**：`warn/dart3` 不是 `t-muhbbydw-w3w4` 行的 `branch` 字段值
（该行 branch 是 `warn/dart6`），而是该行 **claim 历史第 3 条**（2026-09-27T16:58:59Z）——
即本条是「claim 分支而非行 branch」的对应关系，不是普通的 branch 字段匹配；
`f6f7e3d3` 恰为该批次合入的顶端提交（见 §0）。

## 2. 无对应看板行的 5 条合入

| 分支名 | merge sha |
|---|---|
| prep/p08-s1-unreachable-return | `e550fa52` |
| evidence/contract3-condition4-closure | `95040235` |
| arch/policy-a-comparison-plan | `a3e1d795` |
| prep/p08-candidate-material | `f3ad1b49` |
| audit/session-integration | `0c83991a` |

这 5 条是**素材/证据类分支，无独占看板行**（prep / evidence / audit 产物归入
共享治理文档或证据目录，不对应单一可交付行）。本节**不扩大 R5.1 范围**：
这 5 条的去向由 **R5.2 幽灵行对账**决定，本登记只证明「已在主干」这一事实。

## 3. 附节：看板寻址歧义（给后来者的纪律）

独立复核结论（2026-10-01，本席重算）：

1. **按分支名寻址会同时匹配 claim 分支**，不只 `branch` 字段：一行的历史 claim 分支
   （如 `t-muhbbydw-w3w4` 的 `warn/dartts`、`warn/dart3` 等 5 条 claim）也会被分支名
   寻址命中。已知事故：2026-10-01T18:31:58Z 一条备注被写入 `t-muhbbydw-w3w4`
   （经其 claim 分支 `warn/dartts` 命中），写入者本意是 `t-muhbc7gx-g021`
   （该行 branch 恰为 `warn/dartts`），写入者已于 18:32:53Z 自行撤回。
2. **重名分支集合（本席实测重算，与协调席数字一致）**：`fix/rust-runtime-default-bytes-print` ×4 行、
   `warn/swift` ×3 行、`warn/kotlin` ×3 行、`fix/swift-bundle-open` ×2 行、
   `cutover/stage1-p5b-kotlin` ×2 行（空 branch 字段不计）。

**一句话纪律：写看板一律用行内部 id（`t-…`），不用分支名寻址。**

## 4. 核验原始输出（摘录）

`git log --oneline --merges b1188eec..f6f7e3d3`（完整 17 行）：

```
f6f7e3d3 merge: warn/dart3 into arch/agent-guided-governance
608bc9b6 merge: warn/ts3 into arch/agent-guided-governance
d1834102 merge: warn/r1 into arch/agent-guided-governance
e550fa52 merge: prep/p08-s1-unreachable-return into arch/agent-guided-governance
7b4aaf8b merge: fix/p09-roots-guard-candidate into arch/agent-guided-governance
c037054e merge: integrate/rust-module-keyed-read-sites into arch/agent-guided-governance
f256dba2 merge: fix/rust-perchar-units-for-loop into arch/agent-guided-governance
2ecc365e merge: fix/integrity-checker-byte-offset into arch/agent-guided-governance
cbb6a0ca merge: docs/p10-ledger-reconciliation into arch/agent-guided-governance
95040235 merge: evidence/contract3-condition4-closure into arch/agent-guided-governance
a7c5a9df merge: audit/variable-bound-loop-eval into arch/agent-guided-governance
a3e1d795 merge: arch/policy-a-comparison-plan into arch/agent-guided-governance
42b4f7d3 merge: chore/archive-xs-fixture-family into arch/agent-guided-governance
76f3e300 merge: prep/p09-f32-baseline-rebuild into arch/agent-guided-governance
f3ad1b49 merge: prep/p08-candidate-material into arch/agent-guided-governance
da21da29 merge: audit/fallibility-downgrade-from-pit248 into arch/agent-guided-governance
0c83991a merge: audit/session-integration into arch/agent-guided-governance
```

祖先核验：上列 17 个 sha + `f6f7e3d3` 自身逐一 `git merge-base --is-ancestor <sha> f6f7e3d3`，
**全部 rc=0**（逐条输出存 `audit-reports/r51-merge-register-2026-10-01.md`；仓外注记 2026-10-01：该路径为工作区级文件，位于 `/home/losses/Development/tq-workspace/audit-reports/`，不在 boring 仓内，`git ls-files --error-unmatch` 不解析）。
看板行 id / status 与 §1 表逐行经看板读数核对一致（2026-10-01T21:00:56Z 快照）。

## 5. 灾害恢复批次合入（`f6f7e3d3` 之后，补记于 2026-10-01）

口径与 §0 相同：**本表只证明「已在主干」这一事实，不构成签核**，不改变任何看板行状态。
本节由协调席补记，用于关闭 H6 审计发现的缺口——「26 条 `recov/*` 合入（`f6f7e3d3..cfec9666`）
0 板行 0 字段 0 登记」。补记时主干已推至 `ed70c6c8`，故核验基点取 `ed70c6c8`。

| 分支名 | merge sha | 对应看板行 |
|---|---|---|
| recov/r21-evidence-intake | `84eff599` | 无独占行（证据入仓） |
| recov/r51-merge-register | `6af45096` | 无独占行（本登记的产出分支） |
| recov/r56-hardening | `f4d1f94e` | 无独占行（门禁加固） |
| recov/r22d-p10-disposition | `25848069` | 无独占行（P10 处置） |
| recov/r23-review-request | `a62f096b` | 无独占行（评审请求） |
| recov/r23-ledger-conditions | `d3c3492f` | 无独占行（台账条件行） |
| recov/r56rr-gate-redteam | `453ed54d` | 无独占行（红队复核） |
| recov/r31-successor-declaration | `2ba5766b` | 无独占行（后继候选声明） |
| recov/r54r-roots-guard-review | `0b6ec7e7` | 无独占行（roots-guard 复核） |
| recov/r43-vble-unblock | `cf08733d` | 无独占行（可变界限解除阻塞） |
| recov/r34-governance-sweep | `649aa881` | 无独占行（治理扫描） |
| recov/r22c2-sums-sync | `b2f081bf` | 无独占行（校验和同步） |
| recov/r56d-board-trust-root | `b2cf180c` | 无独占行（看板信任根） |
| recov/r34c-enforcement-points | `0048623a` | 无独占行（强制点） |
| recov/r32-successor-refreeze | `a64c7160` | 无独占行（再冻结） |
| recov/r2d-cond12-evidence | `5894bf6c` | 无独占行（condition 1/2 证据） |
| recov/r34e-status-wiring | `15f7ae54` | 无独占行（状态接线） |
| recov/r3c-ledger-refreeze | `10d5d751` | 无独占行（台账再冻结） |
| recov/r54s-rootfloor-signoff | `ddfd36a9` | 无独占行（rootfloor 签核） |
| recov/r44c-ts3-criterion4 | `ccfe6869` | 无独占行（ts3 判据 4） |
| recov/d4-refreeze-table | `c8a7b202` | 无独占行（REFREEZE §3 重算） |
| recov/d1-installer-wiring | `008a12ce` | 无独占行（install.ts 接线） |
| recov/d3-q1-relevance | `6d8c071d` | 无独占行（Q1 相关性校验） |
| recov/d5-freeze-anchor | `73e0bbe2` | 无独占行（P08-3 断锚） |
| recov/d8-flake-synthetic | `4ee84cb1` | 无独占行（flake-synthetic 入仓） |
| recov/d6-e2e-evidence | `4fae343f` | 无独占行（e2e-run 入仓） |

**为何这 26 条全无对应看板行**：它们是灾害恢复的执行分支，工作对象是**治理文档、证据树与门禁工具**，
不落在任何单一行名下（同 §2 的 prep/evidence/audit 类）。其去向由 §3.5 条件 3 的对账决定，
本表不做归属判断。

**合并信息约定不一致（记录在案）**：本批 21 条沿用了既有 `merge: <branch> into <mainline>` 的消息格式，
另有 5 条（`c8a7b202`/`008a12ce`/`6d8c071d`/`73e0bbe2`/`4ee84cb1`）由 git 默认格式生成，
形如 `Merge branch '<branch>' into <mainline>`。两种格式并存不影响 `git log --merges` 计数，
但按 `merge: ` 前缀做机器提取时会漏掉那 5 条——**提取时不要只 grep `^merge:`**。

祖先核验（协调席自跑，2026-10-01）：`git log --format=%H --merges f6f7e3d3..ed70c6c8` 得 **26** 条，
逐条 `git merge-base --is-ancestor <sha> ed70c6c8` **26/26 rc=0**。

未做：本节未做 patch-id 逐条核验（§1 表做过），故不声称「无内容缺失」；该缺口见 H6 报告 §8。

## 6. 灾害恢复第二批合入（`ed70c6c8` 之后，补记于 2026-10-01）

口径与 §0/§5 相同：**本表只证明「已在主干」这一事实，不构成签核**，不改变任何看板行状态。
§5 的截止基点是 `ed70c6c8`，其后的合入在 H6 复核口径下仍属未登记，故由协调席在此补齐。
核验基点取本节提交时的主干 `18cff037`。

| 分支名 | merge sha | 对应看板行 |
|---|---|---|
| recov/d7-r1-residual | `06c8a368` | 无独占行（R1 残余引用） |
| recov/h2-rulings-fixtures | `c66e2bf9` | 无独占行（裁定夹具污染 merge-precheck，PIT-487） |
| recov/h7-e2e-provenance | `0977f964` | 无独占行（e2e-run 逐文件保留理由） |
| recov/h9-out-evidence-ingest | `38d20a16` | 无独占行（out/ 证据入仓 159 文件） |
| recov/h10-doc-style-scope | `648fd67c` | 无独占行（doc-style 扫描范围，PIT-493） |
| recov/h1-precommit-baseline | `b3cbac1b` | 无独占行（pre-commit 基线门禁，PIT-488） |
| recov/h13-precheck-direction | `e0f8fd65` | 无独占行（Check 2 判据方向，PIT-495） |
| fix/guard-landed-unrecorded | `1e8c76ce` | 无独占行（doing-row-guard 假阴性，PIT-494） |
| docs/vble-report-postfix-run | `18cff037` | 无独占行（VBLE 报告刷新） |

**补记背景**：`recov/h10-doc-style-scope`、`recov/h1-precommit-baseline`、
`recov/h13-precheck-direction`、`fix/guard-landed-unrecorded`、`docs/vble-report-postfix-run`
五条在本节之前已完成提交与席位自验，但**未合入主干**：协调席在会话尾部输出了「已合并」的
结论，实际因 `/tmp/merge-r27` 工作树脏、且 `recov/h10-doc-style-scope` 分支指针被错置为
H11 的提交 `a2364908` 而未落地。本次逐条独立复验后合入：Check 2 方向在合成仓上以
「基点早于新裁定」与「基点等于最新裁定」两例对拍（旧码前者误 PASS、新码 FAIL 且后者仍 PASS）；
`doing-row-guard` 在真实看板上复跑（`warn/kotlin` 三行 UNTRACEABLE 转 LANDED_UNRECORDED，
全板 UNTRACEABLE 27→20、LANDED_UNRECORDED 0→7、doing 行 33 不变）；
`recov/h10-doc-style-scope` 的分支指针复位到其自身提交 `cbcc9ccd`。

祖先核验（协调席自跑，2026-10-01）：`git log --format=%H --merges ed70c6c8..18cff037`
得 **9** 条，逐条 `git merge-base --is-ancestor <sha> 18cff037` 得 **9/9 rc=0**。

未做：与 §5 相同的 patch-id 逐条核验缺口。
