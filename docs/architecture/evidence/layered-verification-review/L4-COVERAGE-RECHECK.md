# L4 覆盖面独立复核：`tests/haxe/` 的 runner 夹具是否真的不被收集

复核对象：`GAPS.md` 缺口 6 的**未复核**部分，以及它转述的审阅原始指控（缺口 6 与
`LAYERED-VERIFICATION.md` 中的对应段落）。

被复核树：`ci/collected-suite-failure-attribution` @ `5a484be5`。
实测工作树：`audit/l4-fixture-collection-coverage` @ `55445709`（已确认是 `5a484be5` 的祖先，
且 `tests/ .github/ tools/ package.json bunfig.toml boring.json` 在两个 rev 间**逐路径无差异**，
见 §A.0）。

执行边界（自述，可核）：**未执行任何 `run.sh`，未重生成任何生成树**。只做枚举、检索、计数、读回。
唯一被执行的测试是 `tests/fixture-reachability.test.ts`，该文件只 `readdirSync` 夹具目录、不 spawn 任何夹具。

标记：**[一手]** = 本次亲自跑命令读回；**[转述]** = 仅引自指控原文，本次未独立确认。

---

## 1. `run.sh` 的实际枚举与计数

| 量 | 实测值 | 口径 | 命令 |
|---|---|---|---|
| `tests/haxe` 直接子目录 | **43** | `readdir` 深度 1 | §A.1 |
| `run.sh`（递归全部） | **29** | `git ls-files 'tests/haxe/**/run.sh'` | §A.2 |
| `run.sh`（直接子 `tests/haxe/*/run.sh`） | **27** | shell glob | §A.3 |
| `run.sh`（嵌套，深度 5） | **2** | 29 − 27 | §A.2 |
| `tests/haxe` 直接子文件（非目录） | 9 | `.hxml` / `.hx` | §A.1 |

两个嵌套 runner 是：

- `tests/haxe/flow/replay/run.sh`
- `tests/haxe/source-container-policy/gen/run.sh`

**对账指控的三个数字：**

- **43 个目录 → 一致 [一手]。**
- **27 个 `run.sh` → 只在「直接子」口径下一致；实际总数是 29。** 指控少算了 2 个嵌套 `run.sh`
  （上面的两个）。如果指控的本意是「`tests/haxe/*/run.sh`」，那 27 对；但那不是 `tests/haxe/` 下
  `run.sh` 的实际总数，报告措辞未声明该口径。
- **35 个「有 runner 但无被收集测试」→ 数值一致，但指控的措辞把「runner」误当成了「`run.sh`」**，
  见 §2 的分解：35 里只有 **26** 个直接带 `run.sh`，另外 **9** 个是 **纯 `*.hxml`、根本没有 `run.sh`**。
  所以「27 个 `run.sh` 其中 35 个有 runner 无收集」这句话在算术上不自洽（27 ≠ 35），
  它是一个把两种口径混写的句子，不是一条可复核的陈述。

## 2. 常量 `RECORDED_UNCOLLECTED = 35` 与枚举结果对账

先读回**守卫自己的判据定义**（`tests/fixture-reachability.test.ts:43-55`，`[一手]`）：

- 只扫 `tests/haxe` 的**直接**子项（不含递归）；
- `hasRunner` = 目录里有名为 `run.sh` 的文件 **或** 任何以 `.hxml` 结尾的文件；
- `hasCollectedTest` = 目录里有任何以 `.test.ts` 结尾的文件；
- 计数对象 = `hasRunner && !hasCollectedTest`。

用同样的判据独立复现（§A.4 的便携 one-liner，不 import 被测文件）：

```
dirs=43 uncollected=35
```

**结论：常量 35 与本次独立枚举完全一致（=35），无差异 [一手]。**
被钉住的测试重跑也是 `2 pass / 0 fail`（§A.5）。

但必须写清这个 35 是**混合口径**，它不是「35 个 `run.sh` 夹具」：

| 类别 | 个数 | 说明 |
|---|---|---|
| 无被收集测试且直接带 `run.sh` | **26** | |
| 无被收集测试、**纯 `.hxml`**（没有 `run.sh`） | **9** | 见下 |
| **合计（=常量 35）** | **35** | |
| 带 `run.sh` 但**已被收集**（不计入） | 1 | `rust-resident-dataclass` |

那 9 个纯 `.hxml` 成员（不在指控所说的「35 个 `run.sh`」之内）：

