# 分层验证方案审阅：9 个缺口与逐条复核

审阅对象：`docs/architecture/LAYERED-VERIFICATION.md`。
审阅由独立席位执行（只读，未改任何文件），本文件是**主 Agent 对该审阅的独立复核**：
每一条要么被读回产物确认，要么被降级为「未复核」。**复核不等于采信。**

被审阅树：`ci/collected-suite-failure-attribution` @ `99b6a7c4`。
声明的 base：`arch/agent-guided-governance` @ `0641991b`。

标记：**[已复核]** = 主 Agent 亲自读回产物确认；**[未复核]** = 仅转述审阅，尚未独立确认。

---

## 1. 最重要的一条：方案正文断言了一个不存在的防护 —— **[已复核]，已修**

方案原文第 12 行（L3 行）称：**「S1 已使其归零（1 → 0）」**。

三条独立读数，全部指向同一结论：

| 检验 | 命令 | 结果 |
|---|---|---|
| `cd70eb12` 是 base 的祖先吗 | `git merge-base --is-ancestor cd70eb12 arch/agent-guided-governance` | **rc=1（否）** |
| 它活在哪些分支 | `git branch -a --contains cd70eb12` | 仅 `prep/p08-s1-unreachable-return`（候选材料） |
| `stmtDiverges` 在树里吗 | `grep -rn stmtDiverges --include=*.hx packages/` | **0 命中** |
| 当前诊断计数 | 夹具断言 | **1，且被显式钉住** |

夹具 `tests/swift-gap-boundary/gap-boundary.test.ts` 的注释自述这 1 条 warning 是
「an unwaived, recorded baseline failure -- the goal remains zero diagnostics under `-c`」，
断言为 `toHaveLength(1)`。**夹具说「缺陷仍在」，文档说「已归零」，两者不能同真。**

`rulings/BUILD-PHASE-DIAGNOSTIC-RULING.md` 中「1 → 0」的记载描述的是 `cd70eb12`
**那棵树**，在该树内为真；把它当作当前线状态引用才是错误。

**错误形状**：把候选材料树上的实测写成当前线上的既成事实。这恰是方案自己 L0 节
（第 45–53 行）要求的「必须给出 commit + `is-ancestor` 结果」——该规则当时**没有任何机器执行**
（`grep -rn "is-ancestor" --include=*.ts --include=*.sh --include=*.json` 全仓无命中），
所以被违反了而没人发现。**一条只靠人自觉的元规则，等于没有规则。**

**处置**：已改方案第 12 行为「当前事实是『未归零』」，并新增一节记录这次修正与错误形状。

## 2. 方案内部自相矛盾 —— **[已复核]，已修**

第 12 行写「**已裁定：计入验收口径**」，第 123 行「未决」节又列
「L3 的构建期诊断是否计入验收（`t-muo92xms-s28t`，未认领）」。同一份文件对同一问题
给出两个相反状态。且该任务在板上的状态是 **done**，把它列为「未认领」是三重矛盾。

**处置**：该行已从「未决」节删除（裁定任务已完成，不再是未决项）。

## 3. 零警告门禁可以在生成树编译失败时给 PASS —— **[已复核]，未修**

`tools/warning-gate/check.sh` 的 `check()`：编译诊断数 `n` 只与基线比大小，
宽松/严格两次运行的 rc 仅被 `printf`，从不参与判定；唯一特判是 127（编译器缺失）。

后果：kotlinc/cargo/dart **报错**但产出 0 条 warning 行时，`n=0 <= baseline` ⇒ **PASS**。

**但必须公正判读，这不是作者疏忽**：脚本注释与基线值（dart 46 / kotlin 59 / rust 4）
表明它自始就是**「不回归门禁」**，不是标准 `:80` 要求的「零警告门禁」。作者已经把
`-Werror`（kotlin strict）与 `--fatal-warnings`（dart strict）**跑出来了并打印了 rc** ——
也就是说**失败能力已经存在、成本已经付过，只是没有接线**。

这是一个真实且可修的架构缺陷，形状是：**同一个判断有两个来源，其中一个从未被读取**
（与 `ARCHITECTURAL-CONTRACTS.md` 契约 6「一个判断只能有一个来源」同族）。

