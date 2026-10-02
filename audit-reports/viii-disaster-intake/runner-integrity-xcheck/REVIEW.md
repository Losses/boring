# 冻结运行器完整性契约审计（独立审阅 / 异模型 / 只读）

- 日期：2026-09-29
- 对象：`boring-wt-architecture/out/integration-a3-evidence/exclusive-runner/`（7 个冻结件）
- 审阅问题：PIT-244（plan 补位参接线）与 PIT-245（身份动态派生）两次改动，**有没有削弱「能证明日志/证据未被篡改」这一完整性契约**
- 结论：**完整性契约未削弱**（明细见 §5）；同时如实记录 12 项**与这两次改动无关的既有缺口**（§6 A–L，其中 A/B/E 风险最高：无换行尾部追加不被检出、密封无密钥可重封、`child-evidence/**` 不在密封范围）
- 本审阅只读：未写 `boring-wt-architecture/**`、`publication-staging/**`、`tiqian/**`；未 git 操作；未跑 verify/selftest；全部篡改实验在 `out/runner-integrity-xcheck/work/` 的 `cp -a` 副本上完成（收尾已删）。

---

> **plan 修订链（我自行重放验证，不引用报告数值）**：`b83a636d…`（原始冻结，8480 B）→ `f0b9dddd…`（PIT-244：用该报告自带的 `option-c.plan.diff` 在它自带的基线上 `patch -p0 --fuzz=0` 重放，rc=0，产物与 PIT-245 备份的改动前字节 `cmp` 逐字节相同，8803 B）→ `42517f84…`（PIT-245，9440 B）。**共两次改动，与任务描述一致**；顺带发现 PIT-244 报告里写的改后哈希 `72eb56a6…` 与磁盘上任何字节都不符（详见 §6 L）。

## 1. 密封机制到底是什么

**算哈希的文件是 `run-exclusive.sh`（唯一的密封写入者），`check-log-integrity.sh` 只做重算与比对。**

`run-exclusive.sh` 的密封段（第 248–255 行，全部阶段与 `cleanup_reap` 之后执行）：

```bash
if ls "$STAGES"/* >/dev/null 2>&1; then
    sha256sum "$STAGES"/* | sed "s#  $STAGES/#  #" | sed 's/^/stage-evidence /' >>"$HARNESS_LOG"
fi
sealed_sha=$(sha256sum "$HARNESS_LOG" | cut -d' ' -f1)
printf 'harness end marker sha256=%s\n' "$sealed_sha" >>"$HARNESS_LOG"
```

两层密封：

1. **逐文件清单**：对 `$RUN/stages/*` 逐个 `sha256sum`，以 `stage-evidence <sha256>  <basename>` 写进 `harness.log` 自己。
   - 被哈希的文件**只有**每个 stage 的 4 个产物，由 `run_stage()` 写：`<name>.command`（第 179 行，`printf '%q ' "$@"`）、`<name>.stdout`/`.stderr`（第 181 行，`setsid "$@" >… 2>…`）、`<name>.status`（第 186 行）。
   - stage 名 = `step-$(printf '%s' "$line" | cksum | cut -d' ' -f1)`（第 228 行）——**名字就是该 plan 行内容的 CRC**。
   - `<name>.command` 存的是 `printf '%q '` 后的**原始 plan 行文本**（`run_stage` 的第 3 个参数就是 plan 行本身，经 `eval "$2"` 执行），所以"哪个 plan 行产生了这个 stage"在密封件里可复原（见 §3 末）。
2. **整份日志前缀哈希**：`sealed_sha = sha256(harness.log 此刻全文)`，此刻全文**已含**上面刚写入的清单行；随后把该哈希作为结束标记追加。因此清单行本身也被前缀哈希覆盖，改清单会被第二层抓住。

`check-log-integrity.sh`（未改过，`bebd0cf9…`）的校验顺序：

- 第 27–37 行：取最后一条结束标记；要求**标记之后没有内容**（`wc -l` 比较行号）。
- 第 38–43 行：`recorded` 与 `sha256(第 1..last-1 行)` 必须相等（这一层同时保护清单行）。
- 第 47–63 行：`$STAGES/*` 的**集合**必须与清单完全相等（多文件→`added:`、少文件→`deleted:`），且**哈希逐一相等**（不等→打印 diff 并点名）。退出 0 仅在全部通过时给出。

