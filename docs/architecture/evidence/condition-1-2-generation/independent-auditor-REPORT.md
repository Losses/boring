# R2 独立复核：condition 1/2 真正满足判定

**席位**：R2 独立复核席（本报告）
**日期**：2026-10-01 (America/Toronto)
**对象**：`boring` 仓 `arch/agent-guided-governance`，HEAD `649aa881`
**依据**：RULING-005 §①（condition 1/2 原始定义）、GATE-LEDGER.md 条件 1/2/4 行、
RULING-137、R2.2 三向检查报告、dc-warn 证据报告

**原则**：只读；不改台账、不改看板、不写 boring 主工作树。不可判定的如实说「无法判定」。

---

## 一、condition 2 判据（本席独立撰写，可执行、可证伪）

### 1.1 原始定义

RULING-005:46（中文原文）：

> 2. 每次生成的 `MathNaNTestSupport.{js,d.ts}` 条目均稳定，不能再在 `407/405`
>    间摇摆；`package-artifacts.test.ts:333` 连续重复运行通过。

### 1.2 本席判据（三部分）

| # | 判据 | 可执行检验 | 可证伪条件 |
|---|---|---|---|
| C2.1 | `MathNaNTestSupport.js` 每代 405 字节，`.d.ts` 始终不存在，≥5 代无一例外 | `tar -tzf <tgz> \| grep MathNaNTestSupport` 每代同输出 | 任意一代出现 `.d.ts` 或 `.js` 大小 ≠ 405 |
| C2.2 | 字节一致性测试（`package-artifacts.test.ts` "two generations…byte-identical"）连续 ≥3 次 pass | `bun test tests/ts/package-artifacts.test.ts` 连续 3 次 rc=0 | 任意一次 rc≠0 或 expect 失败 |
| C2.3 | Entry-gate 四要求（hash / 干净工作树 / 独立导出 / 执行者+复核者 claim-vs-commit 核对） | 逐条验证（见 §三） | 任一条不成立 |

**判据 C2.3 是形式性判据；C2.1 与 C2.2 是实体判据，需要实跑生成/测试。**
本报告对 C2.1/C2.2 仅能查证「现有报告是否一致」，不能独立重跑。

---

## 二、condition 1 判据

| # | 判据 | 出处 |
|---|---|---|
| C1.1 | 同一固定工作树 + 相同依赖/工具链下，连续 ≥5 次从干净输入生成 npm tgz，字节/校验和完全一致 | RULING-005:45 |
| C1.2 | Entry-gate 四要求（同 C2.3） | RULING-005 §③ |

---

## 三、台账全表审计：SHA / 路径 / 行号

### 3.1 SHA 引用

条件表（GATE-LEDGER:39-42）包含以下 SHA：

| 行 | 引用 SHA | 解析 |
|---|---|---|
| Cond 1 | `2aadcb69` | rc=0 ✓ |
| Cond 2 | `2aadcb69` | rc=0 ✓ |
| Cond 4 | `eec707b9`, `1704c3db`, `84eff599` | rc=0 ✓ |

额外验证：R2.2 报告、condition-4 README、entry-gate-r2r3 MAPPING 中引用的
`4f80322c`, `d3c3492f`, `77c12ab9`, `32f76bd9`, `c8ae0054`, `fc89d5d8`,
`449444cf`, `71a60c7d`, `b9c090ab`, `5a8f19e6`, `46b83a20`, `f6f7e3d3`,
`a14345ce`, `28820ff5`, `ed41e14d`, `4cf3165d`, `2bd609b9`, `52044ed1`,
`8b32f8a0`, `6322af89` — **全部 rc=0**。

**SHA 引用数 25，失败数 0。**

### 3.2 路径引用

