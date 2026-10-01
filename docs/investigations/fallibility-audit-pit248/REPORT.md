# PIT-248 可失败性降级审计：局部还是普遍？（t-mungw3ci-0i43）

**审计人**：board row `t-mungw3ci-0i43` 的认领 agent（worktree `boring-wt-fallibility`，分支
`audit/fallibility-downgrade-from-pit248`，基线 `arch/agent-guided-governance` @ 05e375b2）。
**日期**：2026-09-30。**方法声明**：本报告是**独立重推导**。派单前存在的上一版审计
（2026-09-29，已存档为 `evidence/REPORT-2026-09-29-previous-pass.md`，其原始证据文件
`evidence/` 中未加 `v2` 前缀者保持原样未动）**未被采信**——所有数字均由本审计自己的
脚本与命令重算（§1.3）。上一版的结论方向与本审计一致，本审计的价值在于：① 数字独立
复现；② 逐点形态与四树隔离补齐（判据 2）；③ 契约裁定逐行核引（判据 3）；④ 明确
"已测 vs 已推"的边界。

---

## 0. 问题与结论（TL;DR）

**问题**：PIT-248 的 Rust 修复使 `value_type_consumer_rendered_id` 从
`-> Result<UString, ValueError>` + `?` + `Ok(...)` 变为 `-> UString` + `.unwrap()`
（可失败性被降级为 panic 路径）。这是**局部现象**还是**普遍回归**？

**三个结论**：

1. **范围判定：局部（单符号），不是普遍回归。** 全树枚举（`reference/rust/gen` f64 509
   文件 / `reference/rust-f32/gen` f32 共有集 466 文件，四树）中，"可失败调用被降级为
   `.unwrap()` / 非 `Result`"的变化**严格限于一个符号**
   `boring/value_type_consumer.rs::value_type_consumer_rendered_id`（及其调用方
   `tests/value_type_tests.rs::test_rendered_string` 的连带变化），两种精度下逐符号
   签名 diff 均为恰好 1 处 `RESULT_LOST`、0 处 `GAINED`、0 处 `OTHER`。**空结果即真答案**：
   不存在其它降级位点。
2. **契约判定：降级是（潜在）契约缺陷。** spec 06（状态 **Complete**）规定函数只在
   "no uncaught domain escapes it" 时才可降为 infallible；`rendered_id` 内
   `ValueError` 无处被捕获 → 逃逸 → **必须保持 `Result`**。即：局部 ≠ 可接受——
   这一处形态本身不合规（§4）。
3. **`.unwrap()` 在现输入下不会 panic**（常量实参 `"face"`，四个字节均不在 trim 空白集，
   §5）→ 属**潜在契约缺陷（签名说谎），非现行崩溃**。

**四树隔离（订正后形态，本审计独立复验）**：

| 树 | `Compiler.hx` sha256:16 | `rendered_id` 签名 | 调用点（tests:47） |
| --- | --- | --- | --- |
| head（pristine） | `1cdc0ebd1e6edb9d` | `-> Result<UString, ValueError>` | `.unwrap().as_ustr()` |
| **coord（as-reviewed）** | `24f79c275c0c493d` | **`-> Result<UString, ValueError>`（与 HEAD 同形态）** | `.unwrap().as_ustr()` |
| arrfix（与 coord 同 Compiler.hx） | `24f79c275c0c493d` | `-> Result<UString, ValueError>` | `.unwrap().as_ustr()` |
| fixed2 | `07896d15a5b718b8` | `-> UString` | `.as_ustr()` |
| fixed3（= 现协调树 = 本 worktree 基线） | `57ee49976511892c` | `-> UString` | `.as_ustr()` |

> **注意**：board 行描述里的旧表述"coord 24f79c27（as-reviewed）… 都发 UString+
> `.unwrap()`"是**错的**（该表述先于 TCN-121 的两次订正）。本审计对五棵树的生成物
> 逐一锚定 grep 复验：as-reviewed 与 HEAD 同形态；且更强——**head→coord 全树逐字节
> 差异 = 0 文件**（f64 509 / f32 466）。翻转只发生在 fixed2/fixed3 形态。

