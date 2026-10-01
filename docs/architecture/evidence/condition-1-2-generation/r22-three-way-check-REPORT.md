# R2.2 三向检查报告 — eec707b9 / 2aadcb69

**出具人**：R2.2 席（非实现者，独立重跑）
**日期**：2026-10-01 (America/Toronto)
**对象**：
- `eec707b9b09ccabdc7541b74174c6d8cf1e9ef0e` (contract 3 condition 4)
- `2aadcb6978d81705379892d2b382671b3458e753` (contract 3 conditions 1/2)
**HEAD**：`f6f7e3d3` (arch/agent-guided-governance)
**门禁脚本名**：`bun run gate:verify` (package.json:50 → `bun tools/gate-proof/verify-commit.ts`)

---

## 方法

三向检查：仓库门禁 (`bun run gate:verify`) + 重读入库 R4 报告 + 逐条对照 entry gate 四要求。
四要求原文引自 `docs/architecture/GATE-LEDGER.md:187-194`（方法段 :201-229）。

---

## 一、eec707b9（contract 3 condition 4）

### 要求 1 · 可追溯的 commit hash

| 字段 | 值 |
|---|---|
| **要求原文** | "A traceable commit hash." (GATE-LEDGER:189) |
| **独立测量方法** | `git rev-parse --verify eec707b9^{commit}` + `^{tree}` |
| **原始输出** | commit=`eec707b9b09ccabdc7541b74174c6d8cf1e9ef0e`; tree=`0a61e32ab7978b37de4d5362c548b50609b6b3fd` |
| **判据** | **CONFIRMED** — 哈希解析成功；tree 与 MAPPING.md 和已提交 R2-worktree.txt 内编号一致 |

### 要求 2 · 干净工作树证明

| 字段 | 值 |
|---|---|
| **要求原文** | "A clean working-tree proof for that hash." (GATE-LEDGER:191) |
| **独立测量方法** | `git worktree add --detach /tmp/r22-eec707b9-wt.XXXXXX eec707b9` → `git status --porcelain` |
| **原始输出** | HEAD=`eec707b9b09ccabdc7541b74174c6d8cf1e9ef0e`; tree=`0a61e32ab7978b37de4d5362c548b50609b6b3fd`; `git status --porcelain` 输出空（0 行） |
| **判据** | **CONFIRMED** — 独立重建的 detached worktree 零 porcelain 行，与已提交 `eec707b9.R2-worktree.txt` 一致 |

### 要求 3 · 从该 commit 独立导出的内容/校验和

| 字段 | 值 |
|---|---|
| **要求原文** | "The candidate content/checksums, exported independently from that commit or from an explicit freeze archive - not read out of a live worktree." (GATE-LEDGER:192-193) |
| **独立测量方法** | (a) `git archive --format=tar eec707b9 \| sha256sum`; (b) `diff <(git ls-tree -r eec707b9 \| awk … \| sort) <(manifest \| awk … \| sort)`; (c) `bun run gate:verify -- eec707b9` |
| **原始输出** | (a) `ad7004d70cd2bab86f81c69ab4d8c209ef2c0fd491eb95fc2f9e312213a77688` （与已提交 `.export.tar.sha256` 完全一致）; (b) 0 diffs（1455/1455 条目，whitespace 归一化后与 `git ls-tree -r` 逐条一致）; (c) `verdict: PASS / total files: 1455 / mismatches: 0 / RC=0` |
| **判据** | **CONFIRMED** — 三个独立检查全部通过；导出校验和可复算、manifest 与 git 树逐条一致、工具裁定 PASS 无错配 |

### 要求 4 · 实现者 + 复核者的 claim-versus-commit 一致性检查

