# 架构治理：问题分类、契约与分层验证

本目录是 Boring 架构治理三项产物的落地位置：

| 文件 | 内容 |
|---|---|
| `PROBLEM-CLASSIFICATION.md` | 跨目标共用的**问题分类**（A–F 六类编译器职责及其属主） |
| `ARCHITECTURAL-CONTRACTS.md` | **架构契约**（接口两端各自承诺什么） |
| `LAYERED-VERIFICATION.md` | **分层验证方案**（每层用什么可观察量检验，以及该判据何时骗人） |

每份文档都带「未决」一节：未决项是文档的一部分，不另立台账。

## 数据目录（2026-10-03 已迁出）

本目录只保留规范性架构文档；机器特定证据数据已随清仓（任务 t-muso22x7-878v）迁出产品仓，现位于 workspace 归档 `boring-docs-archive/`（`MANIFEST.sha256` 全量校验，板上迁址 note 可查）：

- 原 `evidence/`：各轮验证/审计的原始证据（REPORT、日志、哈希清单），含 16 个子目录与 `LOOP-LAMBDA-FROM-INDEXOF.md`。
- 原 `p09-f32-baseline/`：P09 f32 baseline 的版本化输入——`SOURCE_MANIFEST.json`（candidate `77c493b5` 的 15 项输入逐文件 sha256）、`expected.json`（preparation-only，含 PrintedFloatTests 6 条显式豁免与撤销条件）、`inputs/` 快照。
- 原 `bunfig-collection-fix.diff`：bun test 收集修复补丁记录（bunfig.toml 排除 `out/**`）。

## 与 wb 系统的关系

本目录只保留架构文档与数据。**进度管理内容（任务状态、台账判决、合入事实、审计读数、裁定、过程记录）已全部迁入 wb 系统**（迁移任务 t-musjpp6r-k39m，2026-10-03）：

- 任务状态与一次性事实 → wb 看板任务行 note / evidence（父任务 t-musjpp6r-k39m 汇总）。
- 可复用跨任务判断 → wb Wiki（notes.json，ref PIT/TCN/ARC）。
- 常设章程（目标/完成判据/角色权限/文档职责表）→ wb 里程碑 m-mulwvr32-3jht 描述。
- 已退役的叙述性文档（GATE-LEDGER、MANAGEMENT-RULING 系、REFREEZE 系、MERGE-REGISTER、STATUS-CHANGE-AUDIT、GOVERNANCE-SWEEP、rulings/ 等 28 个 .md）在 git 历史中可追溯（forward 删除，未改写历史）。

## 约束性验收标准

约束性验收标准是 `docs/specs/style/02-translator-implementation-standard.md`（:78/:80 定义零警告与计数口径）。本目录不重复该标准。