**动作**：契约判定为缺陷 → 按任务第 ③ 步**新开立修复任务**
`fix/value-type-consumer-fallibility-exposure`（本任务不修，停在 doing）。

---

## 1. 枚举与分母

### 1.1 树与身份（命令 + 输出）

board 行中的 `1cdc0ebd / 24f79c27 / 07896d15 / 57ee4997` **不是 git SHA**，是各树
`packages/compiler/reflaxe/rust/rustcompiler/Compiler.hx` 的 **sha256 前 16 位十六进制**。

命令（2026-09-30 重跑，输出存 `evidence/tree-identity.txt`）：

```
sha256sum <tree>/packages/compiler/reflaxe/rust/rustcompiler/Compiler.hx | cut -c1-16
```

| 树（路径） | sha256:16 |
| --- | --- |
| `p09-chainA-work/execution-option-c-head-e1c65975` | `1cdc0ebd1e6edb9d` |
| `p09-chainA-work/execution-option-c-coord` | `24f79c275c0c493d` |
| `p09-chainA-work/execution-option-c-chainA-fixed2` | `07896d15a5b718b8` |
| `p09-chainA-work/execution-option-c-chainA-fixed3` | `57ee49976511892c` |
| `p09-chainA-work/execution-option-c-arrfix` | `24f79c275c0c493d`（=coord） |
| `publication-staging/execution-option-c-{coord,e1c65975}` | 与 p09 对应树相同 |
| `boring-wt-architecture`（现协调树，只读） | `57ee49976511892c`（=fixed3） |
| `boring-wt-fallibility`（本审计 worktree） | `57ee49976511892c`（=fixed3） |

### 1.2 分母（本审计枚举）

文件枚举命令（每树各跑一次，原始行存 `evidence/census-v2-full.txt` 的
`[inventory]` 行）：

```
find <tree>/reference/rust/gen     -name '*.rs' | sort | wc -l
find <tree>/reference/rust-f32/gen -name '*.rs' | sort | wc -l
```

| 树 | f64（rust/gen） | f32（rust-f32/gen） |
| --- | --- | --- |
| head | **509** | **466** |
| coord | 509 | 466 |
| fixed2 | 509 | **508** |
| fixed3 | 509 | **508** |

- **f64**：四树文件集**完全相同**（`only_in_a = only_in_b = 0`）→ 语料对等，全树可比。
- **f32**：head/coord 466，fixed2/fixed3 508；**共有集 = 466**，fixed 侧多出的 **42 个
  `.rs`** 文件（如 `boring/font_id.rs`、`boring/number_classify_ops.rs`、
  `tests/no_such_element_*.rs` …）源于 `examples/rust-f32.hxml` 新增 33 个模块项 +
  依赖模块连带（`rust.hxml` 两树逐字节相同）。**全树 f32 计数不可比**，涉及 f32 的
  判定一律在 466 文件共有集上进行（跨精度语料不对等是本项目反复踩过的坑，TCN-121 ③）。

符号（函数声明）分母——`census.py` 口径：文本中所有 `fn` 声明（含 `pub fn` / `fn` /
`const fn` / trait 的 `;` 声明），按 `(文件, fn 名, 归一化参数)` 为键：

| 精度 | 声明数/树（共有集） | 其中**可失败声明**（返回 `-> Result<`）head → fixed3 |
| --- | --- | --- |
| f64（509 文件） | 2582 → 2582 | **99 → 98（−1）** |
| f32（466 共有集） | 2449 → 2449 | **97 → 96（−1）** |

"−1"就是本审计追踪的那一个符号。

### 1.3 枚举命令（可复核，全部本审计重跑）

1. **全树 census**（文件清单 + 文件集差 + 逐文件字节 diff + 逐符号返回类型 diff +
   双口径计数 + 逐文件 `unwrap()` 差 + 变更文件行级 diff）：

   ```
   cd boring-wt-fallibility
   python3 docs/investigations/fallibility-audit-pit248/census.py \
     > dc-warn/out/fallibility-audit/evidence/census-v2-full.txt
   ```

   （脚本在本分支 `docs/investigations/fallibility-audit-pit248/census.py`；对
   head↔coord、head↔fixed2、head↔fixed3 三对 × f64/f32 两精度各跑一遍。）