```
flow
kotlin-local-presence-consumer
kotlin-staticfn-prepared-init
local-presence
source-container-policy
swift-package-shell-emit
try-tail
ts-nullable-lowering
ts-template-newline-escape
```

算数自检：`26 + 9 = 35`；直接子 `run.sh` 侧 `26 未收集 + 1 已收集 = 27`。[一手]

`dc-promoted-eval` **确实在这 35 之内**（且属于带 `run.sh` 的 26 个）[一手]，指控这一句成立。

## 3. CI 中是否有任何 job 执行这些 `run.sh`

### 3.1 指控给出的那条命令：确认为空

| 命令 | 结果 |
|---|---|
| `grep -c "run\.sh" .github/workflows/ci.yml` | **`0`，rc=1**（无匹配） |
| `grep -rn "run\.sh" .github/` | 无任何输出，rc=1 |

`[一手]`。并确认 `.github/workflows/` 下**只有 `ci.yml` 一个 workflow**
（`ls -1 .github/workflows/` → `ci.yml`），且全仓历史里 `git log --all --diff-filter=A -- '.github/workflows/*'`
也只出现过这一个文件 `[一手]`。所以「`ci.yml` 为空」这一条**成立**。

### 3.2 扩大到全仓、全可执行入口的检索（指控只查了 `ci.yml` 一个文件）

检索范围（全部 `[一手]`，命令与 rc 见 §A）：

| 检索 | 范围 | 结果 |
|---|---|---|
| `git grep -n -F 'run.sh' 5a484be5 -- . ':!tests/haxe'` | **该 rev 的全部 tracked 文件**（不限文件类型） | **88 命中**，逐条分类后**无一条执行 `tests/haxe/**/run.sh`** |
| `git grep -n 'tests/haxe' -- '*.ts' '*.js' '*.sh' '*.nix' '*.json' '*.yml' '*.yaml' '*.hxml' ':!tests/haxe'` | 可执行文件类型 | 14 命中，均非 `run.sh` 执行路径 |
| `package.json` 全部 scripts | 32 个脚本 | **无任何脚本执行 `tests/haxe/**/run.sh`** |
| `tests/haxe/compile.hxml` | `test:haxe` 实际编译入口 | 引用夹具目录数 = **0** |

88 条命中的**全部**可归入以下惰性类别，没有一类是执行路径：

1. **散文/文档**：`README.md`、`docs/compiler-policy-interfaces.md`、
   `docs/investigations/.../fixture-naming-integration-review.md`、`docs/architecture/BASELINE-FAILURES.md`
   （后者把 `nix develop -c bash tests/haxe/charcodeat/run.sh` 写成**人工诊断**命令，不在任何 workflow 里）。
2. **哈希清单**：`docs/architecture/evidence/entry-gate-r2r3/*.R3-manifest.txt` 列出 `run.sh` 的 sha256，
   是清单不是调用。
3. **字符串字面量（不存在的路径）**：`tools/doc-style/check.test.ts:230-231` 把
   `tests/haxe/source-contract/run.sh`、`tests/haxe/source-origin/run.sh` 当**输入字符串**传给
   `scanPath`（一个纯文本扫描函数）；且这两个路径**在当前树里已不存在**。
4. **注释**：`tools/registry-guard/backstop.ts:10`。
5. **守卫自身**：`tests/fixture-reachability.test.ts:11,53` 只比较**文件名字符串** `"run.sh"`。
6. **其它夹具的自引用**：`tests/bundle-child-evidence/run.sh`、`tests/swift-length-utf16/run.sh`
   （都在 `tests/haxe` 之外，与本案无关）。

另外确认：CI 的 `linux` / `macos` 两个 job 确实跑 `bun run test:haxe`
（`haxe tests/haxe/compile.hxml && bun out/haxe/tests.js`），但 `compile.hxml` 的
`-cp tests/haxe` 只提供 `Main.hx` 等 4 个顶层文件，**不引用任何夹具目录**（§A.8 计数 = 0），
`--macro Intercept.run(['samples','tests/haxe'])` 是编译期宏、不 spawn 进程。

### 3.3 结论：「`run.sh` 不被 CI 执行」成立，但「这 35 个夹具不被任何 CI job 执行」**被推翻一条**

**反例（一手，本次最重要的发现）**：`tests/ts/package-shell.test.ts:388-390` 读取并执行
`tests/haxe/swift-package-shell-emit/emit.hxml`：