| 行 | 引用路径 | HEAD 存在？ | 备注 |
|---|---|---|---|
| Cond 1 | `audit-reports/r22-three-way-check-2026-10-01.md` | **仓库内不存在** (`git ls-files` 归零) | 位于工作区 `/home/…/tq-workspace/audit-reports/`，不在 boring 仓 |
| Cond 2 | 同上 | 同上 | 同上 |
| Cond 4 | `docs/architecture/evidence/entry-gate-r2r3/` | ✓（commit `1704c3db`） | 12 个文件全部存在；`sha256sum -c` 11/11 OK |
| Cond 4 | `docs/architecture/evidence/condition-4-entry-gate/evidence/package-shell-adjudication-REPORT.md` | ✓（merge `84eff599`） | 14037 B |
| Cond 4 | `docs/architecture/evidence/condition-4-entry-gate/evidence/verify-eec707b9-REPORT.md` | ✓（merge `84eff599`） | 7415 B |
| Cond 4 | `docs/architecture/evidence/condition-4-entry-gate/` | ✓ | README + SHA256SUMS + evidence/ |
| Cond 1/2 | `dc-warn/out/npm-determinism/REPORT.md` | **仓库内不存在** | 仅存在于 fuse 挂载（`dc-warn`），不在 git 跟踪 |
| Cond 1/2 | `dc-warn/out/verify-2aadcb69/REPORT.md` | **仓库内不存在** | 同上 |

**路径引用数 8，失败数 3**（cond 1/2 的执行者/复核者报告 + R2.2 报告均不在仓内）。

### 3.3 行号引用

| 引用 | 位置 | 当前指向 | 与台账描述一致性 |
|---|---|---|---|
| `:338` | package-artifacts.test.ts @ 2aadcb69 | `expect(fs.readFileSync(…)).toEqual(…)` — 字节一致性比对 | ✓ 台账称「comparison is at :338」 |
| `:351` (parent) | 同上 @ d2d444c0 | 同一行（比对在父提交 :351） | ✓ |
| `:333` (parent) | 同上 @ d2d444c0 | `test("two generations…")` — 测试声明 | ✓ 台账称「:333 names the declaration there」 |
| `RULING-137:17-19` | MANAGEMENT-RULING-137.md | "Contract 3 condition 4: STILL NOT SATISFIED." | ✓ |
| `RULING-137:32-35` | 同上 | "Until condition 4 is satisfied…do not nominate, do not declare a pass, and do not change its status." | ✓ |
| `GATE-LEDGER:100` | 显式分离句 | "Satisfying the entry gate's evidence form does not satisfy condition 4, and does not nominate P08." | ✓ |

**行号不一致数：0**（全部经过独立核对）。

---

## 四、反向验证（反例尝试）

### 4.1 针对条件 2「entries 稳定」的反例

**假设**：`MathNaNTestSupport.d.ts` 实际上仍然出现在某代生成中。

**查找方法**：
```
find . -name "MathNaNTestSupport.d.ts" 2>/dev/null    # 零命中
grep -rn "MathNaNTestSupport.*flip\|407/405" docs/    # 仅 BASELINE-FAILURES 有历史记述，无当前主张
```

**结果**：树中无任何 `.d.ts` 文件。BASELINE-FAILURES.md:265-270 仍用现在时描述 flip，但该段落是基线记录的历史描述，不含超驰注记——这是**文档陈旧度缺陷**（PIT 候选），而非 condition 2 未满足的证据。

### 4.2 针对 condition 2「test passes repeatedly」的反例

**假设**：`2aadcb69` 之后的提交中，byte-identity 测试存在失败记录。

**查找方法**：
```
git log --oneline -- tests/ts/package-artifacts.test.ts  # 最新提交就是 2aadcb69
```

**结果**：自 `2aadcb69` 之后，无人改动该测试文件。无「修复回归」提交——这与「test passes」一致，但不构成正面证据（pass 不需要修补）。

### 4.3 针对 entry-gate R2 的反例

**假设**：`2aadcb69` 的干净工作树证明不可复现。

**我的独立重建**：
```
git worktree add --detach /tmp/r2b-2aadcb69-wt.XXXXXX 2aadcb69   # rc=0
git -C <wt> status --porcelain                                    # 空，0 行
```
**结果**：**0 porcelain 行**，与已提交 `2aadcb69.R2-worktree.txt` 一致。反例不成立。

### 4.4 针对 entry-gate R3 的反例

**假设**：导出压缩包校验和与已提交值不同，或 manifest 与 git tree 不同。