2. **逐点形态**（锚定模式；**不用**宽泛 alternation + `head -1`，TCN-121 ① 的教训）：

   ```
   grep -n 'pub fn value_type_consumer_rendered_id()' <tree>/reference/rust/gen/boring/value_type_consumer.rs
   grep -n 'value_type_consumer_rendered_id()' <tree>/reference/rust/gen/tests/value_type_tests.rs
   ```

   （输出存 `evidence/point-forms-5trees.txt`。）
3. **逐符号/文件级 diff 文件**：`evidence/v2diff_head_{fixed2,fixed3}_*.u`（脚本自动生成）。

---

## 2. 分类（逐位点证据）

### 2.1 全树文件级 diff（范围的权威口径）

逐文件字节比较（= `diff -rq` 等价，**不依赖任何计数**）：

| 对比 | f64 变更文件 | f32 变更文件 |
| --- | --- | --- |
| head→coord | **0** | **0** |
| head→fixed2 | 3（下表 ①②③） | 6（①② + 4 个 `mod.rs`） |
| head→fixed3 | 3（下表 ①②③） | 6（①② + 4 个 `mod.rs`） |

f64 的 3 个变更文件（head→fixed2 与 head→fixed3 **结果相同**）：

| # | 文件 | 性质 | 与可失败性降级的关系 |
| --- | --- | --- | --- |
| ① | `boring/value_type_consumer.rs` | 签名 `Result`→非 `Result`，体 `?`→`.unwrap()`、`Ok(...)`→裸返回（`v2diff_*.u`，14 行 diff） | **本审计对象**（唯一） |
| ② | `tests/value_type_tests.rs` | 调用点 `test_rendered_string`：`.unwrap().as_ustr()`→`.as_ustr()`（10 行 diff） | ① 的**调用方连带**：`unwrap` 从测试侧移入被调方函数体（净 0） |
| ③ | `tests/number_classify_tests.rs` | 数字字面量 `1.0e308f64`→`3.0e38f64`（11 行 diff） | **与可失败性无关**（`unwrap`/`Result<` 计数 0→0；源自 `samples/tests/NumberClassifyTests.hx` 的源编辑，上一版审计 §3.2 已归因；本审计确认了生成物 diff 与 0→0 计数） |

f32 额外 4 个变更文件：`boring/mod.rs`、`runtime/mod.rs`、`std/mod.rs`、`tests/mod.rs`
——42 个新增模块的模块声明，**与可失败性无关**（42 个新文件本身无可比基线，属语料
不对等部分，不计入降级判定）。

### 2.2 逐符号签名 diff（"降级"的权威口径）

口径：共有文件集上，按 `(文件, fn 名, 归一化参数)` 键比较返回类型；返回类型以
`-> Result<` 开头记为可失败。

| 精度 | RESULT_LOST | RESULT_GAINED | OTHER_SIG_DIFF |
| --- | --- | --- | --- |
| f64（509 共有文件） | **1** | 0 | 0 |
| f32（466 共有文件） | **1** | 0 | 0 |

唯一一处（两精度同一符号）：

```
RESULT_LOST  boring/value_type_consumer.rs :: value_type_consumer_rendered_id()
     head:   -> Result<UString, ValueError>
     fixed3: -> UString
```

### 2.3 逐点形态（四树 + 调用方；`evidence/point-forms-5trees.txt`）

```
head / coord / arrfix（行 66-68，三树逐字节相同）:
    pub fn value_type_consumer_rendered_id() -> Result<UString, ValueError> {
        let id = FontFaceId::new(UStr::new(&[102,97,99,101]))?;
        return Ok(UString::from((id).to_string().as_str()));
    }
fixed2 / fixed3（同位置）:
    pub fn value_type_consumer_rendered_id() -> UString {
        let id = FontFaceId::new(UStr::new(&[102,97,99,101])).unwrap();
        return UString::from((id).to_string().as_str());
    }
调用方 tests/value_type_tests.rs:47（head/coord/arrfix）:
    ... value_type_consumer_rendered_id().unwrap().as_ustr() ...
调用方（fixed2/fixed3）:
    ... value_type_consumer_rendered_id().as_ustr() ...
```

