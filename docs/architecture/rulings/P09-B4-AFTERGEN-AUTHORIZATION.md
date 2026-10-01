# B4 执行授权：`protocol-c afterGen`（Tiqian 侧 codegen 步）

> **状态**：已签署（协调席，2026-10-01）。本文件是书面授权记录，按
> `GATE-LEDGER.md` B4 行（:551）「`protocol-c afterGen` must not run without an
> explicit authorization」的要求落盘，清偿
> `manifest.json` `protocolCException.status = "requires-execution-authorization"` 一项。
> 依据 MR §9「已决事项直接执行并记录」。

## ① 事实（P09 准备席查实，2026-10-01；读数基点 Tiqian pin `8504d230`）

- **声明**：Tiqian `boring.json:121`（revision `8504d230228e8206689a2049bbb84b671c1f079a`）：
  bundle `protocol-c`，`"test": false`，
  `"afterGen": { "command": "bun", "args": ["engine-haxe/out/protocol-c/gen/c-header.js"] }`。
- **执行位置**：Boring driver `packages/driver/src/driver/Main.hx:325-328`——
  `actionGen` 在 `generate` 步（haxe 编译出 js）之后以 `step(..., "afterGen", ...)` 运行该命令；
  `step`（Main.hx:227-228）`cwd == null` 时用 `project.root`（= 工作树根）。
- **副作用范围**：生成的 `c-header.js` 由 Haxe 入口
  `engine-haxe/src/org/tiqian/protocol/CHeader.hx:45` 写出
  **`engine-haxe/out/protocol-c/gen/tiqian_protocol_constants.h`**（相对工作树根）。
  pin 自带文档同证：`engine-haxe/protocol-spec-notes-p4.md:52`、`engine-haxe/README.md:87-88`。
- **性质**：`test: false`，没有测试、不参与结果比较——它是 writer，不是测试。
- **判定**：隔离工作树内的 codegen；无网络、无全局状态、不触碰其他树；**未发现真实语义分歧，无需升级**。

## ② 授权决定（协调席，原文照录）

> 授权 P09 矩阵执行期间 protocol-c afterGen 的 codegen 步骤。理由：
> a) 该步骤是隔离工作树内的 writer，不产生跨树副作用；
> b) pin 自带的 protocol-spec-notes-p4.md:52 已记录同一副作用；
> c) RULING-137 的最小动作允许 close or verify condition 4，本授权即其中一项的执行记录；
> d) MR §9『已决事项直接执行并记录』。
> 边界：仅限 P09 矩阵一次执行、仅限隔离树、每步 argv/cwd/status/哈希留档，不得扩大到其它生成路径。

## ③ 清偿对象

- `GATE-LEDGER.md` B4 行（:551）：`protocolCException.status = "requires-execution-authorization"` →
  本文件即该显式授权；授权之外 B4 门槛不再阻塞 P09 配对。
- 关联判据：`GATE-LEDGER.md:296` 判据 3「Tiqian checks executed」的前置「B4 authorization + pair」中授权一半。
- 本文件不改变 P08/P09 任何其它状态；授权边界（一次执行、隔离树、留档）由执行席在 P09 日志中兑现。