**密封范围之外**（`check-log-integrity.sh` 从不枚举、任何哈希都不覆盖）见 §3。

---

## 2. 两次改动是否影响密封

### 2.1 结论先说

| 改动 | 是否在密封范围内 | 对既有 attempt 的密封校验 | 新增/减少被密封产物 | 判定 |
|---|---|---|---|---|
| PIT-244：plan 每段末尾补 `_ "$OPTION_C_ROOT"`（17 段） | **否** | **否，实测 exit 0** | 无 | 未削弱 |
| PIT-245：plan Stage 1 身份动态派生 + 条目数守卫 | **否** | **否，实测 exit 0** | 无（身份值本来就落在被封存的 Stage 1 stdout 里） | 未削弱（反而加强证据真实性） |
| wrapper 第 40 行 `( "$@" )` | 不涉及 plan，改的是被封存证据的**产出者行为** | 不适用 | 无；反而保证 `.rc`/poststate 恒定写盘 | 未削弱（加强） |

### 2.2 plan 不在密封范围内——代码级与实测双重证明

- `grep -n 'plan\|PLAN' check-log-integrity.sh` → **0 处**。校验器的输入集合只有 `<attempt>/harness.log` 与 `<attempt>/stages/*`。
- `run-exclusive.sh` 只把 plan 的**路径字符串**写进日志（第 94 行 `echo "plan=$PLAN"`），**从不哈希 plan 内容**；计划行的内容只通过 stage 名 CRC 与 `.command` 文本间接进入密封。
- **实测既有 attempt**：`attempt-20260929T180809-2918225`（18:08 起跑、18:14 封存），它的封存 `.command` 里记的是**旧身份行字面量** `compiler-pin=2159c657` / `source-reference=source-before1366`，与当前（PIT-245 之后）plan 的 `basename` 派生行**不同**：

  ```
  IDENTICAL: False      # sealed .command identity line  vs  current option-c.plan identity line
  check-log-integrity.sh attempt-20260929T180809-2918225
  INTEGRITY OK: sealed at line 30, sha 597a9e1151551d6056cd2423cd39fee86459ba3e49a5eeab04f4ba8f0adbb03a, stage manifest exact
  exit=0
  ```

  即：**这次改动已经让"当前 plan 与产生该 attempt 的 plan 不再一致"，而旧 attempt 仍然 exit 0 通过。** 我另外把 `check-log-integrity.sh` 跑遍目录下全部 212 个带 `harness.log` 的 attempt：**150 通过 / 62 失败，62 个失败全部是 selftest 自造的负控**（`plan-a.txt` 30 个=故意在标记后追加 `zombie writer append`；`plan-b/c/d.txt` 29 个=故意增删 stage 文件；`plan-debug` 2 个=无结束标记的历史脚手架；`oc-fail.plan` 1 个），**没有任何一个失败 attempt 使用过 `option-c.plan`**（实测 `grep -l 'option-c\.plan' attempt-*/harness.log` = 0）。详见 `evidence/batch-integrity.txt`。

### 2.3 PIT-245 与"身份是否被封存"

身份三行（`compiler-pin=` / `source-reference=` / `manifest-sha256=`）由 Stage 1 的 inner 脚本打印，经 wrapper `cat` 进 wrapper stdout，而 wrapper stdout 就是 `<name>.stdout` → **在清单里、被哈希、被校验**。实测 witness attempt 的 `stages/step-2320672395.stdout` 前 4 行正是：

```
compiler-pin=2159c657
source-reference=source-before1366
manifest-sha256=11e642e846361952611eb5c2068b1b87a69d46f7618019f6fa1793831cc51a47
[
```

所以 PIT-245 把**假身份**换成**真身份**，且这些值本来就在密封范围内：对密封机制零影响，对"身份可信度"是正向加强。守卫 `[ "$actual" = "${EXPECTED_MANIFEST_ENTRIES:-1431}" ]` 失败时 `exit 9`，wrapper 仍写 `.rc` 并继续跑 poststate，非零 rc 照旧阻断下游（fail-closed），不会少写任何被封存产物。