**邻位对照（强局部性证据）**：同一文件、相邻函数 `value_type_consumer_blank_rejected`
里对**同一个构造器**的调用 `FontFaceId::new(UStr::new(&[32]))` 在 head 与 fixed3 中
**逐字节不变**，仍保持 `__outcome: Result<FontFaceId, ValueError>` 闭包 + `?` 形态
（行 43-49）。即生成器在该文件里**没有**普降可失败性——变化精确地只落在
`rendered_id` 这一个函数上。

### 2.4 计数复核（双口径，TCN-121 ⑤：报数必须写明口径）

`unwrap()`：LINES = 含 ≥1 次出现的行数（`grep -c` 语义）；OCCURRENCES = 总出现次数
（`grep -o` 语义）。f64 两口径差 3，因 3 行 `VectorCodec` 的
`decode(encode(..).unwrap()).unwrap()` 各含 2 次。

| 指标（f64 全树） | head | fixed3 | 净 |
| --- | --- | --- | --- |
| `unwrap()` LINES | 97 | 97 | 0 |
| `unwrap()` OCCURRENCES | 100 | 100 | 0 |
| `Result<` LINES=OCC | 129 | 128 | **−1** |
| 可失败声明（`-> Result<`） | 99 | 98 | **−1** |

f32 **共有集**（466 文件）：`Result<` 126→125（−1）、可失败声明 97→96（−1）、
`unwrap()` 净 0——与 f64 完全一致。f32 **全树** `Result<` 126→127（**+1**，不是 −1）：
语料不对等，42 个新文件贡献 +2 抵消了共有集的 −1。**任何全树 f32 数字都不可用于
判定**（本审计数字与上一版一致，独立复现）。

逐文件 `unwrap()` 差（f64）：恰好 2 个文件、互为抵消——
`boring/value_type_consumer.rs` 0→1（+1，unwrap **移入**函数体）、
`tests/value_type_tests.rs` 1→0（−1，unwrap **移出**调用方）。

### 2.5 已测 vs 已推（边界声明）

**本审计已测**（全部可重跑）：四树身份 sha256；文件清单与文件集差；全树逐文件字节
diff（f64 3 文件 / f32 6 文件，head→coord 0 文件）；逐符号返回类型 diff（各 1 处
RESULT_LOST）；双口径计数与逐文件 `unwrap` 差；逐点形态（五树）；调用方 diff；
`FontFaceId::new` / `UStr::new` / `trim` / `UString` 的源码行；常量实参字节证明；
全部契约引用的原文与行号（本分支 docs）。

**本审计已推（未证）**：① "翻转由 `scanStaticReferences` 前移至 `scanFallibility`
之前这一重排引起"——基于五修订共现（TCN-121 / 上一版审计 §3.4），**未插桩、未重跑
生成器**，`scanFallibility` 内部分类翻转的精确路径**未验证**；② 生成树编译/测试通过
（本审计只读，未跑 cargo）；③ 五树不是受控 A/B（15 个源文件差异、其中 4 个 Rust
编译器文件——"该 diff = PIT-248 修复"不能仅由这一对树支持，上一版审计 §3.5）。

---

## 3. 判定：局部（及其依据）

**判定：局部现象——严格限于单符号 `value_type_consumer_rendered_id`，不是生成器普遍
行为，不是普遍回归。**

依据（全部已测，可复核）：

1. **全树字节 diff 闭集**：head→fixed3 变更文件 f64 恰 3 个 / f32 恰 6 个；其中与
   可失败性相关的只有 ①+② 一对文件，两精度同一对。任何其它位点的"降级"都不存在
   （若存在，必然表现为字节 diff，而 diff 闭集里只有这 3/6 个文件）。