```ts
388:  const hxml = fs.readFileSync(path.join(REPO_ROOT, SWIFT_EMIT_HXML), "utf8")
389:    .replace("-D swift-output=out/swift-package-shell-emit", `-D swift-output=${tree}`);
390:  const result = await runHaxe("swift-package-shell-emit.hxml", hxml);
391:  expect(result.stderr).toBe("");
392:  expect(result.exitCode).toBe(0);
```

而 `SWIFT_EMIT_HXML = "tests/haxe/swift-package-shell-emit/emit.hxml"`（同文件 `:131`），
且 `swift-package-shell-emit` **正是 §2 那 9 个纯 `.hxml` 成员之一、也在 35 之内**。

这个文件是 `*.test.ts`，由 `bun run test`（= `bun test tests/ packages/registry/tests/`）收集，
而该命令正是 CI `collected-suite` job 的 `Collected suite (contract 3 count)` 步骤所跑
（`ci.yml:328-332`）。**所以 35 个夹具里至少有 1 个（`swift-package-shell-emit`）在 CI 里真的被执行。**

因此指控第二部分要分两种读法判定：

- 读作「这些 **`run.sh`** 完全不被任何 CI job 执行」→ **成立 [一手]**（§3.1、§3.2）。
- 读作「这 **35 个夹具**完全不被任何 CI job 执行」（指控紧接着的「L4 的主力正是这些夹具」用的是这个读法）
  → **被推翻**：反例 1 个，即 `swift-package-shell-emit`。

## 4. 指控的「唯一性」部分：**被推翻**

指控称 `dc-promoted-eval` 是**唯一**做「生成物突变 + negative control」的夹具。

`dc-promoted-eval/run.sh` 确实这么做：`mutate()` 复制生成树、`sed -i` 注入一次多余求值、
断言 subject 调用数 `before=1 → after=2` 且 sha256 变化，再跑变异树证明调用方抓得住
（`[一手]`，读源文件，未执行）。

但**另有至少两个 runner 做同一形状的事** `[一手]`：

| runner | 生成物突变 + negative control |
|---|---|
| `tests/haxe/kotlin-comparison-consumer/run.sh:80-90` | `cp -r "$RUN/gen" "$RUN/gen-mutated"` → `sed -i 's/a\.value\.compareTo(b\.value)/b.value.compareTo(a.value)/'` → 重编译并断言变异被检出，注释自述 `# Mutation negative control` |
| `tests/haxe/ts-comparison-collision/run.sh:46-57` | `cp -r "$RUN/ts-gen" "$RUN/mutation-ts-gen"` → `sed -i 's/return 0;/return 7;/'` → 跑变异树并断言**非零**退出 |

所以「唯一」这个全称量词**与产物不符**。判定：**推翻**。
（不排除措辞作者想说的是「唯一同时覆盖五目标 + 生成物突变」之类的更窄命题；但字面写的是
「唯一做生成物突变 + negative control」，在这个字面含义下有两个反例。）

## 5. 结论：一手实测 vs 转述

| 结论 | 来源 |
|---|---|
| `tests/haxe` 直接子目录 = 43 | **一手**（§A.1） |
| `run.sh` 参数 = 29 递归 / 27 直接子 / 2 嵌套 | **一手**（§A.2、§A.3） |
| `RECORDED_UNCOLLECTED` 判据复现 = 35，与常量一致 | **一手**（§A.4） |
| 35 的分解 = 26 带 `run.sh` + 9 纯 `.hxml` | **一手**（§A.4） |
| `bun test tests/fixture-reachability.test.ts` = 2 pass | **一手**（§A.5） |
| `grep -c "run\.sh" ci.yml` = 0（空） | **一手**（§A.6） |
| 全仓无任何路径执行 `tests/haxe/**/run.sh` | **一手**（§A.7，范围见 §3.2） |
| `swift-package-shell-emit` 被 `tests/ts/package-shell.test.ts` 执行 | **一手**（§A.9） |
| `dc-promoted-eval` 在 35 之内、且做生成物突变 + negative control | **一手**（§1、§4） |
| 「`dc-promoted-eval` 是**唯一**做该形状的夹具」 | **一手推翻**（§4） |
| 指控原文的具体措辞与「35 个 `run.sh`」的表述 | **转述**（引自 `GAPS.md:103-111` 与审阅原文，本次未取得审阅原始文件） |
| 「L4 的主力正是这些夹具」 | **转述**（未定义「主力」，本次不判定） |
| 是否**应该**把这些夹具接进 CI | **不判定**（非目标，见任务书） |

## 6. 「我没找到」与「不存在」的区分

本报告中的否定性结论，其**检索范围**如下，请按范围读：