| 字段 | 值 |
|---|---|
| **要求原文** | "A claim-versus-commit consistency check, by both the executor and a reviewer." (GATE-LEDGER:194) |
| **独立测量方法** | 核实两方报告存在于磁盘；阅读内容确认非实现者独立测量 |
| **原始输出** | Executor: `dc-warn/out/package-shell-adjudication/REPORT.md` — 存在，248 行，含 [EXEC]/[CODE] 标记的自主测量。Reviewer: `dc-warn/out/verify-eec707b9/REPORT.md` — 存在，39 行，5/5 CONFIRMED，明确声明 "claim-versus-commit check by someone other than the implementer — Met by this report"。两份报告均为非实现者独立出品 |
| **判据** | **CONFIRMED（含记录位置缺陷）** — 两份报告均存在且均为非实现者独立检查。但两份报告全部在 `dc-warn/out/` scratch 内，**不在仓内** (`docs/architecture/evidence/condition-4-entry-gate/README.md:102-104` 自认 "Requirement 4's evidence has no in-repo location")。记录位置缺陷不改报告的存在性和独立性；此即灾害报告 R2.1 所指的「真正的洞」 |

---

## 二、2aadcb69（contract 3 conditions 1/2）

### 要求 1 · 可追溯的 commit hash

| 字段 | 值 |
|---|---|
| **要求原文** | "A traceable commit hash." (GATE-LEDGER:189) |
| **独立测量方法** | `git rev-parse --verify 2aadcb69^{commit}` + `^{tree}` |
| **原始输出** | commit=`2aadcb6978d81705379892d2b382671b3458e753`; tree=`91151878a6ba0890fda27eddb438d277ac8e9555` |
| **判据** | **CONFIRMED** — 哈希解析成功；tree 与 MAPPING.md 和已提交 R2-worktree.txt 内编号一致 |

### 要求 2 · 干净工作树证明

| 字段 | 值 |
|---|---|
| **要求原文** | "A clean working-tree proof for that hash." (GATE-LEDGER:191) |
| **独立测量方法** | `git worktree add --detach /tmp/r22-2aadcb69-wt.XXXXXX 2aadcb69` → `git status --porcelain` |
| **原始输出** | HEAD=`2aadcb6978d81705379892d2b382671b3458e753`; tree=`91151878a6ba0890fda27eddb438d277ac8e9555`; `git status --porcelain` 输出空（0 行） |
| **判据** | **CONFIRMED** — 独立重建的 detached worktree 零 porcelain 行，与已提交 `2aadcb69.R2-worktree.txt` 一致 |

### 要求 3 · 从该 commit 独立导出的内容/校验和

| 字段 | 值 |
|---|---|
| **要求原文** | "The candidate content/checksums, exported independently from that commit or from an explicit freeze archive - not read out of a live worktree." (GATE-LEDGER:192-193) |
| **独立测量方法** | (a) `git archive --format=tar 2aadcb69 \| sha256sum`; (b) `diff <(git ls-tree -r 2aadcb69 \| awk … \| sort) <(manifest \| awk … \| sort)`; (c) `bun run gate:verify -- 2aadcb69` |
| **原始输出** | (a) `38b6d43a3418d8602eeaa6fed381f06ff3eee7a29ba4292f41cb5a87a2a9a2e0` （与已提交 `.export.tar.sha256` 完全一致）; (b) 0 diffs（1455/1455 条目）; (c) `verdict: PASS / total files: 1455 / mismatches: 0 / RC=0` |
| **判据** | **CONFIRMED** — 三个独立检查全部通过 |

### 要求 4 · 实现者 + 复核者的 claim-versus-commit 一致性检查

| 字段 | 值 |
|---|---|
| **要求原文** | "A claim-versus-commit consistency check, by both the executor and a reviewer." (GATE-LEDGER:194) |
| **独立测量方法** | 核实两方报告存在于磁盘；阅读内容确认非实现者独立测量 |
| **原始输出** | Executor: `dc-warn/out/npm-determinism/REPORT.md` — 存在，92 行，含自主测量的 [EXEC] 标记。Reviewer: `dc-warn/out/verify-2aadcb69/REPORT.md` — 存在，247 行，5 项技术主张全部 CONFIRMED，明确标注 "claim-versus-commit check … Met by this report" |
| **判据** | **CONFIRMED（含记录位置缺陷）** — 两份报告均存在且均为非实现者独立出品。但全部位于 `dc-warn/out/` scratch 内，不在仓内。此与 eec707b9 的缺陷相同 |