2. **逐符号 diff 恰好 1**：两精度 `RESULT_LOST=1`、`GAINED=0`、`OTHER=0`。
3. **邻位对照**：同文件相邻的同一构造器调用位点（`blank_rejected` 的 `?`）不变。
4. **as-reviewed 树全树 ≡ pristine**（0 文件差异）：降级形态不存在于 as-reviewed
   版，只出现于 fixed2/fixed3 形态——它是那条改动链某一阶段（与扫描重排共现）的
   副作用，不是修复的必然伴随。
5. **计数只是佐证**：净 0 / −1 的计数（双口径）与上述闭集一致，但**判定不依赖计数**
   （计数普查看不见 ③ 那种字面量级差异——TCN-121 ④）。

**"局部"回答的是范围问题；可接受性由 §4 的契约问题独立回答**（局部但违规）。

---

## 4. 契约裁定（判据 3）

**问题**：该符号是消费样例（探针），其可失败性**是否应当暴露给调用方**？

**裁定：应当暴露。HEAD 形态合规，fixed3 形态不合规。** 全部引用逐行核引自本分支
`docs/`（verbatim 与行号如下；上一版审计的引文表 `evidence/governing-citations.txt`
与本表一致，本审计独立复核了行号）：

| # | 引用（file:line，本审计核引） | 原文要点 | 分量 |
| --- | --- | --- | --- |
| 1 | `docs/specs/features/06-errors-and-results.md:316`（spec 06 状态 **Complete**，`docs/specs/README.md:71`） | "Rust: all fallible operations return `Result<T, DomainError>` with structured variants. Candidate 1." | 默认裁定 |
| 2 | `docs/specs/features/06-errors-and-results.md:369-375`（:374 锚定） | 可失败性吸收条款：包装函数降为 infallible-to-the-caller "**only when no uncaught domain escapes it**" | **决定性**：`ValueError` 在 `rendered_id` 内无处被捕获 → 逃逸 → 函数**不得**声明为 infallible |
| 3 | `docs/specs/features/06-errors-and-results.md:303` | Panics 候选被否，理由 "**Function signatures hide failure possibilities from callers.**" | fixed 形态的签名正是这种隐藏 |
| 4 | `docs/specs/features/06-errors-and-results.md:399` | "Rust panic and `Box<dyn Error>` returns are banned for the reasons in the judgment table." | `.unwrap()` 即 panic 机制 |
| 5 | `docs/compiler-policy-interfaces.md:163-167`（:166-167 锚定） | "Failure to prove an extraction's preconditions is distinct from invalid source. … **This distinction does not authorize a silent unwrap** or a new null-handling behavior." | 直接禁止该处的发射形态 |
| 6 | `docs/specs/stdlib/08-string-buffer.md:68-71` | Rust 侧可失败性靠 "`String::from_utf16(&buf).map_err(...)` **returning through the enclosing function's `Result`**" | 目标特定裁定：Rust 把可失败性放在外层函数的 `Result` 上——即 HEAD 形态 |
| 7 | `docs/specs/features/19-testing.md:443` | `let decoded = VectorCodec::decode(&VectorCodec::encode(&records).unwrap()).unwrap();` | sanctioned 形态是**测试调用点** unwrap——即 HEAD 的测试形态；测试侧 `.unwrap()` 是惯用法 |
| 8 | `docs/compiler-policy-architecture.md:101`（D 包：控制流结果） | "Branch values, return/assignment/discard intent, … target construction that preserves nested scopes **without rewriting return text**" | 返回的可失败性是 D 的裁定，不得作为扫描顺序的附带后果被改写 |
| 9 | `docs/compiler-policy-architecture.md:103`（F 包：证据与诊断） | "… observation consumers that **expose decisions without participating in selection**" | 样例可以**暴露**决定，不能**参与选择**另一种可失败性 |
| 10 | `docs/compiler-policy-architecture.md:29,31` | "Target representation policy \| … **error and container representation**" / "Target construction \| … declarations, and helper calls" | 错误表示是带生产者的策略决定，不能从扫描顺序里"掉出来" |