- **「CI 里没有 job 执行 `tests/haxe/**/run.sh`」** ＝ 在 tracked 文件的**文本**里没有调用路径，
  检索范围是：(a) `.github/` 全部文件（仅 1 个 workflow）；(b) `5a484be5` 的**全部 tracked 文件**
  中对字符串 `run.sh` 的匹配（88 条，逐条分类）；(c) `package.json` 全部 32 个 script；
  (d) `tests/haxe/compile.hxml` 与两个 stage1 hxml。
  **未覆盖**：`node_modules/` 与 `out/` 等 gitignored 生成树（它们不是 CI 的输入源）；
  以及「某进程在运行时用**拼接字符串**构造出 `run.sh` 路径」这类无法用文本检索穷尽的动态构造
  —— 对此我只有 §3.2 的静态证据，**没有**运行时追踪（runtime trace）证据做补强。
  因此这属于「**在已声明的范围内没找到**」，而不是「**已证明不存在**」。
- **「43 / 29 / 27 / 35」** 是**文件系统枚举**读数，不是检索意义上的否定结论，可视为确定。
- **「`flow` / `source-container-policy` 是 hxml-only」** 是**直接子**口径；
  这两个目录**内部**各有一个嵌套 `run.sh`（§A.2），递归读法下它们是有 runner 的。
- **未检索全部分支**：`run.sh` 的引用只在 `5a484be5` 这一个 rev 上检索。
  §3.2 的 (b) 额外做过一次跨分支抽样（`git rev-list --all --max-count=400`，`[一手]`），
  结果未改变结论，但那是**抽样**、不是全部 rev。

## 7. 指控逐条判定

| # | 指控 | 判定 |
|---|---|---|
| 1 | `tests/haxe/` 下有 43 个目录 | **证实** |
| 2 | 有 27 个 `run.sh` | **部分证实**：仅在「直接子」口径成立；递归实际 29，少算 2 个嵌套 |
| 3 | 35 个「有 runner 但无被收集测试」 | **证实**（与守卫常量精确一致），但 35 ≠ 35 个 `run.sh`：26 带 `run.sh` + 9 纯 `.hxml` |
| 4 | `grep -n "run\.sh" ci.yml` 为空 | **证实**（rc=1，0 命中） |
| 5 | 这些 `run.sh` 完全不被任何 CI job 执行 | **证实**（在 §3.2 声明范围内），但见下面第 6 条的范围警告 |
| 6 | 「L4 的主力（这 35 个夹具）完全不被 CI 收集」 | **推翻一条**：`swift-package-shell-emit` ∈ 35，且被 `tests/ts/package-shell.test.ts` 在 `collected-suite` job 里执行 |
| 7 | `dc-promoted-eval` 在这 35 个之内 | **证实** |
| 8 | `dc-promoted-eval` 是**唯一**做「生成物突变 + negative control」的 | **推翻**：另有 `kotlin-comparison-consumer`、`ts-comparison-collision` 两个同形状 runner |

---

## 附录 A：可复核命令（argv / cwd / rc）

除特别说明，**cwd 均为 `/home/losses/Development/tq-workspace/boring-wt-architecture`**，
实测工作树 rev = `55445709`，被对账的 ci tip = `5a484be5`。所有命令**只读**。

### A.0 两 rev 在被测路径上无差异

```
$ git diff --stat 55445709 5a484be5 -- tests .github tools package.json bunfig.toml boring.json
（无输出）                                  rc=0
$ git merge-base --is-ancestor 55445709 5a484be5 && echo YES
YES                                         rc=0
```

### A.1 目录枚举

```
$ find tests/haxe -mindepth 1 -maxdepth 1 -type d | wc -l     → 43      rc=0
$ find tests/haxe -mindepth 1 -maxdepth 1 -type f | wc -l     → 9       rc=0
```

### A.2 `run.sh` 递归总数与深度

```
$ git ls-files 'tests/haxe/**/run.sh' | wc -l                 → 29      rc=0
$ git ls-files 'tests/haxe/**/run.sh' | awk -F/ '{print NF}' | sort | uniq -c
     27 4
      2 5                                                        rc=0
```

### A.3 `run.sh` 直接子数

```
$ ls tests/haxe/*/run.sh | wc -l                              → 27      rc=0
```

### A.4 复现 `RECORDED_UNCOLLECTED = 35`（便携 one-liner，不 import 被测文件）

