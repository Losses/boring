# 架构治理裁定：构建期诊断（swiftc 的 will-never-be-executed）是否属验收口径

> **状态与来源（协调者补注，2026-09-30）**
> 本文由 `t-muo92xms-s28t` 的执行席在 `gate/build-phase-diagnostic-standard` 分支上产出
> （提交 `3e2e7cde`），现由协调者取入 base 存档，**正文逐字节未改**。
> 它是**技术裁定记录**，不是管理层裁定；两者在本仓库的存档位置与效力不同
> （管理层裁定为 `docs/architecture/MANAGEMENT-RULING-NNN.md`）。
>
> 协调者**独立复现了本文的两条承重论断**，未采信其叙述：
> ① `02-translator-implementation-standard.md:78/:80` 的原文逐字引述准确；
> ② S1（`cd70eb12`）确实含 `stmtDiverges`（`grep -c stmtDiverges` = 9，两文件 +90/−9），
>    且诊断计数确为 1 → 0：须以 `^<path>.swift:<line>:<col>: (warning|error):` **形状**计数，
>    **不可用 `grep -c 'warning:'`**（插入符上下文行会把 1 条数成 2 条）。
>    `baseline-build.stderr.log` = 1 条（`gen/gap/Gap.swift:117:9: warning: will never be executed`）、
>    `after-build.stderr.log` = 0 条；两态产物均为 278824 B。
>
> **尚未主张**：本裁定对 P08/S1 验收口径的效力须经管理层确认后才算定案；在获得该确认前，
> 下游不得据本文改变 P08 状态（维持 NOT PASSED / REJECTED，最终）或提名 S1。
> 相关记录见 `GATE-LEDGER.md` 的 delivery integrity 与 build-phase diagnostic 两节。

