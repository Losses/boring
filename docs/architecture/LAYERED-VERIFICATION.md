# 分层验证方案

分类说"归谁"，契约说"承诺什么"，本文件说**每一层用什么可观察量检验**，
以及**每个判据何时会骗人**。

## 分层与判据

| 层 | 被检验的性质 | 可观察量 | 通过判据 | **该判据何时骗人** |
|---|---|---|---|---|
| **L1 生成** | 编译器未崩溃、产物齐全 | 生成进程退出码 + 文件清单 | `rc=0` 且预期文件存在 | **rc=0 不代表产物正确**：`:2609` 的 `fail()` 也会走到 rc=1，但"未触达崩溃"的输入 rc=0 而输出错 |
| **L2 语法/类型** | 产物在目标语言里合法 | `swiftc -typecheck` / `tsc` / `rustc --emit=metadata` | 0 error | **`-typecheck` 不跑 SILGen**：剥离 `return` 的多语句闭包只报 warning、真实构建才失败。**此类形态必须用 `swiftc -c`** |
| **L3 构建** | 产物可链接成可执行 | `swiftc -c` / `swiftc -o` | 0 error | 构建期诊断（`will never be executed`）**不在 `-typecheck` 里出现**。**已裁定：计入验收口径** —— 见 `rulings/BUILD-PHASE-DIAGNOSTIC-RULING.md`（`1a486ebd`）。**本条目的当前事实是「未归零」**：该诊断计数仍是 **1**，它是一条**未豁免的已记录基线失败**，见下节「这一层当前不是绿的」 |
| **L4 行为** | 运行结果正确 | 与 oracle 逐行比对 | **逐字节相同** | oracle 本身错了就全错；且"同一输入下与 oracle 相同"**不覆盖** oracle 未表达的性质（惰性） |
| **L5 判别** | 该检查**能**发现目标缺陷 | 对故意错误的后端运行 | 故意错误 ⇒ **FAIL** | 若无此层，L1–L4 全绿可能只说明**该性质未被观察** |

## L5 是本会话补上的一层（此前缺失）

**"检查无法发现目标缺陷"的实例**：

1. **`branchBoundary` 夹具**：两分支等长，消费者只打印长度 ⇒ 一个"总取任一分支"
   的后端**通过所有断言**。修复后 `branch-false=1:2:present` 对故意错误的
   后端 FAIL（提交 `d1180768`）。
2. **`swiftc -typecheck`**：漏报 "missing return in closure"（`lambda-fix-xcheck` §5）。
3. **拼接类修改**：生成树 pre/post 逐字节相同 ⇒ 无法区分"未生效"与"改对了"。
4. **零警告门禁根本不存在**（`t-mum29cli-9c9w`，`89dd80b2`）：`:78/:80` 要求零警告，
   但 `package.json:21` 的 `test:dart` **显式**带 `--no-fatal-warnings`、`:12` 的
   `test:rust` 无 `-D warnings`、CI 唯一门禁 `collected-suite` 只 grep `bun run test`
   日志而该日志**不含**五目标编译器输出 ⇒ **通过态下 grep 域为空**。既有警告存量
   Dart 46 / Kotlin 59 / Rust 4 全部 rc=0。**可复现的判别法**：同一棵树注入**一条**警告，
   跑"现有命令"与"严格命令"——`dart: loose rc=0 / strict rc=2`、`rust: loose rc=0 /
   strict rc=101`；**若两者 rc 相同，说明该门禁并不存在**（该席把它做成了可重跑的
   `verify.sh`）。修复行 `fix/zero-warning-gate-wiring`。
5. **"改了发射器"不等于生成了不同产物**（PIT-347 实测）：某席在 `Compiler.hx` 加了
   **38 行** AST 遍历旁路，`diff -rq` 对**整棵生成树**显示 **0 处差异**、目标位点
   一字未变。**判别法**：任何 emitter 改动都必须**重新生成并 diff 生成物**才算数；
   源码 diff 看着合理不构成证据。（同一行的另一次重派只改 **9 行**却真正改变了位点。）