**残留（非本次削弱，属既有口径）**：`compiler-pin=$(basename "$OPTION_C_ROOT")`、`source-reference=$(basename "$SOURCE_MANIFEST")` 仍是对**调用者传入路径的取名**，不是内容锚——把任意一棵旧树复制成名为 `execution-option-c-coord` 的目录即可得到同样的身份串；条目数守卫不设 `EXPECTED_MANIFEST_ENTRIES` 时默认 1431，只能分辨"非 1431 条"。真正的锚只有 `manifest-sha256`（清单内容哈希）。

### 2.4 wrapper 子壳化：源码论证 + 反例实验

改动（与冻结前字节镜像 `d11801e54decbbfb…` 逐字比对，**只差这一行**）：

```diff
-"$@" >"$OUTDIR/$NAME.stdout" 2>"$OUTDIR/$NAME.stderr"
+( "$@" ) >"$OUTDIR/$NAME.stdout" 2>"$OUTDIR/$NAME.stderr"
```

机理（源码行号）：第 40 行若不加子壳，`"$@"` 是**在 wrapper 自己的 shell 里**执行的；当传入的命令是 shell 内建（selftest 的 `oc-fail.plan` 正是字面量 `exit 7`、真 plan 也不可能排除内建），`exit` 直接终止 **wrapper 本身**，于是第 41 行起的 `rc=$?`、第 42 行 `.rc`、第 44–45 行 stdout/stderr 回放、第 47–50 行 poststate 与 `.poststate-rc` **全部被跳过**——违反 wrapper 头注释与 plan 第 25 行承诺的 "ALWAYS run (also after failures)"。加子壳后 `exit` 只退出子壳，`$?` 传播不变（子壳退出码=最后一条命令的退出码），第 41–58 行**恒定执行**。

反例实验（在副本上，`evidence/wrapper-transcript.txt` 原文；对照件与冻结前字节镜像 sha256 相同 = `d11801e5…`）：

| 输入命令 | wrapper 版本 | 落盘产物 | `.rc` | `.poststate-rc` | wrapper 退出码 |
|---|---|---|---|---|---|
| 内建 `exit 7` | **修复后 `( "$@" )`** | `.rc/.poststate/.poststate-rc/.stdout/.stderr` **全在** | `7` | `0` | `7` |
| 内建 `exit 7` | 修复前 `"$@"` | **`.rc`/`.poststate`/`.poststate-rc` 全部缺失** | `<MISSING>` | `<MISSING>` | `7` |
| 真 plan 形态 `bash -c 'exit 7' _ <root>` | 修复后 | 全在 | `7` | `0` | `7` |
| 真 plan 形态 | 修复前 | 全在 | `7` | `0` | `7` |

即：**修复对真实 plan 输入是行为等价的，只把"原本违反自身规范"的内建命令输入改回按规范执行**；原始 rc 传播不变（两种版本退出码都是 7），下游阻断语义不变；被封存的 `<name>.status`（= wrapper 退出码）与 `<name>.stdout` 不受负面影响。`selftest.sh` 第 200 行的 `want 1→2` 是同一改动的断言侧对齐：失败路径下 poststate 摘要出现 2 次（python `print` + wrapper `cat` 报告文件），通过路径（第 192 行 `oc-pass`）本来就写 `want 2`——不是放宽门禁，`option-C original rc preserved` 仍严格期望 7（已在副本上确认两条判据的可满足性）。

---

## 3. `stage-evidence` 覆盖范围

对参照 attempt `attempt-20260929T180809-2918225` 的逐项枚举见 `evidence/seal-scope.txt`。

**被逐文件哈希（在清单里、被校验）**：`$RUN/stages/step-<cksum>.{command,status,stdout,stderr}`——4 个/段，该 attempt 共 16 个文件/4 段。**每个 stage 的 command/status/stdout/stderr 四类产物全覆盖**（问题所问的"是否覆盖该段全部产物"：**覆盖**）。

