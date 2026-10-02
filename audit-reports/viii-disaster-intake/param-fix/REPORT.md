# 修复报告：Builder.sameTypeParameter 的 Ref 指针比较导致重复嵌套节点

- 任务 t-mun3p3km-rbvc，分支 fix/comparison-same-type-parameter-key
- 基线 e1c65975；工作树 `dc-warn/worktrees/param-fix`（detached @ e1c65975）；Haxe 4.3.7（nix devShell）
- 交付：隔离树改动 + `PATCH.diff` + `FILES.sha256` + 本报告；未 commit/push/merge；未自审未签收
- 夹具（可重复运行，无执行位 → `bash tests/haxe/dc-same-type-parameter/run.sh <logdir>`）：
  `tests/haxe/dc-same-type-parameter/`（fixture revp9 Pair/Generic/Boxed/Trigger + 全局
  @:build 宏探针 DedupProbe + run.sh 判定器，9 文件见 FILES.sha256）

## ① 缺陷复现（修复前，本树原始证据 `baseline-pre/probe.stdout`，haxe exit=0）

宿主 = 已编译类形态（revp9.Trigger 先编译，全局 build 宏在 Trigger 上运行），
`analyzeRecord(boxedRef, [boxedRef.get().params[0].t])`：
- `DEDUP ok:false` —— child/pair 两字段的嵌套 Pair 节点为两个不同对象（均 Complete fields=1）；
- `LIMITED allNestedComplete:false`：`maxRecordNodes=2` 时 pair 嵌套节点
  `AnalysisUnresolved(comparison graph exceeded the requested analysis work limit)`，child 仍 Complete；
- 对照 `CONTROL concrete dedup:true`（具体 Int 实参去重正常）——判别因素是参数分支，非宿主随机。
与参考探针（param-identity probe3）结论一致，在本树独立复现。

## ② 改动点与理由

只改 `packages/compiler/SourceComparisonAnalysis.hx` 的 `Builder.sameTypeParameter`（+11/-3 行，
PATCH.diff 唯一文件；fuse 的 11 条 mode-only 记录未进入 PATCH.diff，已用 `git diff --summary`
确认全部为 mode change 且内容 0 字节）。

- 修复前函数文本 sha256：`fn-pre.sha256`（7f26ca56…）；文件级 sha256：`5ef4269e…`（pre-source.sha256）
- 修复后函数文本 sha256：`fn-post.sha256`；文件级 sha256：`5fffdf21…`（post-source.sha256）
- 新口径：`left == right` 短路后，取 `SourceComparisonAnalysis.parameterIdentity(TInst(ref, []))`
  串键比较；任一键为 null → false。未新增 helper（`parameterIdentity` 为同文件公共静态，
  Builder 为其同文件私有消费者）。
- 无串槽风险：键 = `pack|module|name`（owner 全名内嵌，探针 1 已实测 owner-唯一：
  同包不同 owner 同名/异名/同 owner 异名/跨模块碰撞全 false；匿名 → null → 判 false，安全）。
  不同 owner 的同名参数键必不同，故串键比较不可能把 A 声明的 T 配到 B 声明的 T。
- 未改去重算法、未改 `parameterIdentity`、未动 maxRecordNodes 默认值。

## ③ 修复后（`post-fix/probe.stdout`，haxe exit=0；`post-fix-runsh/` run.sh 端到端 PASS exit=0）

同输入：`DEDUP ok:true`，child/pair 为同一节点、`Complete fields=1`；
`maxRecordNodes=2`：两嵌套节点均 `Complete`（`LIMITED allNestedComplete:true`）；
对照 `CONTROL concrete dedup:true` 保持。

## ④ 不回归证据（`regression/`）

- comparison-source-admission：`bash run.sh` **exit 0**（admission-probe 0 / expected-results 0 /
  excluded-inputs 0；运行树 out/comparison-source-admission/run-krjbxEqN；argv=nix develop -c bash <run.sh>，
  见 admission-exit.txt / admission.stdout / admission.stderr）。
- comparison-plan：exit 1，失败为环境限制：swiftc 阶段 `bwrap: setting up uid map: Permission denied`
  （运行树 out/a3-comparison-plan/runs/run-KfwNUtLJ/stages/swiftc-library/child-stderr.bin 实录），
  其后 13 个阶段级联 not-reached —— **明确标注"未到达"，未伪造**。Haxe 侧全部通过：
  status.tsv 中 `macro-probe zero normal-exit/0` 与 `gen-swift zero normal-exit/0`
  （即宏探针观测==期望，含泛型参数/嵌套/有限嵌套盒用例）。

## ⑤ 负控（`negative-control/`）

把 `sameTypeParameter` 临时改回 `return left == right;`（其余不变）重跑同一夹具：
`DEDUP ok:false` 且 `pair … AnalysisUnresolved`（haxe exit=0，判定器判 FAIL 成立）→
检查能抓住回退；随后已从备份恢复修复版本（diff 校验 "restored ok"）。

## ⑥ 不确定项

1. swiftc 原生阶段因容器沙箱 bwrap 限制未到达（同既往 audit 结论），Swift 运行时行为未全量观测；
   但本修复不触及 Swift/Kotlin/Dart 消费路径（admit 全名基、schema 忽略实参），且 Swift/TS 的
   analyzeRecord 路径正是受益方（重复节点消除）。
2. 串键口径只覆盖参数分支：sameClassDeclaration 对非参数仍走 sameBaseIdentity；
   sameTypeParameter 仅在双方均为 KTypeParameter 时被调用（L417-418）。
3. `parameterIdentity(TInst(ref, []))` 要求空 arguments；若未来出现带实参的参数 Ref（现不存在），
   键为 null → 判 false（保守回退，不误合并）。
4. 宿主依赖同参考报告：全部实测于 Haxe 4.3.7 宏上下文；若生产宿主参数 Ref 稳定，本修复等价无副作用。

## 证据索引

- baseline-pre/（修复前 stdout/stderr + exit）、post-fix/、post-fix-runsh/、negative-control/、regression/
- pre-source.sha256 / post-source.sha256 / fn-pre.sha256 / fn-post.sha256
- PATCH.diff（内容唯一文件 SourceComparisonAnalysis.hx，+11/-3）、FILES.sha256（夹具 9 文件）