**⇒ L5 的操作形态**：每个夹具必须配一个**故意错误的后端**（取错分支、返回错值、
剥掉转换），并证明该夹具在它上面 FAIL。**只证明"正确后端通过"不算验证。**
**⇒ 对"门禁类"判据的推论**：必须**同时**给出宽松与严格两次运行的 rc —— 只报"通过"
无法区分"检查通过"与"没有检查"。

## 每个判据必须写明"在哪棵树上成立"（本会话新增，L0 前置）

**规则**：任何声称"已修 / 已生效 / 已闭合"的判据，必须在**同一行**给出
**commit 哈希**与 **`git merge-base --is-ancestor <commit> arch/agent-guided-governance` 的结果**。
结果为否的，只能写成"分支态 / 工作树态"，**不得**写成已生效。

**为什么这不是形式主义**：本会话实测到同一件东西在两棵树上给出**相反结论**——
`tools/roots-guard/` 的硬化版（`1cafaa42`，+923 行）**已审已签**却**从来不是 base 的祖先**，
于是 base 上跑的是弱版：删掉真实根 `boring.ArraySliceOps` 再补一条 reason 为 `"because"`
的豁免，弱版 **rc=0 PASS（4 exemptions）**、硬化版 **rc=1** 并逐字点名。
即"已签核"与"已生效"是两件事；不写明树，一个**不存在的防护**会被记成存在。

**三步核实法（签核或接手前必跑）**：
1. `git rev-parse --verify <branch>` —— 该分支**存在吗**（本会话有若干行的 `branch` 字段指向**从未创建**的分支）
2. `git merge-base --is-ancestor <commit> arch/agent-guided-governance` —— **进 base 了吗**
3. **直接读共享树里的文件** —— base 里**到底是什么形态**（第 3 步不可省：本案前两步都过，第三步才发现是弱版）

**合入后还要核落点**：`git rev-parse --abbrev-ref HEAD`（我现在在哪条线上）**与**第 2 步（它真在**声明的 base** 上吗）——
本会话有一次四个 merge 全落在工作线上、而声明 base 未动，导致新开的 worktree 拿不到那些修复。

## 交付面：承重件必须能回答"哪个 commit 里有它"

**规则**：工具、护栏、夹具、驱动、断言脚本这类会被后人依赖的东西**必须入库**；
证据可以只放报告。判据若依赖某文件，须同时给出**它在 clone 里可达**的依据
（例如 `git ls-files --error-unmatch <path>` 通过、且 `git archive HEAD` 能取出）。

**本会话两次实测**：① `dc-warn/worktrees/` 下 **37/37** 全是 detached HEAD、**全有未提交改动**、
**无一带超出 `e1c65975` 的提交** —— "工作树里做完 + 报告在档"成了本批的实际交付约定；
② 证据清单 `FILES.sha256` 混入 2 条 **git-ignored** 的 `dc-warn/out/...` 路径，
使"一条命令 rc=0"**只对作者的工作副本成立**、对 clone 为假（PIT-346）。
**修法**：清单可**分节标注可达性**（repo-verifiable / evidence-only），并在**只含已提交文件的干净导出树**里验。

## 每层的证据强度必须分开陈述

**不得**把三者混为一谈：
- "生成成功"（L1）
- "生成的代码类型检查通过"（L2）
- "运行结果正确"（L4）

**本会话的一次误判即源于此**：以 `-typecheck` 0/0 作为验收判据提交了 `d14aae11`，
而该判据看不到 L3/L4 层的问题（P4 回归只在完整构建下暴露）。

## 覆盖率的诚实报告

**规则**：报告"覆盖 N/M"时必须同时给出**被跳过的项及其原因**。

**实例**：P1 范围化运行声称"每个 P1 更新的期望都被 exercised"，
实际 **56/57**——`printed-record.test.ts:88` 只在超时的测试里被消费，
故从未执行；而 `array-root.test.ts:18` 的既存红使 `L28` 从未到达。
（教训 PIT-321）

## 超时与失败必须区分

**判据是"主体是否跑完"，不是"是否超时"。**

