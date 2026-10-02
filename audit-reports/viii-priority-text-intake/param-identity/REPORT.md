# 核查报告：比较分析的泛型参数所属声明身份（独立复核）

- 任务：t-mulxx76r-apv6「核查比较分析的泛型参数所属声明身份」，分支 audit/dc-parameter-identity
- 基线：dc-warn/worktrees/param-identity @ e1c65975；Haxe 4.3.7（rev1/env-check.log 实测）
- 方式：全部探针从零重建（自有 fixture、自有 hxml），一律调用**真实的**
  `SourceComparisonAnalysis`（非函数副本）；未改动任何共享代码
  （`packages/compiler/SourceComparisonAnalysis.hx` 与 boring-wt-architecture 副本逐字节一致，开工前已验证）；
  未 commit/push/merge；四路候选未触碰。
- 探针源码：worktree 内 `out/rev-param-identity/`（gitignored；27 个文件，见同目录
  `PATCH.diff` 与 `FILES.sha256`；11 条 rclone mode-only `M` 记录已从两者中剔除）。
- 原始输出证据：`rev1/probe1-raw.log`、`rev1/probe2-raw.log`、`rev1/probe3-raw.log`、
  `rev1/admission-tests.log`、`rev1/plan-tests.log`（全部 exit=0 记录在案）。

## ① 原证据重述与复现状态

### 原主张 1（宏探针：parameterIdentity 键含 owner 路径）
原证据：`parameterIdentity` 键含类型参数 ClassType 的 owner 声明路径；同模块
`HolderOne<T>`/`HolderTwo<T>` 不撞；`ownParameterSlot` 正/负控 = 0/null。
**复现：复现并加强。** 探针 1（probe1-raw.log）直接调用真实
`parameterIdentity` / `ownParameterSlot` / `schemaParameterIndex` /
`analyzeRecordSchema` / `comparisonPlan`，覆盖 7 个参数输入
（`revp1.One.T`、`Two.T`、`Alpha.T`、`Beta.U`、`Swap.A/B`、跨模块 `revp1.sub.SubHolder.T`）
加匿名字段：
- 参数 ClassType 的 `pack` 与 `module` 均为 owner 全名（例：
  `One.T: pack=[revp1.One] module=revp1.One name=T`）→ 键 = `revp1.One|revp1.One|T`，
  owner 身份内嵌于键；
- 全部碰撞检查为 false（同包不同 owner 同名 / 异名 / 同 owner 异名 / 跨模块）；
- `ownParameterSlot` 正控 0（`Swap.B→1`）、负控 null（`Two.T vs One` owner、`Alpha.T vs One`）；
  `schemaParameterIndex(Two.T, [One.T]) => null`；
- 匿名 `TAnonymous` → 键 null、槽 null（安全）；
- 真实 schema 路径：`One` → `left:ParameterOrder(0)` complete；`Swap` → `ParameterOrder(0)/1`。

→ 参数身份缺陷假设（不同 owner 同名参数键碰撞 → 槽位串用）被反驳：**缺陷不存在**。

### 原主张 2（真实调用探针：Ref 每次全新、计划 ready）
原证据：`declarationReference`/`analyzeRecord` 每次获得新分配的 Ref（ref1==ref2:false），
两节点 comparisonPlan 均 ready。
**复现：复现并加强。** 探针 2（probe2-raw.log）：
- A：`ref1==ref2 (Ref): false`，且 **`ref1.get()==ref2.get() (ClassType): false`** ——
  本宿主下 ClassType 对象本身也不稳定（比原报告更强）；
- A2：参数对象 `tG1!=tG2`、`ref(tG1)!=ref(tG2)`；
- B：跨 fresh refs 的 `analyzeRecord` 去重各自成节点（指针独立），两计划均 ready；
- F：`admit` 全部正确（`Generic<Int>` Admitted；binder 实参 SortedKey Admitted；
  binder 实参 OptionalEq Rejected(`ParameterWithoutEqualityEvidence(0)`) —— 正确；
  递归 `Loop` Admitted，visitedDeclarations=1 有界闭合）；
- G：schema 路径稳健（`value:ParameterOrder(0)`、`child:NullBeforePresent(RecordOrder…)`、
  `pair:RecordOrder…`）。