**被前缀哈希间接覆盖（不在清单里、但改了就破坏结束标记哈希）**：`harness.log` 头 6 行（`run=`/`root=`/`child_evidence_dir=`/`external_dir=`/`plan=`/`start=`）、每段 `status=` 行、`end=`/`failed_stage=`/`last_status=`、以及清单行本身。

**不在密封范围内**（无任何哈希覆盖，校验器也不枚举）：

| 未封存项 | 参照 attempt 规模 | 是什么 / 风险 |
|---|---|---|
| `$RUN/child-evidence/**` | **57 个文件**（`run-*/<NNNN>/{record.json,stdout.bin,stderr.bin}`） | plan 第 51–57 行把 driver 的 **33 条 child records** 定义在这里。**这是最大的缺口**：逐子进程的原始证据（含 stdout/stderr 字节）可任意增删改而无从检出；封存的 Stage 3 stdout 只有 driver 自己的汇总。**实测**：改 `child-evidence/**/record.json` 后 `check-log-integrity.sh` 仍 `INTEGRITY OK`，exit 0（`evidence/seal-scope.txt` 末段 CASE K）。 |
| `$RUN/option-c/**` | 20 个文件 | wrapper 的私有副本：inner 的 `.stdout`/`.stderr`（**分流原件**）、`.rc`（**原始 rc**）、`.poststate`/`.poststate-rc`、`tmpdir/`。封存 stdio 是它们的拼接，原件不在密封内（风险见 §6 G/J）。 |
| `$RUN/plan-errors.txt` | 该 attempt 无 | plan 校验失败的错误原文写在这里（`run-exclusive.sh:235`），在 attempt 根而不在 `stages/`。 |
| `../.latest-run` | 每次都覆写 | 共享可变指针（PIT-243），不可当证据；只有封存前缀里的 `run=` 行可信。 |
| `../external-*/` | 自测穿越目标 | 与证据无关。 |
| **执行根侧产物** | 大 | `$OPTION_C_ROOT/toolchain-resolution.txt`、`out/`、`target/`、生成树等：**在 attempt 目录之外**，密封完全够不到。 |
| plan 文件、7 个冻结件自身 | — | 它们的哈希不被记录（见 §6 D）。 |

**风险判定**：`child-evidence/**` 与"执行根侧产物不封存"是**实质性**风险——它们正是"运行读了什么、子进程各自输出什么"的原始证据；但这些缺口**不是这两次改动造成的**：`run-exclusive.sh`（唯一的密封写入者）与 `check-log-integrity.sh` 与冻结前**逐字节相同**，密封从来只 glob `$STAGES/*`。PIT-244 的真实影响是让 Stage 0 起**第一次真正跑起来**（改前 `cd ""` 必败，attempt 里根本不会产生 child-evidence 与根侧产物），因此**暴露面变大而机制未变**。建议（不在本次范围，仅记录）：把 `$RUN/child-evidence` 与 `$RUN/option-c` 一并纳入清单，或为它们各写一份聚合 MANIFEST 进 `$STAGES/`。

**一处 plan 自述与实现不符**（PIT-244 之前就存在，改后才显形）：plan 第 34–36 行称"npm/node/tar/python3/haxe/kotlinc 的解析路径 **recorded into sealed stage evidence**"，但 Stage 0 的 inner 脚本是 `{ … } > toolchain-resolution.txt`——路径写进 `$OPTION_C_ROOT/toolchain-resolution.txt`（attempt 目录之外），**stdout 里一个字都没有**。实测封存的 env-guard stage stdout 只有 90 字节 = 两行 poststate 摘要（`evidence/seal-composition.txt`）。即这条工具链 provenance 事实上**未被封存**。属"文档承诺 > 实现"，不是密封机制被削弱。

---

## 4. 篡改可检测性（实验，全部在 `/home/losses/Development/tq-workspace/out/runner-integrity-xcheck/` 的 `cp -a` 副本上）

方法：`cp -a` 真实 attempt 得到 `work/attempt-base`，每个 case 再 `cp -a` 一份后施加单一改动，然后 `bash work/check-log-integrity.sh <case>` 取退出码与输出。需求中的三个实验（a/b/c）与四个补充对照。原始记录见 `evidence/tamper-transcript.txt`、逐 case 输出见 `evidence/case-*.out`。

