# P09 f32 BASELINE REBUILD REPORT — prep only（preparable, NOT executed）

- 任务：`t-mup4nyxh-mlvw`（branch `prep/p09-f32-baseline-rebuild`，worktree `boring-wt-p09f32prep`，off `arch/agent-guided-governance` @ `0641991b`）
- 日期：2026-10-01（America/Toronto）
- 性质：baseline/prep 重建。**无生成、无编译、无矩阵**；`generationStarted=false`；不改旧 attempt、compiler、Tiqian、已签核基线；不触碰 `boring-wt-architecture` 的未提交 `tests/ts/printed-collection.test.ts`（该改动未进任何哈希或数字）。P09 维持 **NOT PASSED**，本报告不宣布 f32 绿。

## 1. candidate revision（先钉后包，TCN-173/TCN-74 口径）

- **candidate = `77c493b5644a3613f70067045f4596f52e346e6d`**（`boring-wt-architecture` @ branch `ci/collected-suite-failure-attribution`；为 base `arch/agent-guided-governance` @ `0641991b` 的后代，已核 `merge-base --is-ancestor`）。
- 打包方式：`git archive 77c493b5…` 干净导出（`/tmp/p09f32-clean-export`）。工作树当时有未提交 `tests/ts/printed-collection.test.ts`（+30/−4）——**刻意排除**，未污染任何输入。这与 PIT-354（工作树根生成用活源码）的教训一致：凡进入 baseline 的内容都来自 committed 导出，报告写明 commit。
- 内容锚为逐文件 sha256（`SOURCE_MANIFEST.json`），15/15 与 prep `inputs/` 副本一致。

## 2. PrintedFloatTests 6 条裁定：显式豁免（唯一裁定）

见 `compare-policy.md` §1。要点：6 条为 feature 44 f32 专属 oracle，仅 haxe-f32 TestCollector 收集；三目标 f32 hxml 固定口径从未含 `tests.f32.*`（在 `77c493b5` 导出上复核：`extra-id-allowlist.json` 恰 6 条，hxml 0 命中）。纳入需先做"目标侧收集+验证"，属矩阵后工作，非本任务授权；故按 TCN-173 作**显式豁免**，绑定内容锚 sha256，写明撤销条件（任一目标 f32 加 `tests.f32` roots 即失效须重建）。新口径：haxe-f32 = 736 行（730 共享+6 专属），三目标 = 730 行，6 条豁免单列，不计 Extra/Missing。

## 3. 交付物（本分支版本化，路径与哈希）

| 文件 | 内容 |
|---|---|
| `SOURCE_MANIFEST.json` | candidate revision 绑定 + 15 项输入逐文件 sha256（清单 sha256 `9b91ffc99e3109289878f7fa9534e9302b8bc6b46882b80f1d5ea2323febb8f7`）+ 6 条内容锚 |
| `expected.json` | 新口径 expected 行数、豁免 id、撤销条件、carry-over 事实（P09 NOT PASSED / 166 条历史 / Tiqian gate 未执行） |
| `compare-policy.md` | 裁定正文与静态检查记录 |
| `inputs/`（15 文件） | 8 个 rootsFile hxml、GenerateMain.hx、PrintedFloatTests.hx、extra-id-allowlist.json、roots-allowlist.json、check-roots-guard.sh、boring.json、feature-44 spec 的版本化副本 |
| `verify-prep.sh` | 静态验证脚本（本轮 rc=0 PASS） |

## 4. 复现（有 ref，逐条可重放）

```bash
CAND=77c493b5644a3613f70067045f4596f52e346e6d
git -C boring-wt-architecture archive $CAND | tar -x -C /tmp/repro-export
for f in $(python3 -c "import json;print(' '.join(e['path'] for e in json.load(open('docs/architecture/p09-f32-baseline/SOURCE_MANIFEST.json'))['sourceManifest']['entries']))"); do
  sha256sum "/tmp/repro-export/$f";   # 须与 SOURCE_MANIFEST.json 对应 candidateSha256 全等（15/15）
done
bash docs/architecture/p09-f32-baseline/verify-prep.sh   # rc=0
```

## 5. 静态检查结果（如实，含一条红色开放项）

1. **verify-prep PASS**：15/15 哈希一致、6/6 豁免绑定与 allowlist 全等、`generationStarted=false`（两处 JSON 字段）、carry-over 事实在位。脚本：`verify-prep.sh`（本轮 rc=0）。
2. **roots-guard 在候选 revision 上为红（先于本任务存在，不修饰）**：`tools/roots-guard/check-roots-guard.sh` 在 `77c493b5` 干净导出上 FAIL（50 条 FAIL）：`runtime.UString/GraphemeWalk/Graphemes/SortedTable/TestCore` 五个 root-floor 模块在 kotlin/rust/swift base+f32 六个 hxml 自声明的 classpath 上不可解析（模块实体在 `packages/compiler/runtime/`，hxml 未声明 `-cp packages/compiler`）；另有既存 unrooted FAIL（`tests.NullBoolTernaryTests`、`tests.TestLitEdgeTests`，swift 侧再加 `tests.NullInflatedLiteralOpsTests`）。base `0641991b` 干净导出复测同为红（35 FAIL）→ 红不是本 prep 引入。本红不触及 tests.f32 豁免判定（该 id 集由 extra-id-allowlist 单独声明），但**任何后续矩阵启动前须有人接这个活**。
3. **generationStarted=false**：无任何生成执行；`reference/*` 未被动过；expected 行数是口径推导值，非测量值。
4. **carry-over 事实原样保留**：166 条（160 missing + 6 reference-only）为诊断历史；组 A（60 id、共同 id verdict 零翻转）仍只能算"未证明"；arrfix manifest 不可重绑开放项保留；**Tiqian gate（kotlin-f32/dart 冻结束 1342×3）未执行**，在矩阵前仍必须补跑。

## 6. 未做 / 非目标

未启动 full matrix；未改 `examples/*.hxml` 或任何守卫输入；未覆盖旧 evidence（新清单写独立目录）；未给任何 P09 归因结论开绿灯。