---

## 三、与入库 README 相矛盾 / 不一致之处

### 3.1 GATE-LEDGER 与 MANAGEMENT-RULING-137 直接矛盾（灾害报告 R1.1 所指，未修复）

| 文件·行 | 内容 |
|---|---|
| `GATE-LEDGER.md:42` | `**...and the entry now SATISFIES the entry gate (all four requirements met)**` |
| `GATE-LEDGER.md:75` | `**Condition 4's entry gate is now SATISFIED.**` |
| `MANAGEMENT-RULING-137.md:17` | `**Contract 3 condition 4: STILL NOT SATISFIED.**` |
| `MANAGEMENT-RULING-137.md:33-35` | `Until condition 4 is satisfied and a later explicit ruling says otherwise: do not nominate, do not declare a pass, and do not change its status.` |

**性质**：GATE-LEDGER 写入 SATISFIED 的提交 `b9c090ab` 基于 `5a8f19e6`（不含 RULING-137）。RULING-137 在 `46b83a20` 落主线（先于合并），但合并者未核查裁定时间线矛盾——灾害报告将此定性为「影响 A · 主线失去自洽」。**截至本检查时，GATE-LEDGER:42,75 的 SATISFIED 措辞仍然在线、未经修复。**

### 3.2 GATE-LEDGER 条件 1/2 仍标 `in-flight`，但其要求 1–3 已被 R2/R3 包满足

GATE-LEDGER:39-40 将条件 1/2 写为 `in-flight`。本检查确认 2aadcb69 的 entry gate 四要求均已满足（要求 4 的两份报告存在且已读），仅 req 4 的记录位置在 scratch。账簿状态 `in-flight` 与已完成工作之间的落差应由 R2.3（更新台账）解决。

### 3.3 MAPPING.md 内的 review ID 不解析为本地 commit

`docs/architecture/evidence/entry-gate-r2r3/MAPPING.md:23/25`：
- `02507c97` → `fatal: Not a valid object name`（该仓库无此对象）
- `e32fd55e` → `fatal: Not a valid object name`

condition-4-entry-gate README:106-108 自认 "do not resolve to commits in this repository — they name review seats/reports, not objects"。**这不是错误但具有误导性**：门禁方法段要求 "traceable commit hash"，MAPPING.md 在同一表格里混用了 commit-full-id（能解析）和 review-seat-id（不能解析），两者形态相同，读者无法仅凭结构区分。

### 3.4 SHA256SUMS 自引用行

`entry-gate-r2r3/SHA256SUMS.txt` 自引用行哈希为 `e3b0c442…`（空字符串的 SHA-256），`sha256sum -c` 对该行报告 FAILED。condition-4-entry-gate README:114-118 已记录，不另修。

---

## 四、INCONCLUSIVE 项

**本报告无 INCONCLUSIVE 项。** 所有四个需求的测量均可在本环境独立复算：
- 要求 1（commit hash）：`git rev-parse` 直接解析
- 要求 2（干净工作树）：`git worktree add --detach` + `git status --porcelain` 在本仓库完成
- 要求 3（独立导出）：`git archive` + `sha256sum` + manifest diff + `bun run gate:verify` 均在本仓库完成
- 要求 4（两方报告）：四份报告均在 `dc-warn/out/`（fuse.sshfs 挂载）上存在且可读

唯一未复算项：未在 `52044ed1`/`2bd609b9` 历史提交上重跑测试套件——此即 verify-eec707b9 报告自身标明的同一限制。该限制不改变因果关系测量（relative+emit → exit 0 → `not.toBe(0)` 失败），本席认同核实者的判断：**限制不构成 INCONCLUSIVE**。

