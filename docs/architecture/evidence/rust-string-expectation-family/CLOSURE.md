# host-String 陈旧期望家族（PIT-304）— 收尾记录

任务行 `t-munjfayf-iyh2`，分支 `fix/rust-string-expectation-family`（base = `05e375b2`，认领时的
`arch/agent-guided-governance` 行头）。完整报告与原始证据：`dc-warn/out/rust-string-expectations/`
（REPORT.md + evidence/，fuse 挂载，树外副本）。

## 判定

家族是**陈旧期望**，不是产品缺陷。判定锚（全部经 `git merge-base --is-ancestor <c> 05e375b2` 核真，
05e375b2 为 arch 行头，故**已生效于 base**）：

- `40cf0ad0` test(ts): refresh stale Rust string expectations across 13 files（57 ins/54 del：
  54 处替换 = 52 行 Rust-target 陈旧期望 + 2 行同提交 Swift 陈旧行；3 处纯新增守卫）；
- `9c9548ef` test(ts): unblock the array-root file's Rust assertions behind its stale Swift row；
- `d1180768` test(swift): make the read-only-boundary fixture able to observe branch selection。

本行对该家族**零新增改动**（独立验证 + 裁定，非重复修复）。UString 契约：`RustType.hx:176-179`
（Haxe String → UString 值 / &UStr 参数），spec 引文 `docs/specs/features/02-abstract-types.md:201`、
`docs/specs/stdlib/08-string-buffer.md:121-122`、`docs/specs/stdlib/06-std-modules.md:254`、
`reference/rust/gen/runtime/u_string.rs:2-4`。

## 独立测量（本行 worktree，本基状态；逐文件驱动因全量 bun OOM 于 RSS 10.95 GB）

- 54 文件基线唯一失败名 = 34（A 超时类 25 / B 断言红 7 / C 环境·flake 2）；**0 个属 String 家族**。
- 12 个家族名：11 个 after pass（实测）；第 12 个（record printed-member 的 mutation 配置用例）
  在本基仍 fail，原因是 120 s 预算 vs 8×haxe ≈190–240 s——预算类，期望行（`tests/ts/printed-record.test.ts:88`
  `pub fn to_string(&self) -> UString`）已修好且与再生成树逐字一致。该预算修复（420_000 等）是
  `fix/test-timeout-budget` 行（t-munga5l9-alq1）在 `fix/test-collection-ignore-out` 分支上的提交
  9905949e/36e7540e/e8a4c3bb/4c292c64——**分支态，未生效于 base**（`merge-base --is-ancestor`
  4 者对 arch 行头全为 false，已逐个核）。
- before/after 唯一失败名差集：NEW = ∅（after 复跑 5 名全部 ∈ before A 类；本行零测试改动，
  余 45 文件按零机制免跑）。
- B 类 7 名（loop-structure ×2、compiler-scope、sorted-dataclass、sorted-key-domains、
  arithmetic-helpers、package-shell）：本基既有红，ci 后代行（f1eb7498，05e375b2 直接后代）
  带 RustRuntime.hx/RustExpr.hx/TsDecl.hx 修复与对应测试更新；生成器输出两状态一致，非缺陷。

## 范围勘误（PIT-304 独立复现）

PIT-304 记 10 文件/≈57 行；独立扫法（覆盖 `String|&str|UStr|to_string|to_ustring` 多形态 +
声明的模式）命中 **13 文件/52 行 Rust-target 陈旧期望**。多出的 3 文件各带 1 行被原 grep 漏掉的
形态：`enum-queries.test.ts:54`（`&str` 参数）、`sealed-variants.test.ts:245`（`"…".to_string()`
返回）、`string-buffer.test.ts:47`（`String::from_utf16`）。57 行口径 = 52 Rust + 2 Swift 同提交 +
3 纯新增。

## 遗留（不归本行）

1. 120 s 类预算实测闭环在 `fix/test-timeout-budget` 行的 before/after 差集（本行不越界改预算）。
2. npm tgz 非确定 flake（byte-identity / npm-tarball 两用例）：timeout-budget 席已定位
   （`dc-warn/out/timeout-budget-fix/evidence/identity-inspect-all.*`），建议方向在该行通报。
3. 全量 bun OOM 未归因（逐文件驱动可完整覆盖 54 文件，不阻塞）。