- **新发现 C（非缺陷）**：`analyzeRecord(decl, [binderArg])` →
  `ComparisonPlanFailed(value, unsupported resolved source shape, TInst(…T,[]))`。
  已查明为设计使然：非 schema record 路径 L289 以 `shape(instantiated)`（无 binderOwner）
  计算字段形，`terminalShape`（L331-335）仅在 `binderOwner != null`（即 schema 模式）
  才走 `ownParameterSlot`/`ParameterShape`；非 schema 模式下参数类型字段 →
  `UnsupportedShape`。原探针 F 用具体 `Int` 实参，故未触及此路径。符号实参是
  `TsDecl.selectComparator`（L235，传 `cls.params` 自身）的既有设计行为，与身份无关。

### 原主张 3（sameTypeParameter 未被公共 record/schema/admit 路径触达，仅防御建议）
**反驳。** 见 ④ 最小反例：真实公共 `analyzeRecord` 调用可达
`Builder.sameTypeParameter`（L434，Ref 指针相等），且对同一逻辑参数返回 false。

## ② 探针源码与命令

探针根：worktree `out/rev-param-identity/`（三个探针，fixture 均为新写的 `@:dataClass` 类）：
1. `identity/`（包 revp1）：fixture `One<T>{left:T}`、`Two<T>`、`Alpha<T>`、`Beta<U>`、
   `Swap<A,B>{first;second}`、`AnonField<T>{anon:{value:T}}`+`AnonPlain`、
   `sub/SubHolder<T>`；`probe/revp1/RevIdentity.hx` 调真实
   `parameterIdentity/ownParameterSlot/schemaParameterIndex/analyzeRecordSchema/comparisonPlan`
   并打印原始 ClassType 事实（pack/module/name/kind）。
2. `callsite/`（包 revp2）：fixture `Point`、`Wrapper`、`Pair<S>{s:S}`、
   `Generic<T>{value:T; child:Null<Pair<T>>; pair:Pair<T>}`、`Loop`（自递归）；
   `probe/revp2/RevCallSite.hx` 覆盖 A/A2（fresh refs 指针与 ClassType 身份）、
   B（analyzeRecord 去重+双计划）、C（binder 实参 → 设计性 Failed）、
   C2（`TypeTools.applyTypeParameters` 实参身份：arg!=tG、ref(arg)!=ref(tG)、**键相等**）、
   D（Wrapper 计划）、E（递归 Loop fresh refs）、F（admit 五例）、G（schema 计划）、
   H（可达性事实）。
3. `compiled/`（包 revp3，本次复核新增，回答“已编译类是否同样不稳”）：fixture
   `Point/Pair/Generic/Boxed<T>{child:Null<Pair<T>>; pair:Pair<T>}` + `Trigger`
   （引用前三者，强制其先于探针被编译）；`probe/Setup.hx` 经
   `Compiler.addGlobalMetadata("", "@:build(BuildProbe.run())", true, true)`
   注册全局 build 宏（与 `packages/compiler/Intercept.hx` L155 同一机制；
   Haxe 4.3.7 的 `@:build` 直接注解形式在包内引用不可解析，故采用仓库既有模式）；
   `BuildProbe` 以 `macro static function run():Array<Field>` 返回
   `Context.getBuildFields()`，守卫到 revp3.Trigger 后执行 P1-P6。

统一命令（自 `dc-warn/` 执行，输出与退出码分文件记录）：
```
XDG_CACHE_HOME=$PWD/out/nix-cache timeout 1800 \
  nix develop /home/losses/Development/tq-workspace/dc-warn/worktrees/param-identity \
  -c bash -lc 'haxe <绝对路径>/<探针>/build.hxml' > rev1/probeN-raw.log 2>&1; \
echo "exit=$?" | tee -a rev1/probeN-raw.log
```
（nix devShell 提供 Haxe 4.3.7；shellHook 的 “Git tree … is dirty” 为 rclone
mode-only 噪声，已确认 0 内容变更，`git diff --summary` 全为 mode change。）

**已有比较测试**（任务验收项）：
- `tests/haxe/comparison-source-admission/run.sh`（`IN_NIX_SHELL=1`，经 nix develop）：
  **exit 0**（admission-probe / expected-results / excluded-inputs 全 0；
  运行树 out/comparison-source-admission/run-5lmRQBkp）。