**我的独立重建**：
```
git archive --format=tar 2aadcb69 | sha256sum
→ 38b6d43a3418d8602eeaa6fed381f06ff3eee7a29ba4292f41cb5a87a2a9a2e0
  = 已提交 .export.tar.sha256 ✓

diff <(git ls-tree -r 2aadcb69 | awk '{printf "%s\t%s\n",$3,$4}' | sort) \
     <(awk '{printf "%s\t%s\n",$1,$2}' 2aadcb69.R3-manifest.txt | sort)
→ 0 diffs, 1455/1455 ✓
```
**结果**：反例不成立。

### 4.5 针对 claim-vs-commit 独立性的反例

**假设**：复核者就是执行者，或复核未独立完成。

**查找**：阅读两方报告。
- 执行者（npm-determinism/REPORT.md）：以第一人称描述实现，92 行，5-gen 数据。
- 复核者（verify-2aadcb69/REPORT.md）：247 行，声明「not the implementer」，编写了独立 driver（`repro-verify.mjs`），明确了执行者报告中缺少的证据（重复运行日志），并自行补测。两方方法、代码、数据路径均不同。

**结果**：独立性成立。复核确实存在，确实独立。

---

## 五、独立复核是否存在

| 检查项 | 结论 | 证据 |
|---|---|---|
| 复核是否存在 | **是** | `dc-warn/out/verify-2aadcb69/REPORT.md`（247 行，2026-09-30） |
| 复核者是否不同于被复核者 | **是** | 复核者声明「not the implementer of 2aadcb69」；执行者报告 92 行，复核者报告 247 行，方法/行文/数据完全不同 |
| 复核是否独立（不同方法） | **是** | 复核者编写了独立 driver（`repro-verify.mjs`），未使用执行者的脚本或证据；复核者发现了执行者证据的缺口（「no repeated-run log exists」）并自行填补 |
| 复核是否在仓内 | **否** | 报告仅存在于 `dc-warn/out/`（fuse 挂载），不在 git 跟踪中 |

此外，R2.2 三向检查（`r22-three-way-check-2026-10-01.md`）提供了**第二层**独立检查，确认了 entry-gate 四项要求。该报告同样不在仓内（位于工作区 `audit-reports/`）。

---

## 六、判据的诚实边界（本环境无法判定的部分）

| # | 无法判定项 | 原因 | 需要什么才能判定 |
|---|---|---|---|
| 1 | C1.1：连续 ≥5 次从干净输入生成 npm tgz，字节/校验和一致 | 需实跑 haxe 4.3.7 + bun 1.3.13 + tsc 5.9.3 + kotlinc 2.4.10；本环境无完整 nix 工具链 | 可运行 `bun run gen:ts` + `bun test tests/ts/package-artifacts.test.ts` 的环境 |
| 2 | C2.1：`MathNaNTestSupport.js` = 405 B, `.d.ts` 始终 absent，≥5 代无一例外 | 同上；`tar -tzf` 需要先生成 tgz | 同上 |
| 3 | C2.2：字节一致性测试连续 ≥3 次 pass | 同上；测试耗时 350-420 s/run（16 核），本环境不可行 | 同上 |
| 4 | C1.1/C2.1 的「真正稳定性」（与 CI runner 环境的可比性） | 两方报告均在 16 核本机上运行；CI runner 环境可能有不同争用/时序 | 在 CI runner 上重复生成并比对 |
| 5 | `collected-suite` 不再因该 flake 失败（condition 3） | Condition 3 的完整端到端验证需要 CI runner + 数小时运行 | CI runner |

**已知但可独立验证的部分**（不属于「无法判定」）：
- Entry-gate R1（hash）：独立确认 ✓
- Entry-gate R2（干净工作树）：独立重建 ✓
- Entry-gate R3（导出/校验和）：独立重建 ✓
- Entry-gate R4（claim-vs-commit）：两方报告存在、独立、一致 ✓（但有记录位置缺陷）
- 所有 SHA：全部分辨 ✓
- 所有行号：全部核对 ✓

---

## 七、结论

### 7.1 condition 1 裁定：**无法判定**