| # | 篡改内容 | 退出码 | 校验器输出关键行 |
|---|---|---|---|
| control | 无（对照） | **0** | `INTEGRITY OK: sealed at line 30, sha 597a9e11…, stage manifest exact` |
| **(a)** | 在某段 `.stdout` 末尾追加 1 字节（`step-2320672395.stdout`） | **1** | `INTEGRITY FAIL: stage evidence hash changed` + `> 65bd307c8ad1fdd83e9a95e2efe220d0557b9d60c934518e22670e82bbc5d243  step-2320672395.stdout` / `< d575aec2aa2883ebf96464e35b448ce3376461811a73c827770e6bab8244afcd  step-2320672395.stdout`（**点名文件**） |
| **(b)** | 某段 `.status` 由 `1` 改成 `0`（`step-737716045.status`） | **1** | `INTEGRITY FAIL: stage evidence hash changed` + `2d1 < 4355a46b19d348dc…  step-737716045.status` / `8a8 > 9a271f2a916b0b6e…  step-737716045.status`（**点名文件**） |
| **(c)** | 删除某段 `.stderr`（`step-2119220958.stderr`） | **1** | `INTEGRITY FAIL: stage evidence set differs from manifest` / `--- manifest only:` / `deleted: step-2119220958.stderr`（**点名文件**） |
| D | 结束标记后追加一整行（控制项） | **1** | `INTEGRITY FAIL: content after the end marker (lines 31..31)` |
| E | 新增清单外 stage 文件 `step-999999999.stdout` | **1** | `INTEGRITY FAIL: stage evidence set differs from manifest` / `added: step-999999999.stdout` |
| **I** | 结束标记后追加**不以换行结尾**的字节 `TAMPERED-EVIDENCE-NO-NEWLINE` | **0** | `INTEGRITY OK: sealed at line 30, sha 597a9e11…, stage manifest exact` ← **未检出（缺口，见 §6 A）** |
| **G** | 篡改 `.status` + `.stdout`，再按 `run-exclusive.sh` 的算法**重算清单与标记** | **0** | `INTEGRITY OK … sha e0445152b395d4fa…` ← **未检出（无密钥，可重封，见 §6 B）** |
| H | 把已封存 attempt **整体移走**后校验 | **0** | `INTEGRITY OK …`，而日志第 1 行 `run=` 仍指旧路径 ← **未检出（路径未绑定，见 §6 C）** |
| **K** | 只改**未封存面**：`child-evidence/**/record.json` 覆写 + `option-c/{identity.rc 改写, driver-verify.poststate 删, env-guard.rc 删}` | **0** | `INTEGRITY OK: sealed at line 30, sha 597a9e11…` ← **未检出（范围外，见 §3/§6 E）** |

**需求 (a)(b)(c) 三条全部满足**：均**非零退出**且**输出点名被改/被删的文件**。

---

## 5. 判定

### 判定：**完整性契约未削弱**

三条独立依据：

1. **两次改动都不在密封输入集合内**：`check-log-integrity.sh` 零处引用 plan（grep 证明），`run-exclusive.sh` 只记 plan 路径不记内容；密封的全部输入是 `<attempt>/harness.log` + `<attempt>/stages/step-*`。
2. **对既有 attempt 无失效**：实测既有 attempt（其封存 `.command` 记录的正是 PIT-245 改掉的旧身份行）在当前 plan 下仍 `INTEGRITY OK` exit 0；212 个 attempt 的批量扫描中没有任何一个失败来自 `option-c.plan`。
3. **被密封产物的种类与数量未减少**：PIT-244 只改 argv 接线（`$1` 由空变为 `$OPTION_C_ROOT`），不触碰 `run_stage` 写文件的任何一行；PIT-245 只改 Stage 1 的内层脚本文本（其输出本来就落在被封存的 stdout 内），并新增一条 fail-closed 守卫；wrapper 子壳化经反例实验证明是**加强**（改前内建 `exit` 会让 wrapper 跳过 `.rc` 与 poststate，改后恒定执行），对真实 plan 输入行为等价。