- **任务编号**：`t-muo92xms-s28t`
- **裁定日期**：2026-09-30
- **工作分支**：`gate/build-phase-diagnostic-standard`（基线 `5a8f19e6`）
- **涉及文档**：
  - [02-translator-implementation-standard.md](file:///home/losses/Development/tq-workspace/boring-wt-builddiag/docs/specs/style/02-translator-implementation-standard.md)
  - [architecture-work-plan.md](file:///home/losses/Development/tq-workspace/boring-wt-builddiag/docs/architecture-work-plan.md)
  - [tests/swift-gap-boundary/gap-boundary.test.ts](file:///home/losses/Development/tq-workspace/boring-wt-builddiag/tests/swift-gap-boundary/gap-boundary.test.ts)
  - [MANAGEMENT-RULING-245.md](file:///home/losses/Development/tq-workspace/boring-wt-builddiag/docs/architecture/MANAGEMENT-RULING-245.md)

---

## 1. 结论摘要 (Executive Summary)

1. **口径归属裁定**：Swift **构建期诊断**（包括 `swiftc -c -whole-module-optimization` 与 `swiftc -o` 阶段由 SILGen / 流程分析报出的 `will never be executed` 等 warning）**在应然层面与既有管理判例中均确属 `02-translator-implementation-standard.md:78/:80` 的验收口径**。
2. **规范文本性质**：现行 `02-translator-implementation-standard.md:78` 的字面措辞对"构建期"处于**未定义（沉默 / 措辞存在内在张力）**状态。文本一方面以全称性总纲要求 "Generated code compiles without warnings on every target"，另一方面在枚举各目标校验工具时写为 "the Swift type-checker"。这一时机窄化属于**起草疏漏**（将前端静态检查工具指代与目标完整编译口径混淆），而非有意豁免构建期诊断。
3. **可失败性论证**：若将构建期诊断排除在外，则 Swift 目标的"零警告"判据将退化为**空判据（Decorative / Non-falsifiable Criterion）**——真实生成质量缺陷（死代码、未初始化、SIL 降级缺陷）均在前端语义检查后被隐藏，而下游实际编译二进制的消费者与 CI 却会遭遇构建警告甚至中断。
4. **源中不可达语句的责任归属**：Haxe 源中已存在但 Haxe 4.3.7 不告警的不可达语句，生成器机械发射到 Swift 导致 Swift 编译器告警，属于**目标发射器缺陷（Emitter Defect）**。严禁修改 Haxe 源来规避告警（违背 `:92`）。在修复落地前，依照 `work-plan:415`，该现象只能作为**已记录且未豁免的基线缺陷（Recorded, Unwaived Baseline Failure）**留存，绝不能被解释为合规。
5. **下游候选后果**：
   - 已封存候选 `c8ae0054` 维持 **P08 NOT PASSED / REJECTED** 裁定，不得翻案或追溯修改。
   - S1 候选材料（`cd70eb12`）在 `SwiftExpr.hx` 中引入局部发散判定 `stmtDiverges`，在发射端剔除发散后的死语句，已在根源上使 `swiftc -c -whole-module-optimization` 下的诊断数归零，是符合规范导向的根本修复。

---

## 2. 规范原文逐字引用（带行号）

### 2.1 `docs/specs/style/02-translator-implementation-standard.md`

#### 第 76–88 行：### Acceptance
> 76: ### Acceptance
> 77: 
> 78: 1. Generated code compiles without warnings on every target: kotlinc, rustc, the TypeScript compiler, the Dart analyzer, and the Swift type-checker. A translation that produces a warning is an emitter defect with the same severity as a translation that produces wrong output.
> 79: 2. Warning suppression markers are banned in generated trees: no `@Suppress` or `@SuppressWarnings` (Kotlin), no `#[allow]` (Rust), no `@ts-ignore`, `@ts-expect-error`, or `eslint-disable` marker (TypeScript), no `// ignore:` comment (Dart). The emitter produces code that does not warn.
> 80: 3. Acceptance for any emitter change counts the warning lines in the target suite output that name files under the generated trees; the count is zero. A change that replaces a warning with a suppression marker fails acceptance.
> 81: 4. Cross-target behavior is checked by `bun run test:consistency`: it compares
> 82:    recorded outcomes from the shared test set on six runners (Haxe, TypeScript,
> 83:    Kotlin, Rust, Swift, Dart) and requires equal results. Obtain those records
> 84:    from fresh generation and test execution before comparison. Consistency
> 85:    verifies the covered tests; divergences outside the covered tests are found
> 86:    by the Step 0 comparison of the consolidation procedure, which is why Step 0
> 87:    reads every copy before any editing.
> 88: 

#### 第 60–63 行：Exception ledger
> 60: 5. **Separate mechanisms.** When Step 0 returns verdict (iii) and the owner keeps both behaviors, the targets keep two independent mechanisms with their own names. Presenting them as one shared mechanism with a hidden branch is banned.
> 61: 
> 62: **Exception ledger (ruled; implementation pending).** Every standing exception registers at compile time in a `SemanticException` registry with an identifier, the mechanism, the target, the reason, and the fixture that verifies it. The registration rule rejects missing, duplicate, and unknown identifiers. The continuous-integration artifact `out/semantic-pass-exceptions.json` carries the exception count and its delta against a baseline; an increase requires a new fixture and an owner ruling. A count that keeps growing is the signal that the abstraction boundary sits in the wrong place.
> 63: 

#### 第 89–94 行：## Fix location
> 89: ## Fix location
> 90: 
> 91: 1. A defect in translated output is fixed in the translator: the target printer (`packages/compiler/reflaxe/<target>/**`) for rendering defects, the shared layer (`packages/compiler/`) for mechanism defects.
> 92: 2. Editing `samples/` or `tests/` Haxe source to make a translation defect disappear is banned. The single exception is a Haxe semantic the target language cannot carry; in that case the change record names the semantic and states why the common layer cannot express it.
> 93: 3. Generated trees are gitignored build artifacts. They are regenerated, hashed, and compared during acceptance; they are never committed and never edited by hand to satisfy a check.
> 94: 

---

### 2.2 `docs/architecture-work-plan.md`

#### 第 415–419 行：
> 415: Generated-code warnings and suppression markers are acceptance failures under
> 416: the current standard. Record any baseline failure separately, including its
> 417: revision and reproduction; a baseline finding does not waive the standard.
> 418: Cross-target agreement supplements assertions against the specified semantics.
> 419: 

---

## 3. 文档措辞的字面判定：未定义（沉默 / 存在内在张力）

基于文本用词做纯文义判定：

1. **未明确包含**：
   `:78` 在具名枚举各目标工具时，明确使用了 `"the Swift type-checker"`，而不是 `"the Swift compiler"` 或 `"swiftc -c / swiftc -o"`；且全文未出现关于 SILGen、构建期代码生成或可达性分析的具体说明。
2. **未明确排除**：
   `:78` 首句总纲为全称命题：`"Generated code compiles without warnings on every target"`（生成的代码在每个目标上编译均无告警）；第二句规定：`"A translation that produces a warning is an emitter defect with the same severity as a translation that produces wrong output"`（产生告警的翻译是发射器缺陷，其严重程度等同于产生错误输出）。
   `:80` 给出的计数算式为：`"the warning lines in the target suite output that name files under the generated trees; the count is zero"`。这里是以目标套件执行输出中的告警行进行全量计数，并没有排除构建期输出的免责条款。
3. **结论**：
   文档措辞对于"仅在构建期出现而在类型检查期不出现的诊断"属于**未定义（沉默）**，呈现出**总纲意图的全称性要求**与**工具枚举的具体用词窄化**之间的规范缝隙。

---

## 4. 三类诊断的观测时机与时机窄化的性质判定

### 4.1 观测时机区分

| 观测时机 | 对应命令与阶段 | 诊断覆盖范围 | 本案诊断表现（`Gap.swift:117`） |
|---|---|---|---|
| **类型检查期** | `swiftc -typecheck`（Swift AST 解析与语义分析 Sema） | 语法错误、类型不匹配、协议未满足、符号未解析等前端约束。**不运行 SIL 阶段**。 | **完全不可见（0 告警）**。因为 `return ReadOnlyArray(...)` 语法合法且类型完全匹配方法返回类型。 |
| **构建期** | `swiftc -c -whole-module-optimization` / `swiftc -o`（SILGen、Mandatory Diagnostic Passes、LLVM IR 及目标码生成） | 确定性初始化（Definite Initialization）、可达性/死代码分析（Control Flow Unreachable Code Elimination）、内存流安全等。 | **必定触发（恰好 1 条告警）**：`Gap.swift:117:9: warning: will never be executed`。SILGen 在分析发散的 switch 后发现紧随其后的 return 永远无法到达。 |
| **运行期** | 编译后的可执行产物运行（`./runtests` 或 `bun run test:consistency`） | 语义正确性、退出码、断言输出等，无编译器静态诊断。 | 运行结果与 Haxe JS oracle **逐字节一致**，运行期无法感知该不可达语句的存在。 |

### 4.2 为什么工具列表写为 "the Swift type-checker"：有意还是疏漏？

判定：**起草疏漏（Drafting Oversight）**。

**依据如下**：
1. **多目标枚举的对齐惯例**：
   在 `:78` 列举的工具中：
   - TypeScript 写作 `"the TypeScript compiler"`（日常主要是 `tsc --noEmit` 做类型检查，运行时由 Node/Bun 承担）；
   - Dart 写作 `"the Dart analyzer"`（即 `dart analyze` 静态分析器，而非 Dart AOT 编译器）；
   - Swift 顺理成章地被撰写者写成了 `"the Swift type-checker"`（即对标前端静态检查）。
   撰写者在起草该规则时，直觉上是将各后端的"前端静态验证门禁"并列，误以为 `swiftc -typecheck` 已经囊括了 Swift 的所有静态诊断。
2. **总纲全称与目的解释的矛盾**：
   `:78` 开宗明义写的是 `"Generated code compiles without warnings on every target"`（编译无告警），而不是 `"passes type checking"`。若撰写者是有意排除构建期诊断，其必在后文阐述排除理由（例如"由于 Swift 构建耗时较长，CI 验收仅执行类型检查"）。但规范全文毫无此类说明，反而在 `:80` 中以套件输出中指向生成树文件的警告行为准。
3. **下游实际消费场景的强约束**：
   生成代码的下游消费者（如 Tiqian 引擎、Swift Package 等）绝不可能只停留在 `-typecheck`，他们必须使用 `swiftc -c` 或 `swiftc -o` 构建动态库或二进制。如果在生成端因窄化为 `type-checker` 放行了构建期警告，下游开启 `-warnings-as-errors` 编译时便会直接炸库。这与“生成代码必须高质量、零告警”的规范宗旨背道而驰。

---

## 5. 应然裁定建议与验收可失败性（Falsifiability）

### 5.1 裁定建议
**应然裁定：明确将构建期诊断纳入 `:78/:80` 的验收口径。**

### 5.2 纳入与排除对验收可失败性的影响分析

- **若排除构建期诊断（宽口径）**：
  1. **零警告判据退化为空判据（Decorative / Vacuous Criterion）**：
     在 Swift 编译器流水线中，大量关于代码质量与结构缺陷的分析（如 `will never be executed` 死代码、无用变量赋值、变量未重用 `variable was never mutated`、SILGen 优化降级提示）都是在类型检查**之后**的 SILGen 及流程分析阶段才产生的。如果门禁只看 `swiftc -typecheck`，则生成器哪怕输出了极为混乱、充斥死逻辑甚至在实际构建时引发警告的代码，门禁都会给出 0 警告的“虚假绿色”。该判据将失去击败真实缺陷的能力，丧失科学哲学意义上的可失败性。
  2. **破坏既有管理判例的一致性**：
     [MANAGEMENT-RULING-245.md](file:///home/losses/Development/tq-workspace/boring-wt-builddiag/docs/architecture/MANAGEMENT-RULING-245.md) 第 45 行与第 53–55 行已白纸黑字载明：两份独立复核均确认在 `swiftc -c` 下 `Gap.swift:117:9` 有一条构建期诊断，标准要求为零且不予豁免，并据此对候选 `c8ae0054` 裁定最终 REJECT。如果此时通过重新解释规范将该诊断排除，就等同于事后推翻 MANAGEMENT-RULING-245，瓦解架构治理的公信力。
- **若纳入构建期诊断（严口径）**：
  1. **确保验收的可失败性与真实性**：
     构建步骤（如 `tests/swift-gap-boundary/gap-boundary.test.ts` 中的 `swiftc -c -whole-module-optimization ... -o gap.o`）真正生成目标文件，并严格检查 `buildDiagnostics` 中的 `warning:`。一旦发射器产生不可达语句等构建期缺陷，门禁坚决失败；只有在根源上修好发射器后才可通过。
  2. **倒逼生成器质量与架构完备性**：
     推动后端实现真正的可达性修剪，确保目标语言输出符合现代编译器的最高质量要求。

---

## 6. 核对 S1 修复（Commit `cd70eb12`）

### 6.1 核对方式
通过 `git show cd70eb12 --stat` 及 `git show cd70eb12` 仔细阅读提交内容、代码差异及提交附带的验证证据。

### 6.2 修复原理分析
在 `packages/compiler/reflaxe/swift/swiftcompiler/SwiftExpr.hx` 中：
1. **旧逻辑**：`blockLines` 在遍历语句列表 `stmts` 时，无条件把所有语句都交给 `stmtLines` 翻译并发射到输出数组 `out` 中。
2. **新逻辑**：
   - 引入变量 `var diverged = false;`。
   - 循环中增加检查：
     ```haxe
     while (i < stmts.length) {
         if (diverged)
             break;
         ...
         if (stmtDiverges(stmts[i]))
             diverged = true;
         i += 1;
     }
     ```
   - 实现了本地保守发散判定函数 `stmtDiverges(e:TypedExpr):Bool`：
     - `TReturn(_)` 与 `TThrow(_)` 判定为发散（`true`）；
     - `TBlock`：末尾语句发散则发散；
     - `TIf`：then 与 else 均发散则发散；
     - `TTry`：try 体与所有 catch 均发散则发散；
     - `TSwitch`：针对变体枚举 switch，若每个 case 臂均发散且覆盖全部枚举构造器（复用 `enumTable`），则判定整体发散。
3. **在 Gap 夹具上的作用**：
   在 `Gap.hx` 中：
   ```haxe
   class GapExplicitReturn {
       public static function switchExplicitReturn(choice:GapChoice):ReadOnlyArray<Int> {
           switch (choice) {
               case One: return Gap.sourceFirst();
               case Two: return Gap.sourceSecond();
           }
           return Gap.sourceFirst();
       }
   }
   ```
   因为 `One` 和 `Two` 穷尽了 `GapChoice` 且两臂均 `return`，`stmtDiverges` 判定该 `switch` 已经发散。随后的 `blockLines` 循环直接 `break`，不再发射随后的不可达语句 `return Gap.sourceFirst();`。
   因此，生成的 `Gap.swift` 彻底消除了第 117 行的死代码 return。

### 6.3 诊断可见性核验结论
- **`swiftc -typecheck`**：在修复前、修复后读数均为 0 条警告。它看不到死代码警告，因而**不能**作为该缺陷是否被消灭的有效度量工具。
- **`swiftc -c -whole-module-optimization`**：
  - 修复前（基线）：准确报告 1 条 `will never be executed` 告警；
  - 修复后（`cd70eb12`）：报告 **0** 条告警，成功生成 `gap.o`（278824 字节），且运行时对 Haxe oracle 逐字节一致。
  - 防腐针在 `gap-boundary.test.ts` 中完成反转更新：由原先“断言存在 1 条已记录告警”更新为“断言构建期告警数等于 0”。
- **结论**：`cd70eb12` 确已在发射器源头消灭了该诊断。

---

## 7. 任务书三问专项回答

### 问①：build 期诊断是否属于 `:78/:80` 的口径？
**答**：**属于。**
虽然 `:78` 字面提及 "the Swift type-checker"，但结合第一句总纲 "Generated code compiles without warnings on every target"、第二句 "A translation that produces a warning is an emitter defect"、`:80` 按套件输出统计告警行的规则，以及 Management Ruling 245 的权威裁决，完整构建期（`swiftc -c` / `swiftc -o`）报出的诊断必须且已被判定计入零警告口径。

### 问②：若是，`work-plan:415` 的 baseline 条款如何适用于一条"源中不可达"的语句？
**答**：
1. **源不可达不能成为翻译告警的豁免理由**：
   Haxe 4.3.7 对源码中不可达的尾部 return 保持沉默，是源语言前端的宽松性行为。但发射器若不加鉴别地将其原样发射到目标语言，导致严谨的目标编译器（Swift SILGen）报出 warning，根据 `:78` 这明确构成**发射器缺陷（emitter defect）**。
2. **严禁修改源文件掩盖缺陷**：
   根据 `02-translator-implementation-standard.md:92`，严禁通过删改 `Gap.hx` 源码中的尾部 return 来规避告警。
3. **`work-plan:415` 的精确适用**：
   `"Record any baseline failure separately, including its revision and reproduction; a baseline finding does not waive the standard."`
   在发射器修复前，该构建期警告必须作为**已记录的基线失败（Recorded Baseline Failure）**独立登记（包括修订号、复现方式以及带防腐针的测试套件，如 `gap-boundary.test.ts` 所做）；但**基线的存在绝不构成对标准的豁免（does not waive the standard）**。任何候选在清偿该基线缺陷（即完成发射器死代码修剪使告警清零）之前，均不能声称达到零告警标准，更不能免测通过。

### 问③：若否，该例外应记录在何处，使后续评审可引用同一处？
**答**：
尽管本裁定认定其**属于**验收口径，但若未来经所有者裁定产生针对特定构建期诊断的例外，依规范体系必须统一记录在以下法定位置：
1. **规范级例外账本（Exception Ledger）**：
   依据 `02-translator-implementation-standard.md:62`，在编译期 `SemanticException` 注册表中登记，并在 CI 产物 `out/semantic-pass-exceptions.json` 中体现增量，附带标识符、机制、目标、理由及校验夹具。
2. **架构基线台账（Baseline Failures Record）**：
   在 [BASELINE-FAILURES.md](file:///home/losses/Development/tq-workspace/boring-wt-builddiag/docs/architecture/BASELINE-FAILURES.md) 的“未豁免基线失败清单”中单独开辟章节，记录 revision 与 reproduction。
3. **夹具内防腐针注解**：
   在对应测试夹具（如 `gap-boundary.test.ts`）的头部规范注释中，显式声明该诊断豁免属于何次 Ruling 的特许决议，并冻结其精确读数。

---

## 8. 对下游的具体后果 (Downstream Consequences)

1. **对 P08 密封候选（`c8ae0054`）**：
   确认 Management Ruling 245 决议有效且不可撼动。`c8ae0054` 在 `swiftc -c -whole-module-optimization` 下存在 `Gap.swift:117:9` 的未清偿警告，违反零警告标准，其 **P08 NOT PASSED / REJECTED** 为终局状态。不得通过重新解释口径试图为其“翻案”或免检。
2. **对 S1 后继候选材料（`cd70eb12` 及后续冻结候选）**：
   - 确立了后继候选的验收口径必须强制包含 `swiftc -c -whole-module-optimization` 零警告断言；
   - 确认了 `cd70eb12` 的实现方向（在 `SwiftExpr.hx` 中通过 `stmtDiverges` 抑制发散后的死语句）是在发射器端清偿该缺陷的唯一合规路径；
   - 后继候选在重新冻结并提请独立复核时，必须以 `gap-boundary.test.ts` 中反转后的“0 pending build warnings”作为合规证据。

---

## 9. 规范文本修订建议（仅供参考，不修改正文）

建议在后续规范演进轮次中，将 `docs/specs/style/02-translator-implementation-standard.md:78` 文本修订为：

> **建议修订文本**：
> `1. Generated code compiles without warnings on every target: kotlinc, rustc, the TypeScript compiler, the Dart analyzer, and the Swift compiler (both type-checking and code-generation/build phases, including whole-module-optimization). A translation that produces a warning is an emitter defect with the same severity as a translation that produces wrong output.`

*(注：本工作严格遵守工作纪律，未直接修改 `docs/specs/**` 正文。)*