**处置**：未修（属实现任务，不在本次文档审阅范围）。建议单独建任务：
「把 warning-gate 的 strict 列 rc 接入判定」。

## 4. CI 里被当作「契约 3 验收判据」的计数是空域 —— **[已复核]，确认为真**

`ci.yml:356` 的判据是：从 `out/collected-suite.log` 里
`grep -iE 'warn' | grep -E 'reference/[a-z0-9-]+/gen(-tests)?/'`，要求计数为 0（`:362`）。

**实测两份真实日志**（不需要重跑，历史证据即可判定）：

| 日志 | 行数 | 命中 `warn` ∧ `reference/*/gen` 的行 | 全log 中 `warning:` 出现次数 |
|---|---|---|---|
| `dc-warn/out/ci-wire/evidence/run-A-collected-suite.log` | **28** | **0** | **1** |
| `dc-warn/out/ci-attribution/evidence/pre-existing-collected-suite.log` | **126** | **0** | **1** |

那份 28 行日志的**全部内容**是 1 个测试文件（`bundle-child-evidence`）的 19 条测试结果
加一个 bun 摘要头。它唯一的 `warning:` 行是：

```
warning: Git tree '/home/losses/Development/tq-workspace/boring-wt-architecture' is dirty
```

—— 与生成树无关。日志里**没有** kotlinc / dart / cargo / swiftc 的任何输出。

**结论**：该 grep 在 `bun run test` 的日志上**结构上不可能命中**，域是空的。
方案第 25–28 行自己已裁定该日志不含五目标编译器输出；实测把这一裁定坐实。
按方案自己对门禁类判据的推论（第 40–41 行），**只报「通过」无法区分
「检查通过」与「没有检查」** —— 这条判据的「能失败」从未被建立。

`dc-warn/out/ci-warning-count/evidence/run-over-baseline/` 与 `run-green/` 这一对
正是审阅以外的人做过的同类判别实验，值得复看它们当时注入的是什么。

## 5. L4 的两条失效条件防护最弱 —— **[未复核]**

- **惰性求值在被收集套件里零覆盖**：审阅称 `grep -rniE "lazy|laziness|惰性"` 的命中
  全是 Rust `LazyLock` 文本断言。而惰性正是 P08 台账反复出现的行为面。
- **oracle 无外部对照**：跨跑者一致性对「六者共享的同一处作者错误」免疫。
- `readonly-boundary.test.ts` 的归一化会抹掉 `文件:行:` 前缀差异，该差异不在判据覆盖内。

## 6. L5 的常设形态缺失 + 大面无覆盖面 —— **[已复核：一条被推翻，两条需改写]**

复核报告：`L4-COVERAGE-RECHECK.md`（独立席位，交叉核验）。结论不是「确认」而是**修正**：

| 指控 | 复核结论 |
|---|---|
| `tests/haxe/` 下 43 个目录 | **一致**（43） |
| 27 个 `run.sh` | **只在「直接子」口径下一致；实际总数 29**（另有 2 个嵌套：`flow/replay/run.sh`、`source-container-policy/gen/run.sh`） |
| 35 个「有 runner 但无被收集测试」 | **数值一致（=35）**，但**措辞错**：35 里只有 **26** 个真正带 `run.sh`，另 **9** 个是**纯 `.hxml`、根本没有 `run.sh`**。故原句「27 个 run.sh 其中 35 个有 runner」**算术上不自洽**（27≠35），是把两种口径混写 |
| 这些 `run.sh` 不被任何 CI job 执行 | **成立**：`grep -c "run\.sh" .github/workflows/ci.yml` → **0，rc=1**；且已扩大到该 rev 的全部 tracked 文件（`git grep` 88 命中），逐条分类后**无一条是执行路径**（散文 / 哈希清单 / 字符串字面量 / 注释 / 守卫自身引用） |
| `dc-promoted-eval` 在这 35 之内 | **成立** |
| **「这 35 个夹具不被任何入口触及」** | **被推翻**：`tests/ts/package-shell.test.ts:388` 读取并执行 `tests/haxe/swift-package-shell-emit/emit.hxml`（该夹具属那 9 个纯 `.hxml` 成员）。**至少有一个成员是被收集路径真实触及的。** |

