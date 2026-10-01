# 可失败警告门禁接线（t-muornewc-n52w）

## 决策：B，基线差值门禁

本轮不修改 `reference/**` 生成物，也不假装清偿既有存量。门禁保存审计已测得的既有计数，只允许当前生成树的计数不高于该基线；任何新增警告使入口失败。基线来源是同一提交 `89dd80b2` 入库的审计原始输出，而不是手抄数字：

| 目标 | 基线 | 可复算形状 | 来源 SHA-256 |
|---|---:|---|---|
| Dart | 46 | `^warning` 行 | `docs/architecture/evidence/zero-warning-gate-coverage/dart-analyze.log`, `07264594db77ad9899ee6eb2a81f779850ad1931d417ffed4d7404dd0cad8eda` |
| Kotlin | 59 | `<file>.kt:<line>:<col>: warning:` | `kotlin-compile.log`, `b86d468fcbf77c4094a4481f3089690bd7843cf2e34b49c1` |
| Rust | 4 | 生成树文件的 `-->` 引用行（排除插入符/上下文/汇总） | `rust-baseline-check.log`, `c091f9de8287eaa3bb519ae4dab7d71ba94bf88814e186e0611c19b51b4c8838` |
| Swift / TypeScript | 0 | 编译器 warning 行 | 本轮门禁中的严格入口；审计未给出存量，故基线只允许 0 |

Dart/Kotlin/Rust 的原始计数、受控注入和严格/宽松 rc 见审计报告及其 `verify.sh`。门禁实现为 `tools/warning-gate/check.sh`，package 入口为 `bun run warning:gate`，并接在 CI linux 作业生成全部目标树之后、测试之前。`collected-suite` 原职责未改动。

## 入口行为

入口分别运行宽松命令（用于计数）和严格命令：Dart `--fatal-warnings`、Kotlin `-Werror`、Rust `RUSTFLAGS=-D warnings`、Swift `-Xswiftc -warnings-as-errors`，以及 TypeScript 的独立 typecheck。严格 rc 直读并打印；在 B 方案下既有存量会使严格 rc 非零，因此门禁判据是“实测计数不得超过可复算基线”，而不是把已知存量误报成新增。

脚本在生成树不存在时明确失败，避免空目录/缺失输出伪造 0。所有临时日志位于 `/tmp` 并由 trap 清理。

## 实测边界

本 worktree 当前 checkout 没有生成树（`reference/dart/gen`、`reference/kotlin/gen`、`reference/rust/gen` 均由 `.gitignore` 排除），且本环境 `nix develop` 不可用；因此不能诚实声称已经在“当前树”跑过正向入口，也不能给出本轮未实测的正向 rc。CI 会在同一入口前执行既有 `gen:*` 链接线。审计提交已有同树正/反向证据：Dart 受控 warning 宽松 rc=0、严格 rc=2；Rust 宽松 rc=0、严格 rc=101，诊断逐字记录在对应日志中；`verify.sh` 移除临时注入后清理 `/tmp`。

本轮因此交付的是接线和可复算 B 判据，不宣称存量已清偿；后续清偿行应逐目标把基线降至 0，再把门禁基线改为 0，并重跑同一正/反向证据。
