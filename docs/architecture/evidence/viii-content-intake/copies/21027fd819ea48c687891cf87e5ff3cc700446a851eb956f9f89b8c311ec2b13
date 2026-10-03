# 架构治理：问题分类、契约与分层验证

本目录是 Boring 架构治理三项产物的落地位置：

| 文件 | 内容 |
|---|---|
| `PROBLEM-CLASSIFICATION.md` | 跨目标共用的**问题分类**（A–F 六类编译器职责及其属主） |
| `ARCHITECTURAL-CONTRACTS.md` | **架构契约**（接口两端各自承诺什么） |
| `LAYERED-VERIFICATION.md` | **分层验证方案**（每层用什么可观察量检验，以及该判据何时骗人） |

## 与既有文档的关系

- **约束性验收标准**是 `docs/specs/style/02-translator-implementation-standard.md`
  （计划 `:63` 把 "acceptance rules" 指派给它）。本目录不重复该标准，
  只在契约 3 引用它并推出其**收集**含义（没有套件在跑 ⇒ 不产生计数 ⇒ 标准被绕过）。
- **任务顺序与状态**是 `docs/architecture-work-plan.md`（计划 `:65` 自述其职责为
  "task order, assignments, dependencies, and programme status"）。本目录不取代它。
- **边界策略记录**是 `dc-warn/out/boundary-policy-record/RECORD.md`；本目录引用其
  CORRECTION 13 的结论（三条 REFUSED 行为 PLANNER-CELL ONLY），不复制其正文。

## 这三份文档的来源

取自本程序既有的调查记录、两席架构咨询（SOL2 / Astra）与 CODEX-AUDIT，
以及本会话四处已修复缺陷的机制。**不是新调查**；目的是把散落在报告与
会话中的设计结论汇成可引用的形式。

## 每份文档都带"未决"一节

未决项是文档的一部分，不是缺陷：构建期诊断是否计入验收、J 类迁移的契约、
命名一致性的归类、单返回快速路径的缺口，均在各自文档中具名。