**实例**：`value-type` 的耦合运行**并非被杀死**——`Bun.spawnSync` 阻塞 bun 定时器，
耗时 351 s ≈ 15 次运行，临时目录在两副本中都消失 ⇒ 主体**跑完了**。
把它读作"被超时掩盖的耦合"是错的；正确表述是**潜伏耦合**
（修复根本不在那些探针的执行路径上）。

## 每层对应的命令（现状）

| 层 | 命令 | 是否在 CI 中 |
|---|---|---|
| L1 | `haxe <fixture>.hxml` | 部分（26 个 `bun run test:*` 脚本） |
| L2 | `swiftc -typecheck` / `tsc` | 部分 |
| L3 | `swiftc -c` | **否** |
| L4 | 夹具自带 runner + oracle | **否** |
| L5 | 判别性后端 | **否** |
| 收集 | **`bun run test`（收集 `tests/**`）** | **是**（`collected-suite` job，`9f26e1ef`） |

**⇒ 结论**（`9f26e1ef` 起）：`collected-suite` job 每次运行入口 `bun run test`，
报告收集域与计数；该 job 阻塞、无 `continue-on-error`，破坏受保护断言即失败
（负控证明见 `dc-warn/out/ci-wire/`）。**计数已存在**，但标准 `:80` 的
"count is zero" **仍未满足**：基线（`1001 pass / 32 fail / 8 errors`）尚未清偿，
`BASELINE-FAILURES.md` 只记录、不豁免。收集域为 303 文件，其中 249 个来自
生成树 `reference/ts/gen-tests`，故该 job 先重生成再收集。

## 这一层当前不是绿的（L3 构建期诊断，修正记录）

**本文件早先的版本在第 12 行写过「S1 已使其归零（1 → 0）」。那是错的，此处更正并保留
错误形状，因为它正是本文件 L0 节自己警告的那一类。**

错误形状：把**候选材料树上的实测**写成了**当前线上的既成事实**。分别核对：

| 问题 | 结果 |
|---|---|
| `cd70eb12` 是 `arch/agent-guided-governance`（base）的祖先吗？ | **否** —— `git merge-base --is-ancestor cd70eb12 arch/agent-guided-governance` → rc=1 |
| 它出现在哪些分支上？ | 仅 `prep/p08-s1-unreachable-return`（含 origin 同名分支）—— 是一份**候选材料** |
| `stmtDiverges` 在当前树里存在吗？ | **否** —— `grep -rn stmtDiverges --include=*.hx packages/` → 0 命中 |
| 当前树上的诊断计数是多少？ | **1**，且被夹具**显式断言必须存在** |

`tests/swift-gap-boundary/gap-boundary.test.ts` 把这 1 条 warning 钉住，其注释自述
这是「an unwaived, recorded baseline failure -- the goal remains zero diagnostics under
`-c`」，断言为 `toHaveLength(1)`。所以：

- **夹具说的是「缺陷仍在」**（防腐针，缺陷一旦真被修掉，这条断言会失败并强制重读计数）；
- **文档那时说的是「已归零」**。

两者不能同时为真，实测站在夹具一边。`rulings/BUILD-PHASE-DIAGNOSTIC-RULING.md` 中
「1 → 0」的记载描述的是 `cd70eb12` **那棵树**，在该树内它为真；它不能作为当前线的状态引用。
把候选树结论写成线状态，与本记录 L0 节要求的「必须给出 commit + `is-ancestor` 结果」
直接冲突——而这条规则当时没有任何机器执行，所以它被违反了而没人发现。

**教训（已写入 L0 节）**：一份候选材料的实测结果，只有在 `is-ancestor` 为真时才能写成
「已生效」。此前本文件恰恰缺这一步。

## 未决

- **L5 的判别性后端是否写入每个夹具**（当前只有 `branchBoundary` 与 gap 驱动有）
- **`swiftc -c` 是否应取代 `-typecheck` 成为所有 Swift 验收的口径** ——
  证据支持按形态区分（普通形态 `-typecheck` 足够，剥离 return 的形态必须 `-c`）