**最强反论（最近的"可证失败臂不可达"先例）为何不适用**：
`docs/specs/features/06-errors-and-results.md:389-395`（:394 锚定）确实 sanction 了
失败臂不可达的渲染 `usize::try_from(bound).unwrap_or(0)`（"the `unwrap_or(0)` arm is
unreachable and a reserved capacity of zero stays a valid hint"）。但它不能救 fixed
形态，三点：① 它 sanction 的是 **`unwrap_or(0)`——不 panic 的兜底**，本处是
`.unwrap()`（panic）；② 它有**记录在案的值域证明**（"Haxe `Int` maps to `u32` …
succeeds on every supported target"），本处**无任何证明附着**；③ 本处发射是
**value-blind** 的：`RustExpr.hx:2582-2584`
`if (!isFallible) return isFallibleCallee(...) ? ".unwrap()" : ""`（该行两树逐字节
相同）——只要外层函数被判 infallible，体内**所有**可失败调用一律 `.unwrap()`，与实参
值无关。

**该判定的适用边界（上一版审计的追问，本审计确认）**：docs 对
`value_type_consumer` / samples **未作专门规定**，裁定依据上述通则。该判定**不推广**
到其它生成点的依据：① 全树逐符号 diff 已证其它位点形态未变（§2.2），不存在需要
同一裁定覆盖的第二位点；② 若未来出现第二位点，须重做"该处失败是否被捕获/是否有
值域证明"的逐位判定——`unwrap_or` 先例（引用 2 的例外通道）是**逐位**可用的，通则
不是 blanket 授权。

---

## 5. 该 `.unwrap()` 在此输入下会不会 panic？（判据 4 的要求）

**不会 panic（对现行常量实参）——但签名在说谎。**

源码证据（fixed3 树 `reference/rust/gen/`；两树 `value_type_ops.rs` 逐字节相同，
故 head 同结论）：

- `boring/value_type_ops.rs:44-50`：
  `pub fn new(value: &UStr) -> Result<Self, ValueError>` —— **当且仅当**
  `value.trim() == UString::from("")` 返回 `Err(ValueError::BlankValue)`。
- `runtime/u_string.rs:24`：`UStr::new` 是零成本 `unsafe` 重解释
  （`&[u16] as *const UStr`），不分配、不能失败。
- `runtime/u_string.rs:70-87`：`trim` 只剥离空白集
  `{0x09..=0x0D, 0x20, 0x85, 0xA0, 0x1680, 0x2000..=0x200A, 0x2028, 0x2029, 0x202F,
  0x205F, 0x3000, 0xFEFF}`；`start`/`end` 双端扫描有界（`start < end` / `end > start`），
  结果 `UString(units[start..end].to_vec())` 越界安全。
- `runtime/u_string.rs:16,170-173`：`UString(Vec<u16>)` 派生 `PartialEq`（逐元素）；
  `UString::from("")` = 空 `Vec`。
- 实参：`UStr::new(&[102,97,99,101])` = 码元 `f a c e`（字节证明
  `evidence/face-bytes-proof.txt`：四字节均不在空白集 → trim 后长度 4 ≠ 0 →
  `value.trim() == UString::from("")` 为假 → 走 `Ok` 臂）。

**结论**：`.unwrap()` 在此位点、此实参下**不会 panic**（Err 臂不可达）→ 现行无崩溃
风险，属**潜在契约缺陷**：`-> UString` 签名对一个可失败操作声称不会失败（引用 3 的
"hide failure possibilities"），且若实参未来可变（样例输入变化 / 生成器泛化），将
直接成为 panic 路径。这正是引用 2 的例外通道（`unwrap_or` + 值域证明）未被满足的
形态——**若要走"可接受"路线，必须先补一份有引用的值域证明并做规范修订**（TCN-121
"能定案的材料"），而非默认放行。

---

## 6. 未验证 / 未证明（明示清单）

1. **翻转的精确机制未验证**：`scanStaticReferences` 前移如何使 `scanFallibility` 对
   这个 public static 改判——需插桩或重跑生成器（本审计只读，未动生成器）。