- `tests/haxe/comparison-plan/run.sh`：exit 1，**失败为环境限制而非代码问题**：
  swiftc 阶段 `bwrap: setting up uid map: Permission denied`（本容器沙箱无法建
  uid map），其后 12 个阶段级联 not-reached；Haxe 侧阶段全部通过：
  `macro-probe` normal-exit/0 且 observed==expected（14 行，含泛型参数用例
  `ComparedParameter`/`NestedParameter`/`NullableParameter`/`SequenceParameter`、
  `nested-binder-owner-and-operation`、`finite-box-nesting`、`finite-argument-permutation`），
  `gen-swift` normal-exit/0（status.tsv + 运行树
  out/a3-comparison-plan/runs/run-dsyQaGVA，rev1/plan-tests.log）。

## ③ 三级判定

**原结论成立（参数所属声明身份缺陷不存在，该点无须修复）——但原证据的一条事实前提被反驳，
防御性建议须从“不可达”改判为“可达、低严重度”。**

1. 原缺陷假设（`parameterIdentity` 键不含 owner → 同包不同 owner 同名参数碰撞 → 槽位串用）
   **不存在**：探针 1 以真实函数与 7 个输入+匿名对照反驳；schema/admit 两路按串键解析，
   实测正确（`ParameterOrder(0)`、admit 五例全对）。**“无须修复”在该点成立。**
2. 原时间线 seq3 的断言“`sameTypeParameter` 的 Ref== 当前未被公共 record/schema/admit
   路径触达”**被真实公共路径调用反驳**（探针 3 P4/P5/P6、探针 2 C2）：
   `Builder.sameTypeParameter`（L434）可由真实 `analyzeRecord` 调用触达，
   对同一逻辑参数（fresh Refs）返回 false → 产生重复嵌套记录节点。
   这不改变主缺陷判定（无槽位串用、无错误比较结果：重复节点均 Complete 且语义等价，
   admit 路为全名基、schema 路忽略实参，均不受影响——实测），
   但使“不可达”论断失效，并暴露一条**潜在**风险（见下）。
3. 不是“证据不足”：三条主张均已实测定性。

## ④ 最小反例（sameTypeParameter 可达性）与四路候选影响

### 最小反例（真实公共调用，e1c65975，Haxe 4.3.7）
```haxe
@:dataClass class Pair<S> { public final s:S; /* … */ }
@:dataClass class Boxed<T> {
    public final child:Null<Pair<T>>;
    public final pair:Pair<T>;
    /* 两个同形嵌套泛型字段共享同一类型参数，无裸 T 字段 */
}
final boxedRef = SourceComparisonAnalysis.declarationReference(clsOf("revp3.Boxed"));
final node = SourceComparisonAnalysis.analyzeRecord(boxedRef, [boxedRef.get().params[0].t]);
```
实测（probe3-raw.log）：
- **P4**：`child`/`pair` 两字段的嵌套 Pair 记录节点**不是同一对象**（`dedup ok: false`）——
  `record()` 去重检查（L275）`sameArguments` → `sameType` → `sameClassDeclaration` →
  `sameTypeParameter`（L434 `return left == right;`）收到同一逻辑 T 的两个 fresh Ref，
  返回 false → 建第二节点。两节点均 Complete、fields=1、形一致（语义正确，仅重复）。
- **P1/P2**（机制）：已编译类同样 `ref1==ref2:false` 且 `ref1.get()==ref2.get():false`；
  参数对象跨 fresh refs 不同（tG1!=tG2、Ref 不同）。
- **P3**（机制，关键）：同一个已编译 ClassType 内，字段类型 T 与 `params[0].t`
  即**非同一对象**（`value field type == tG1: false`，Ref 亦不同）；
  `TypeTools.applyTypeParameters(T, [tG1])` 产物再是另一 fresh 对象（键相同）。
  → 嵌套 record 调用按字段各得一份 fresh 参数 TInst，Ref 指针相等在结构上不可靠。
- **P6（对照）**：具体 `Int` 实参 → 嵌套节点去重成功（`dedup: true`）、计划 READY
  —— 证明参数分支是判别因素，非宿主随机性。