**已复核**：`bun test tests/fixture-reachability.test.ts` → **2 pass**，常量
`RECORDED_UNCOLLECTED = 35` 与独立枚举一致；且该常量的判据是**混合口径**
（`hasRunner` = 有 `run.sh` **或** 有任何 `.hxml`），所以它**不能**被读作「35 个 run.sh 夹具」。

**教训**：审阅给的三个数字里有两个是**口径未声明**的，其中一个还与前一个算术不相容。
**转述别人的计数前，先问它的口径是什么** —— 这与缺口 1（候选树结论被当成线状态）
是同一族错误，只是这次错在**口径**而不是**树**。

## 7. L0 两条规则与交付面规则完全靠人 —— **[已复核]，且已修其一半**

审阅称 `is-ancestor` 与 `ls-files --error-unmatch` 在整个 `*.ts/*.sh/*.json` 中零命中，
`gate:verify` 不在 CI。**第 1 条缺口已经证明这正是出错的那条规则** ——
一条只写在正文里的规则，等于没有规则。

**处置：L0 的树规则现在有机器执行了。** `tests/doc-reference-integrity.test.ts` 新增一条：

> 一条**声称已生效**的断言如果引用了 commit，该 commit 必须可从 base **或** HEAD 到达，
> 否则该行必须自己说明它成立在哪棵树上。

**负控已做，且用的是真实发生过的错误**：在一份副本里把第 12 行还原成历史错误句
（`S1 已使其归零（1 → 0，cd70eb12）`），守卫 FAIL 并精确点名
`LAYERED-VERIFICATION.md:12`。该行附近同时留有「未归零」字样，所以抓到它的是
**祖先关系**而非措辞巧合 —— 这才是这一条能成立的理由。

**守卫第一次跑就误报了** `GATE-LEDGER.md:614`（`f8bb6d40`）：它确实不在 base，
但在 HEAD 上，**文档是对的、守卫太窄**。已把可达性基准从「仅 base」放宽为
「base 或 HEAD」。这次误报本身就是该守卫文件自己警告的
「观察域小于所声称的性质」，记在 PIT-405。

`ls-files --error-unmatch`（交付面规则）**仍未机制化**，缺口 7 只闭了一半。

## 8. 收集域漂移不复核 —— **[未复核]**

审阅实测收集域 **314 文件**（251 生成 + 62 tests + 1 registry），方案第 118 行称
**303**（249 生成），CI 注释称 **304**。而基线 `1001 pass / 32 fail / 8 errors`
仍绑在 303 域上 —— 二者不同域却仍被并列对账。方案说「计数已存在」，但**域计数没有门禁**。

## 9. `tools/roots-guard/` 未被任何脚本调用 —— **[未复核]**

审阅称其与 base **逐字节相同**（已由 `8b32f8a0` 从 `1cafaa42` 取入），
所以方案第 50–53 行「base 上跑的是弱版」对当前 base 已过期；且该守卫
**没有被任何脚本或 CI 调用**（`grep -rn "check-roots-guard"` 除自引用与文档外无命中）。

**一个没人执行的守卫，与它是否硬化无关** —— 这条判断值得单独记入 PIT。

---

## 复核结论

审阅的**头号指控（缺口 1）与内部矛盾（缺口 2）已独立复核并修复**。
缺口 3 已复核且判读清楚（不回归门禁 vs 零警告门禁，缺口是 strict 列未接线）。
缺口 4–9 **尚未独立复核**，本文件如实标记，不把它们写成已确认事实。

**下一步（按价值排序）**：
1. 复核缺口 4（WARN_COUNT 空域）—— 它决定 CI 里那条判据是否真实存在。
2. 复核缺口 6（35 夹具不被收集）—— 它决定 L4 的真实覆盖面。
3. 建任务修缺口 3（strict rc 接线）。
4. 复核缺口 8（域漂移）—— 它决定基线数字能否与当前树对账。
