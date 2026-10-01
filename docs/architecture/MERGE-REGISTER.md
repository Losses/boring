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
**全部 rc=0**（逐条输出存 `audit-reports/r51-merge-register-2026-10-01.md`）。
看板行 id / status 与 §1 表逐行经看板读数核对一致（2026-10-01T21:00:56Z 快照）。