**一行结论：两次改动都落在密封范围之外（plan 不被哈希、校验器不读 plan），既有 attempt 实测仍 exit 0 通过，被密封产物一个未少，wrapper 子壳化反而补上了「失败后 post-state 必须运行」的缺口——完整性契约未削弱；真正的既有缺口是无换行尾部追加不被检出、密封无密钥可重封、以及 `child-evidence/**` 不在密封范围，这三项均与本次两次改动无关。**

---

## 6. 其它可能削弱证据可信度的设计（含本次新发现，均与两次改动无关）

**A.（新发现，可修，优先级最高）"标记之后无内容"检查可被无换行追加绕过。**
`check-log-integrity.sh:33-37` 用 `wc -l` 比较行数；`wc -l` 不计算**没有换行结尾**的末行，于是"在最后一行的 `\n` 之后追加任意字节"既不增加行数、又不改变第 1..last-1 行的哈希，校验直接通过（实验 I，exit 0）。这使该文件自称的 "nothing follows the marker" 不成立，也让"追加一条伪造的 `post-state: … 0 failures`"成为一条静默通道。fix：改用字节长度（`wc -c`）或直接校验 `sha256(整个文件) == prefix_sha ⊕ 标记行` 的精确等式。

**B.（新发现，机制级）密封是**无密钥**校验和，可被完整重封。**
`sealed_sha` 没有 HMAC/签名/时间戳/外部锚；拿到 attempt 目录写权限的人只要按同一算法重算清单与标记即可（实验 G，exit 0）。因此它证明的是"**这份文本自封存以来没被朴素地改过**"，**不是**"任何人都改不了"，也不是"这份证据出自某次特定运行"。现有外部锚只有 `.latest-run`（可写、每跑必覆写）与 attempt 目录名（不在密封内）。若要抗有写权限的篡改者，需要密钥签名或写入后不可变/可审计的存储。

**C.（新发现）attempt 与其路径未绑定。**
`harness.log` 第 1 行 `run=` 记了 attempt 的绝对路径，但**校验器不比对**：把一份通过校验的 attempt 整体复制/改名后仍 exit 0（实验 H），于是可以把它当作"另一个 attempt 目录"的证据呈现，且 `run=` 与 `plan=` 的陈旧值不会报警。fix：校验 `<attempt>` 的 `pwd -P` 与日志 `run=` 是否一致。

**D. 运行器来源（provenance）未密封。** 密封不记录 `run-exclusive.sh`、wrapper、`option-c-poststate.py`、`option-c.plan` 的哈希；`<name>.command` 里只有 plan 行的**文本**（stage 名是它的 CRC），plan 的注释行、空行、以及"这份 plan 文件本身"都不在密封内。后果：密封能证明"证据文本未变"，不能证明"这是冻结运行器跑出来的"。**对本审计的意义**：想核"某 attempt 是否由某个 plan 修订产生"，只能拿封存 `.command` 的末字段与 plan 行逐行比对——**可复原，但门禁不强制**（§2.2 的 witness 就是把这条通道走通的例子）。

**E. 关键原始证据留在密封之外。** `child-evidence/**`（driver 的 33 条 child records 的 `record.json`/`stdout.bin`/`stderr.bin`）与 `$RUN/option-c/**`（分流原件、原始 `.rc`、poststate 文件）可任意增删改而不被检出（实验 K，exit 0）。封存的 Stage 3 stdout 只有汇总。这是本次发现中**最实质**的覆盖缺口（细节与修法见 §3）。

**F. plan 自述与实现不符。** Stage 0 注释宣称工具链解析路径进了"sealed stage evidence"，实际只写进 `$OPTION_C_ROOT/toolchain-resolution.txt`（attempt 外、不封存）；封存 stdout 只有 90 字节 poststate 摘要。**看似被密封的 provenance 其实没封**。