```
$ bun -e '
const fs=require("fs"),p=require("path");
const H=p.join(process.cwd(),"tests","haxe");
const d=fs.readdirSync(H).filter(n=>{try{fs.readdirSync(p.join(H,n));return true}catch{return false}});
const u=d.filter(n=>{const e=fs.readdirSync(p.join(H,n));return e.some(f=>f==="run.sh"||f.endsWith(".hxml"))&&!e.some(f=>f.endsWith(".test.ts"))});
console.log("dirs="+d.length,"uncollected="+u.length);
'
dirs=43 uncollected=35                                        rc=0
```

### A.5 守卫测试重跑

```
$ bun test tests/fixture-reachability.test.ts
(pass) fixture reachability > the fixtures directory is present and discovery works
(pass) fixture reachability > the number of runner-bearing uncollected fixtures matches the record
 2 pass / 0 fail / 3 expect() calls / Ran 2 tests across 1 file    rc=0
```

### A.6 指控给出的 CI 检索

```
$ grep -c "run\.sh" .github/workflows/ci.yml                  → 0       rc=1
$ grep -rn "run\.sh" .github/                                 （无输出） rc=1
$ ls -1 .github/workflows/                                    → ci.yml  rc=0
```

### A.7 全仓检索

```
$ git grep -n -F 'run.sh' 5a484be5 -- . ':!tests/haxe' | wc -l          → 88   rc=0
$ git grep -n 'tests/haxe' 5a484be5 -- '*.ts' '*.js' '*.sh' '*.nix' \
      '*.json' '*.yml' '*.yaml' '*.hxml' ':!tests/haxe' | wc -l         → 14   rc=0
$ git log --all --diff-filter=A --name-only --pretty=format: \
      -- '.github/workflows/*' | sort -u | grep -v '^$'
.github/workflows/ci.yml                                                 rc=0
```

跨分支抽样（**抽样**，非全部 rev）：

```
$ git grep -n -F 'run.sh' $(git rev-list --all --max-count=400) -- . ':!tests/haxe' \
    | sed 's/^[0-9a-f]*://' | awk -F: '{print $1":"$2}' | sort -u | wc -l   → 103  rc=0
```

### A.8 `test:haxe` 是否触达夹具

```
$ grep -cE 'run\.sh|/expected/|gen/' tests/haxe/compile.hxml  → 0       rc=1
$ cat tests/haxe/compile.hxml
-lib reflaxe / -lib boring / -cp packages/compiler / -cp samples / -cp tests/haxe
-main Main / -js out/haxe/tests.js / -D analyzer-optimize
--macro Intercept.run(['samples', 'tests/haxe'])
--macro haxe.macro.Compiler.addGlobalMetadata('boring', '@:build(std.RecordMember.build())')
```

### A.9 反例：35 中的成员被收集套件执行

```
$ grep -n 'SWIFT_EMIT_HXML\|runHaxe\|Bun.spawn' tests/ts/package-shell.test.ts
57:  async function runHaxe(hxmlName: string, content: string)
61:    const proc = Bun.spawn(["haxe", path.relative(REPO_ROOT, hxmlPath)], ...)
131: const SWIFT_EMIT_HXML = "tests/haxe/swift-package-shell-emit/emit.hxml";
388:   const hxml = fs.readFileSync(path.join(REPO_ROOT, SWIFT_EMIT_HXML), "utf8")
390:   const result = await runHaxe("swift-package-shell-emit.hxml", hxml);
                                                                          rc=0
```

`collected-suite` job 确实跑该收集域（`ci.yml:328-332`：`nix develop -c bash -c 'bun run test'`，
而 `package.json` 的 `test` = `bun test tests/ packages/registry/tests/`）。

### A.10 「唯一」的反例

```
$ git grep -lE 'sed -i' 5a484be5 -- 'tests/haxe/**/run.sh'
tests/haxe/dc-promoted-eval/run.sh
tests/haxe/kotlin-comparison-consumer/run.sh
tests/haxe/ts-comparison-collision/run.sh                        rc=0
```

后两者的变异上下文见 §4 表（均为 `cp -r` 生成树副本 + `sed -i` + 断言变异被检出）。

---

## 附录 B：本次未做 / 不能被本报告支撑的结论

- **未执行任何夹具**，故本报告**不**包含任何关于这些夹具**是否通过**的断言。
- **未判定**这些夹具是否*应该*被接进 CI —— 那是实现任务，且任务书把它列为非目标。
- **未穷尽「不存在」**：§6 已写明否定性结论的检索范围与其缺口（无运行时追踪、
  gitignored 树未检索、跨分支为抽样）。
- 本次复核**不改**任何 fixture、workflow、测试；只新增本文件。