2. **五树非受控 A/B**：15 个源文件差异（4 个 Rust 编译器文件 + f32 hxml + 源样例
   等），"diff = PIT-248 修复"这一归因来自四树隔离 + TCN-121，不能仅由 head↔fixed3
   这一对树支持。
3. **生成树未编译、未跑测试**（cargo/bun 均未跑）；本审计的全部证据是文本级。
4. **f32 全树计数无意义**（语料 466 vs 508 不对等）；判定只用共有集。
5. **③ `number_classify_tests.rs` 字面量差异的归因**（源编辑）承自上一版审计 §3.2，
   本审计独立确认了生成物 diff 与 0→0 计数，未重读 `NumberClassifyTests.hx` 源。
6. **是否存在"强制实参非空"的生成器守卫**：未发现（上一版同），但未穷举证明其不存在。
7. 本审计未验证 `boring-wt-architecture`（现协调树）的 `reference/rust/gen` 是否与其
   工作树中的生成器一致（只核了 `Compiler.hx` sha256 = fixed3）；判定不依赖该树。

---

## 7. 动作与交接

- **修复任务已开立**：`fix/value-type-consumer-fallibility-exposure`（里程碑"Boring
  架构治理"；二选一路线：恢复 `Result` 暴露 / 补值域证明+规范修订；验收判据含全树
  复审计）。本任务不修。
- **本任务停在 doing**；sign-off 由队长/人执行（`wb_task_update status=done confirm=`）。
- **Wiki**：本审计的教训（锚定模式、语料对等、diff -rq 优先于计数、口径写明、跨修订
  隔离）均已记于 TCN-121，不重复立注；本审计另补一条 PIT（board 行描述可能落后于
  Wiki 订正，开工前须以核实的形态为准）——见 `wb_note_add` 记录。

---

## 8. 证据索引（`evidence/`，本审计新增文件带 `v2`/新名；旧文件未动）

| 文件 | 内容 |
| --- | --- |
| `census-v2-full.txt` | 本审计全树 census 原始输出（[inventory]/[file-set]/[byte-diff]/[counts]/[counts-common]/[sigs]/[line-diff]，三对树 × 两精度） |
| `v2diff_head_fixed3_reference__rust__gen_boring__value_type_consumer.rs.u` | ① 的 f64 行级 diff（签名+体） |
| `v2diff_head_fixed3_reference__rust__gen_tests__value_type_tests.rs.u` | ② 的 f64 行级 diff（调用点） |
| `v2diff_head_fixed3_reference__rust__gen_tests__number_classify_tests.rs.u` | ③ 的 f64 行级 diff（无关字面量） |
| `v2diff_head_fixed2_*.u`（9 个） | head→fixed2 的对应行级 diff（四树隔离：与 fixed3 逐字节相同的 3/6 文件集） |
| `v2diff_head_fixed3_reference__rust-f32__gen_*.u`（6 个） | f32 变更文件行级 diff（4×mod.rs + ① + ②） |
| `point-forms-5trees.txt` | 五树逐点形态（锚定 grep 原文 + 各树 Compiler.hx sha256:16） |
| `tree-identity.txt` | 九处 Compiler.hx sha256:16（含现协调树与本 worktree） |
| `face-bytes-proof.txt` | 实参 `[102,97,99,101]="face"` 对 trim 空白集的字节证明 |
| `REPORT-2026-09-29-previous-pass.md` | 上一版报告存档（原 REPORT.md 原样） |
| （上一版证据，未动） | `census-totals.txt`、`sigs-*.tsv`、`perfile-*.tsv`、`fulldiff-*.txt`、`governing-citations.txt`、`panic-analysis.txt`、`diff-*.patch/diff`、`f32-baseline-anomaly.txt`、`revision-artifact-matrix.txt` 等 |

**复现**：`python3 docs/investigations/fallibility-audit-pit248/census.py`
（分支 `audit/fallibility-downgrade-from-pit248` @ boring-wt-fallibility worktree）。