- **P5（可观测差异）**：公共参数 `maxRecordNodes=2` 下
  `analyzeRecord(boxedRef, [tB], 2)` → `pair` 字段的嵌套节点
  `AnalysisUnresolved("comparison graph exceeded the requested analysis work limit")`
  （正确去重时逻辑图仅 Boxed+Pair=2 节点，不超限，该节点应为 Complete）；
  计划级结果两种情形相同（`Failed at child.s`，非 schema 模式参数字段的设计行为）。
  现有生产调用**无人传** `maxRecordNodes`（全包 grep 0 命中）→ 预算消耗为**潜在**风险。

### 四路候选影响（真实调用点 grep 结论）
| 候选 | 驱动 API | 是否触达 sameTypeParameter 假分支 | 影响 |
|---|---|---|---|
| Swift | `SwiftComparisonPlan.select` → `analyzeRecord(declaration, applied)`（SwiftType.hx:338 具体 applied） | 仅当外层泛型语境（applied 含外层类型参数，如 `Outer<S>` 字段 `g:Generic<S>`）且 ≥2 个同形嵌套泛型字段 | 重复节点（重复分析/内存），无错误操作；`selectSchema` 不受影响 |
| TS | `TsDecl.selectComparator` → `analyzeRecord(declaration, [自身 params])` | 是（符号实参 + 同形嵌套字段） | 重复节点；参数类型字段的 `ComparisonPlanFailed`→`Context.error` 为既有设计行为，与身份无关 |
| Kotlin | `KotlinDecl`：`admit` + `analyzeRecordSchema` | 否（admit 全名基；schema 忽略实参） | 无 |
| Dart | `DartComparisonPlan`：仅 `analyzeRecordSchema` | 否 | 无 |
| （Rust，第五目标备查） | `RustDecl`：`admit` + `analyzeRecordSchema` | 否 | 无 |

### 若需修复（本复核不改共享代码，仅给出最小方向）
将 `sameTypeParameter`（L434）由 Ref 指针相等改为 `parameterIdentity` 串键比较
（或同 `sameBaseDeclaration` 式全名比较）即可令跨 fresh Ref 的去重成立；
串键已被探针 1 证明 owner-唯一，无串槽风险。是否修由队长/执行席决定（如修，应另建
修复任务并附五目标回归）。

## ⑤ 不确定性
1. **宿主依赖**：Ref/ClassType 不稳定性全部实测于 Haxe 4.3.7 宏上下文（懒加载与已编译
   两种类表示均覆盖——探针 3 专门覆盖已编译）；其他 Haxe 版本/宿主未验证。若生产宿主
   下同一逻辑参数恰为共享对象（稳定），sameTypeParameter 假分支不触发；该情形无法在
   本环境完全排除（生产 reflaxe 管道宿主不可复现），但主缺陷结论（串键身份）不依赖此点。
2. **swiftc 环境限制**：comparison-plan 套件的 Swift 原生编译/运行阶段因
   `bwrap: setting up uid map: Permission denied` 未执行；Haxe 侧（macro-probe +
   gen-swift）已通过。本次未做 Swift 运行时全量观测。
3. **重复节点开销未量化**：未跑基准；`maxRecordNodes` 预算消耗路径当前无生产调用方，属潜在。
4. **rclone fuse 瞬断**：工作期间证据目录曾出现一次 EIO/大小写条目混乱（一个 scratch 目录
   卡死，已弃用并改用新目录）；全部证据文件已重读校验（行数/字节数见
   `ls -la rev1/`）。
5. **Haxe 4.3.7 行为细节**：`@:build` 直接注解形式对非 haxelib 包引用不可解析
   （`Unexpected <name>`，多次复现），仓库既有 `Compiler.addGlobalMetadata`
   全局元数据模式可用——此为工具链事实，不影响被测代码结论。

## 证据索引
- `rev1/env-check.log`（Haxe 4.3.7）、`rev1/probe1-raw.log`、`rev1/probe2-raw.log`、
  `rev1/probe3-raw.log`、`rev1/admission-tests.log`、`rev1/plan-tests.log`
- worktree 运行树：`out/comparison-source-admission/run-5lmRQBkp`、
  `out/a3-comparison-plan/runs/run-dsyQaGVA`
- 探针源码 27 文件：`PATCH.diff`（新增文件统一 diff）、`FILES.sha256`
- 共享代码零改动；mode-only 11 条（rclone）已自 PATCH/哈希中剔除；无 commit/push/merge