---

## 五、本席实际跑过的命令（完整清单）

```bash
# —— 仓库环境 ——
cd /home/losses/Development/tq-workspace/boring
git rev-parse HEAD                          # f6f7e3d3
git merge-base --is-ancestor eec707b9 HEAD  # yes
git merge-base --is-ancestor 2aadcb69 HEAD  # yes
git merge-base --is-ancestor 1704c3db HEAD  # yes

# —— 要求 1（两 commit） ——
git rev-parse --verify eec707b9^{commit}    # eec707b9b09ccabdc7541b74174c6d8cf1e9ef0e
git rev-parse --verify eec707b9^{tree}      # 0a61e32a…
git rev-parse --verify 2aadcb69^{commit}    # 2aadcb6978d81705379892d2b382671b3458e753
git rev-parse --verify 2aadcb69^{tree}      # 91151878…

# —— 要求 2（两 commit） ——
WT=$(mktemp -d /tmp/r22-eec707b9-wt.XXXXXX)
git worktree add --detach "$WT" eec707b9
git -C "$WT" rev-parse HEAD                # eec707b9…
git -C "$WT" rev-parse HEAD^{tree}         # 0a61e32a…
git -C "$WT" status --porcelain            # (空 — 0 行)
git worktree remove "$WT"

WT=$(mktemp -d /tmp/r22-2aadcb69-wt.XXXXXX)
git worktree add --detach "$WT" 2aadcb69
git -C "$WT" rev-parse HEAD                # 2aadcb69…
git -C "$WT" rev-parse HEAD^{tree}         # 91151878…
git -C "$WT" status --porcelain            # (空 — 0 行)
git worktree remove "$WT"

# —— 要求 3（两 commit） ——
git archive --format=tar eec707b9 | sha256sum
# ad7004d70cd2bab86f81c69ab4d8c209ef2c0fd491eb95fc2f9e312213a77688
# matches eec707b9.export.tar.sha256

git archive --format=tar 2aadcb69 | sha256sum
# 38b6d43a3418d8602eeaa6fed381f06ff3eee7a29ba4292f41cb5a87a2a9a2e0
# matches 2aadcb69.export.tar.sha256

# Manifest 逐条对账 (0 diffs, 1455/1455):
diff <(git ls-tree -r eec707b9 | awk '{printf "%s\t%s\n", $3, $4}' | sort) \
     <(awk '{printf "%s\t%s\n", $1, $2}' docs/.../eec707b9.R3-manifest.txt | sort)
diff <(git ls-tree -r 2aadcb69 | awk '{printf "%s\t%s\n", $3, $4}' | sort) \
     <(awk '{printf "%s\t%s\n", $1, $2}' docs/.../2aadcb69.R3-manifest.txt | sort)

# —— 仓库门禁 ——
bun run gate:verify -- eec707b9           # PASS, 1455/0, RC=0
bun run gate:verify -- 2aadcb69           # PASS, 1455/0, RC=0
```

报告文件读取（全部通过 `read` 工具完成）：
- `docs/architecture/GATE-LEDGER.md` (834 行)
- `docs/architecture/MANAGEMENT-RULING-137.md` (38 行)
- `docs/architecture/evidence/condition-4-entry-gate/README.md` (134 行)
- `docs/architecture/evidence/entry-gate-r2r3/README.md` (57 行)
- `docs/architecture/evidence/entry-gate-r2r3/MAPPING.md` (53 行)
- `dc-warn/out/package-shell-adjudication/REPORT.md` (248 行)
- `dc-warn/out/verify-eec707b9/REPORT.md` (39 行)
- `dc-warn/out/npm-determinism/REPORT.md` (92 行)
- `dc-warn/out/verify-2aadcb69/REPORT.md` (247 行)