**理由**：condition 1 的实体判据（「连续多次从干净输入生成 npm tgz，每次归档字节和校验和完全一致」）需要实跑 haxe toolchain 生成 npm tgz 并逐字节比对。两个独立测量（执行者 5 gen, 1 hash；复核者 9 gen, 1 hash）技术主张一致，entry-gate 形式证据完整，SHA/路径/行号全部验证通过。但本席**不能独立重跑生成**，依据「不要猜」原则，裁定为无法判定。

**额外发现**：condition 1/2 的执行者与复核者报告均仅在 `dc-warn/out/` scratch（fuse 挂载），不在 boring 仓内。这与 condition 4 之前的情况相同（R2.1 解决了 condition 4 的记录位置缺陷，但 condition 1/2 仍未解决）。

### 7.2 condition 2 裁定：**无法判定**

**理由**：同上。condition 2 的实体判据（「MathNaNTestSupport 条目 405/absent 稳定，byte-identity test 连续重复 pass」）需要实跑。现有证据（执行者 10 gen 稳定 + 复核者 9 gen 稳定 + 复核者 3 次独立重复运行 pass）强有力地支持「技术主张成立」，entry-gate 形式证据完整，SHA/路径/行号全部核对无误。但本席**不能独立重跑**，裁定为无法判定。

**额外发现**：
1. **行号引用**：台账注明「at `2aadcb69` the comparison is at `:338` (`:351` in the parent; `:333` names the declaration there)」——本席独立核对全部三个行号，**全部正确**。原始 RULING-005:46 引用的 `:333` 是父提交中测试声明的行号，字节比对在 `2aadcb69` 中是 `:338`，台账的标注精确。
2. **BASELINE-FAILURES 陈旧度**：`:265-270` 仍用现在时描述「The entries flip in and out between runs」，而 `2aadcb69` 已是 HEAD 的祖先且修复了该问题。该段落缺少超驰注记——属文档陈旧度缺陷，非 condition 2 未满足的证据。
3. **`no in-repo location` 残余**：condition 4 的「no in-repo」已被 R2.1 修复（`84eff599`），但 condition 1/2 相同的缺口**仍然存在**。两方报告（npm-determinism、verify-2aadcb69）仍仅在 `dc-warn/out/` scratch 中。

### 7.3 最小证据集（独立复现本席结论所需命令）

```bash
# Entry-gate R1: sha 解析
git -C boring cat-file -e 2aadcb69^{commit}; echo $?  # 0

# Entry-gate R2: 干净工作树
git -C boring worktree add --detach /tmp/wt 2aadcb69
git -C /tmp/wt status --porcelain | wc -l            # 0

# Entry-gate R3: 导出一致性
git -C boring archive --format=tar 2aadcb69 | sha256sum
# → 38b6d43a3418d8602eeaa6fed381f06ff3eee7a29ba4292f41cb5a87a2a9a2e0

diff <(git -C boring ls-tree -r 2aadcb69 | awk '{printf "%s\t%s\n",$3,$4}'|sort) \
     <(awk '{printf "%s\t%s\n",$1,$2}' boring/docs/architecture/evidence/entry-gate-r2r3/2aadcb69.R3-manifest.txt|sort)
# → rc=0

# 行号核实
git -C boring show 2aadcb69:tests/ts/package-artifacts.test.ts | awk 'NR==338'
# → expect(fs.readFileSync(path.join(second, pkg.file))).toEqual(…)

# 反例：condition 1/2 报告不在仓内
git -C boring ls-files | grep -c 'npm-determinism\|verify-2aadcb69'
# → 0
```

---

## 八、未完成项 / 未覆盖项

| # | 项 | 状态 |
|---|---|---|
| 1 | condition 1/2 的执行者+复核者报告 in-repo 入库 | **仍未做**（condition 4 已做，condition 1/2 漏掉） |
| 2 | R2.2 三向检查报告的 in-repo 入库 | **未做**（报告在 `audit-reports/` 工作区，不在仓内） |
| 3 | BASELINE-FAILURES.md:265-270 陈旧描述加超驰注记 | **未做**（仍用现在时描述已修复的 flip） |
| 4 | Condition 1/2 实体判据的实跑复核 | **本席无法完成**（需要 haxe/bun/tsc/kotlinc 工具链） |

**未对 boring 仓做任何写入。** 本报告仅写入工作区 `audit-reports/`。