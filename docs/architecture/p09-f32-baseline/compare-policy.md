# P09 f32 baseline compare policy — PrintedFloatTests 6 条裁定（TCN-173 落地）

- 任务：`t-mup4nyxh-mlvw`（branch `prep/p09-f32-baseline-rebuild`）
- 日期：2026-10-01（America/Toronto）
- 性质：prep/口径裁定。未生成、未编译、未跑任何测试矩阵；`generationStarted=false`；不改旧 attempt、compiler、Tiqian、已签核基线，也不触碰 `boring-wt-architecture` 工作树里的未提交 `tests/ts/printed-collection.test.ts`。

## 0. candidate revision（先钉后包）

- candidate revision = `77c493b5644a3613f70067045f4596f52e346e6d`（worktree `boring-wt-architecture`，branch `ci/collected-suite-failure-attribution`，是 base `arch/agent-guided-governance` @ `0641991b` 的后代）。
- 所有哈希取自 `git archive 77c493b5…` 的干净导出（`/tmp/p09f32-clean-export`，只含 committed 内容）。该工作树存在的未提交改动 `tests/ts/printed-collection.test.ts`（+30/−4，TS 侧 printed collection 断言刷新）**不进入任何输入/哈希/报告数字**，本 prep 与它互不相干。
- identity 按 TCN-74 口径用逐文件 sha256（`SOURCE_MANIFEST.json`），目录名/compiler-pin 不作身份。

## 1. 裁定（唯一）：PrintedFloatTests 6 条 = 显式豁免（explicit-exemption）

豁免的 6 个 id（即组 B 全集）：

```
tests.f32.PrintedFloatTests.printsShortestFloatText
tests.f32.PrintedFloatTests.printsWholeNegativeAndNullFloatFields
tests.f32.PrintedFloatTests.printsNonFiniteFloatFields
tests.f32.PrintedFloatTests.printsComputedShortestTextOnNullableFields
tests.f32.PrintedFloatTests.printsNullableFloatCollectionForm
tests.f32.PrintedFloatTests.printsShortestFloatTextOnCollectionElements
```

裁定理由（每条可独立核验）：

1. **口径性缺口，非 candidate 回归**：这 6 条是 feature 44（record float text f32）的 f32 专属 oracle，只被 haxe-f32 的 TestCollector（`tests/haxe/generate-main-f32.hxml` 扫 `samples/tests/f32`）收集；三个目标 f32 hxml（kotlin/rust/swift-f32）的固定输入口径从未包含 `tests.f32.*`。任何 candidate 都不改变这一点（audit §组 B 已确认，本次在 `77c493b5` 干净导出上复核：`extra-id-allowlist.json` 恰好 6 条 `tests.f32.PrintedFloatTests.*`；hxml 中 0 命中 `tests.f32`）。
2. **"纳入"需要先做本任务非目标内的事**：纳入 = 把 `samples/tests/f32` 加进三个目标 roots 并验证 kotlin/rust/swift f32 下可编译可过。这需要真实生成+执行（本任务非目标：不启动矩阵），且 TCN-173 禁止在无法绑定 expected 的现状下把 compare 数字当验收。
3. **豁免有界、可撤销**：豁免绑定内容锚 `samples/tests/f32/PrintedFloatTests.hx` @ `77c493b5` 的 sha256（见 SOURCE_MANIFEST `printedFloatTests.contentAnchorSha256`）。撤销条件（写进 expected.json）：任一目标 f32 bundle 增加 `tests.f32` 收集 roots 时，本 baseline 失效，须重建后才可再作验收依据。

## 2. 新 compare 口径（唯一，替代旧 166 条口径用于验收）

- 参与比较的 f32 束：`haxe-f32`（reference）vs `kotlin-f32` / `rust-f32` / `swift-f32`（targets），来源 `boring.json`（inputs/ 内有副本）。
- 预期行数：haxe-f32 = 736（730 共享 + 6 f32 专属）；三个目标束 = 730。**6 条 f32 专属 id 在跨目标比较中按豁免单列，不计入 Extra，也不计入 Missing。**
- 旧 166 条口径（160 missing + 6 reference-only）保留为**诊断历史**，不再用于 P09 验收归因；组 A（160/60，arrfix 侧执行覆盖缺口、共同 id verdict 零翻转）事实陈述不变，但 arrfix manifest 无法重绑命名 revision 的开放项原样保留。
- P09 维持 **NOT PASSED**；本 prep 不改变任何 ledger verdict。

## 3. 静态检查记录（本轮实际执行）

1. 15 个目标/参考输入哈希一致：干净导出侧与 prep `inputs/` 副本侧逐文件 sha256 全等，15/15（`SOURCE_MANIFEST.json` 内逐条 `match:true`；清单 sha256 `9b91ffc99e3109289878f7fa9534e9302b8bc6b46882b80f1d5ea2323febb8f7`）。复现命令见 REPORT.md §4。
2. `tools/roots-guard/check-roots-guard.sh` 在候选 revision 上**为红（如实记录，不修饰）**：runtime.UString/GraphemeWalk/Graphemes/SortedTable/TestCore 五个 root-floor 模块在三个 base+f32 hxml 自声明的 classpath 上不可解析（模块实际在 `packages/compiler/runtime/`，hxml 未 `-cp packages/compiler`）；另有既存 unrooted 测试模块 FAIL（NullBoolTernaryTests、TestLitEdgeTests、swift 侧另缺 NullInflatedLiteralOpsTests）。对 base `0641991b` 的干净导出复测同为红（35 FAIL）——**红先于本任务存在**，本 prep 未改任何 hxml/守卫输入。该红与 f32 口径裁定无耦合（它不触及 tests.f32 判定），但它是"下一轮矩阵前须有人接的活"，已如实上报。
3. `generationStarted=false`：本 prep 无任何生成动作；无 `reference/*` 产物被创建或改动；expected 行数是口径推导值，不是测量值。
4. P09 NOT PASSED、166 条诊断历史、Tiqian gate（kotlin-f32/dart 冻结束 1342×3）未执行——三项均原样保留并写入 expected.json `carryOverFacts`。

## 4. 输入清单（15 项，全部有 inputs/ 版本化副本）

8 个 rootsFile hxml（kotlin/kotlin-f32/rust/rust-f32/swift/swift-f32/generate-main/generate-main-f32）、GenerateMain.hx、f32 oracle 源 `samples/tests/f32/PrintedFloatTests.hx`、`tools/test-consistency/extra-id-allowlist.json`、`tools/roots-guard/roots-allowlist.json`、`tools/roots-guard/check-roots-guard.sh`、`boring.json`（束/比较契约声明）、feature 44 spec。逐项哈希见 `SOURCE_MANIFEST.json`。