**G. 封存 stdio 是拼接，流边界不可复原。** `<name>.stdout = [inner stdout][inner stderr][poststate 报告 ×2]`，**无分隔符**；实测 `69373 + 305 + 90 = 69768` 精确成立（`evidence/seal-composition.txt`）。因此"某行来自 stdout 还是 stderr"只能靠 attempt 内**未封存**的 `option-c/*.stdout|stderr`，而那份不受完整性保护；审查者若只看封存件，无法排除"把 stderr 输出冒充 stdout"这类拼接层面的混淆。另：poststate 报告重复两遍（python `print` + wrapper `cat`），是 `selftest.sh:192/200` 的 `want 2` 所依赖的实现细节。

**H. 未检查的写与读（静默降级）。** wrapper 第 38 行 `mkdir -p "$TMPDIR"`、第 42 行 `>…rc`、第 44/45/49 行 `cat …` 全部**未判返回码**：`cat` 失败只会让命令输出从封存 stdout 里消失，而 stage 仍然"成功"（退出码不由它们决定）。`run-exclusive.sh:251` 的 `ls "$STAGES"/* >/dev/null 2>&1` 吞掉一切错误——**零个 stage 的 attempt 会以"空清单"封存**，而校验器对"空清单 vs 空 stages"给出 `INTEGRITY OK`（空集相等）。这些都属"出错不报、静默弱化"，不是本次改动引入的。

**I. stage 名 = plan 行 CRC 带来两个边角。（1）** plan 里出现**两行完全相同**的命令时，同名 stage 的 4 个文件被 `>` 截断覆写，前一次的运行证据**静默丢失**（当前 17 段互不相同，未触发）。**（2）** `sha256sum` 对含换行/反斜杠的文件名会加 `\` 前缀并转义，`sed "s#  $STAGES/#  #"` 只替换首次出现；当前 stage 名恒为 `step-<digits>` 故不可达，但该格式对"名字含特殊字符"的产物不稳健。

**J. `.status` 混淆了原始 rc 与 poststate rc。** wrapper 第 52–57 行：原始 rc 非零则退出 rc；否则退出 poststate rc；否则 0。因此封存的 `.status` 非零**无法区分**"命令失败"与"命令成功但 post-state 失败"；区分它们要读未封存的 `option-c/<name>.rc`（原始 rc）。方向仍 fail-closed（两者都阻断下游），只是**归因**证据不在密封内。

**K. `.latest-run` 是共享可变指针**（PIT-243 已记）：每次运行覆写、不受完整性保护，**不得**当证据引用；唯一可信的自指是封存前缀里的 `run=` 行（且它也没被校验器与真实路径比对，见 C）。

**L.（新发现）冻结 plan 的"改后哈希"在报告里就是错的，而密封对此无能为力。**
`dc-warn/out/option-c-plan-fix/REPORT.md` §3 写"修复后 plan sha256 = `72eb56a6…`"，但用**该报告自带的 diff** 在**该报告自带的基线**（`b83a636d…`）上重放得到的是 `f0b9dddd…`——而它正是 PIT-245 备份下来的改动前字节（`cmp` 逐字节相同）。磁盘上找不到任何哈希为 `72eb56a6…` 的 plan（在 `dc-warn/out` 全量搜索无命中）。即：**plan 确实只改过两次，但 PIT-244 报告的哈希数字是错的**。危害不在运行（字节链本身自洽、可用 diff 重放复原），而在**"这批冻结 plan 到底是哪些字节"只能靠报告里的散文与哈希来追**——而 plan 既不被 `run-exclusive.sh` 哈希、也不被 `check-log-integrity.sh` 读取，密封无法为它提供任何锚。修法同 D：把 plan（以及运行器 7 件）的 sha256 记进 attempt 的封存前缀（例如 `plan_sha256=` 行），让"某 attempt 由哪份 plan 产生"成为**被密封的事实**而不是靠人比对 `.command`。

---

## 7. 证据清单与复现命令

同目录 `evidence/`：

| 文件 | 内容 |
|---|---|
| `hashes.txt` | 7 个冻结件的实测 sha256 + 冻结前镜像 sha256 + plan 三代哈希与"plan 不被记录"说明 |
| `plan-revision-chain.txt` | plan 修订链的重放验证（`b83a636d` → `f0b9dddd` → `42517f84`，含 `patch --fuzz=0` rc=0、与 PIT-245 备份 `cmp` 逐字节相同）与 `72eb56a6` 报告哈希的不符记录 |
| `seal-scope.txt` | 参照 attempt 的封存/未封存逐项枚举（16 个封存文件 + 57 child-evidence + 20 option-c + 其余），末尾 CASE K 原文 |
| `seal-composition.txt` | 封存 stdout 拼接的字节算术（69373+305+90=69768）与 env-guard 90 字节原文（证明工具链路径未封存） |
| `plan-binding.txt` | 封存 `.command` 的旧身份行 vs 当前 plan 身份行全文、`IDENTICAL: False`、以及该 attempt 仍 exit 0 的校验输出 |
| `tamper-transcript.txt` + `case-*.out` | control/(a)/(b)/(c)/D/E/I/J/G/H/K 的完整原文与退出码 |
| `wrapper-transcript.txt` | 内建 `exit 7` 与真 plan 形态 × 修复后/修复前 四组 `.rc`/poststate/退出码读数 |
| `batch-integrity.txt` + `batch-failures.txt` | 212 个 attempt 的批量扫描汇总与失败分组（全部为 selftest 负控/历史脚手架） |
| `case-G-forged.out` | 重封实验（篡改后自算清单与标记 → exit 0）的原文 |

复现（只读；篡改一律在 `cp -a` 副本上）：

```bash
cd /home/losses/Development/tq-workspace
R=boring-wt-architecture/out/integration-a3-evidence/exclusive-runner
W=out/runner-integrity-xcheck/work
# 1) 冻结件身份
sha256sum $R/{run-exclusive.sh,check-log-integrity.sh,option-c-poststate.py,option-c-child-records.py,option-c.plan,option-c-stage-wrapper.sh,selftest.sh}
# 2) 校验器不读 plan
grep -n 'plan\|PLAN' $R/check-log-integrity.sh   # -> 无输出
# 3) 既有 attempt 在新 plan 下仍通过
bash $R/check-log-integrity.sh $R/attempt-20260929T180809-2918225; echo "exit=$?"
# 4) 篡改实验（副本）
mkdir -p $W && cp -a $R/attempt-20260929T180809-2918225 $W/attempt-base
cp $R/check-log-integrity.sh $W/
for c in A B C; do cp -a $W/attempt-base $W/case-$c; done
printf 'X'                               >> $W/case-A/stages/step-2320672395.stdout
printf '0\n'                             >  $W/case-B/stages/step-737716045.status
rm -f                                        $W/case-C/stages/step-2119220958.stderr
for c in A B C; do bash $W/check-log-integrity.sh $W/case-$c; echo "case-$c exit=$?"; done
# 5) 无换行尾部追加（缺口 I）
cp -a $W/attempt-base $W/case-I; printf 'X' >> $W/case-I/harness.log
bash $W/check-log-integrity.sh $W/case-I; echo "case-I exit=$?"   # -> INTEGRITY OK, exit 0
```

## 8. 边界与未做

- 只读；**未**修改 `boring-wt-architecture/**`（含真实 attempt 目录与 7 个冻结件）、`publication-staging/**`、`tiqian/**`、任何 dc-warn worktree；**未** git commit/push/merge；**未**跑 verify/selftest（PIT-243：`.latest-run` 共享指针）；**未**签收。
- 全部写入只在 `out/runner-integrity-xcheck/`（副本/证据）与 `dc-warn/out/runner-integrity-xcheck/`（报告）；`out/runner-integrity-xcheck/` 收尾已删。
- 判据中"两次改动"的改动前字节取自 `dc-warn/out/option-c/freeze-apply/backup/`（freeze-apply 记录的原字节镜像，wrapper 反例件 sha256 与之一致）。plan 的三个修订态我**自行重放验证**过：`b83a636d…`（`option-c-plan-fix/backup/option-c.plan.orig`）→ 用同目录 `option-c.plan.diff` `patch -p0 --fuzz=0` 重放 → `f0b9dddd…`（与 `option-c-identity-fix/backup/option-c.plan` `cmp` 逐字节相同）→ `42517f84…`（当前冻结件）。我**未**采信 PIT-244 报告里的 `72eb56a6…`（见 §6 L）。
