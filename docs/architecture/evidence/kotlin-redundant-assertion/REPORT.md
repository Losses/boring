# 审计：Kotlin 发射的冗余 `!!`（同一表达式内抑制只覆盖部分读取点）

> 分支 `audit/kotlin-redundant-assertion-vs-master`，base `ci/collected-suite-failure-attribution`（`e54611c1`）。
> 看板任务 `t-mupmsxcx-qjsj`。
> 工具链：haxe 4.3.7；kotlinc-jvm 2.4.10（JRE 21.0.12+8-nixos）；reflaxe `/nix/store/ch901mw058pjvr3nyxgwxps31vc46wmm-source`。
> 除特别标注「转述」外，本报告每一条结论都由本人重跑命令后从产物里读回。

## 结论

**这是发射器缺陷，不是可接受的保守发射。**

判据链（详见 §4、§6）：

1. 该 `!!` 在语义上**不可能抛**：它由同一表达式中前一个已打印的 `!!` 支配；kotlinc 的数据流分析据此把第二个 `c` 定型为**非空 `Int`**，并直接报出 `unnecessary non-null assertion (!!) on a non-null receiver of type 'Int'`。
2. 判定它冗余**不需要**发射端自己建模「跨 `&&` 的数据流」。发射端**已经持有**这条事实：`addProofExpr` 在真正打印 `!!` 的地方把「这个稳定主体已断言」写进 `extractedLocals`（`KotlinExpr.hx:2673/:2677`），并在每个分支/循环/lambda/catch 边界做快照回滚（`ExtractionSuppressesRepeat`）。**同一棵树里，成员访问读取点（`instanceField`, `:3854` → `:3904`）消费了这条记录并成功省掉了重复 `!!`；裸局部操作数读取点（`operand`, `:3661`）没有消费它。** 同一个主体、同一条规则、两个读取点、两个答案。
3. 因此这不是「无法证明」，而是「拿到手的事实没有在 `operand` 这一族被查询」。结合 §6 的 bisect（差异由**单个 commit `3fb8c565`** 引入，且 `3fb8c565^` 与 master `cc9957dd` 的产物**逐字节相同**），它是一次回归，不是主线的既定口径。
4. 按仓库自己的标准，这两点足以定案：`docs/specs/style/02-translator-implementation-standard.md:78` 把「生成代码产生警告」与「生成代码输出错误」列为**同等严重**的发射器缺陷，`:80` 要求命名生成树内文件的警告行数为 0。实测该警告确实落在 `reference/kotlin/gen/runtime/StringTools.kt:9:28`（§5）。

同时必须分清：**这条 `!!` 不影响运行结果**（第一个 `!!` 要么抛、要么产出非空值，第二个永远不会抛），所以它不是「错值」缺陷，而是 `:78` 明确定级的**警告级发射器缺陷**。

## 1. 判定对象（判据 1：两棵树同源码产物对照）

### 1.1 源码逐字节相同（一手实测）

```
sha256  packages/compiler/runtime/StringTools.hx
6e07218a91c7a0b21fb82471b0bc1b463c7b9178c351a47896735611a26696dc
```

同一个哈希出现在三棵树：`boring-wt-cs42c805d3`（`42c805d3`）、`dc-warn/cs-master-cc9957dd`（`cc9957dd`）、本分支 worktree（`e54611c1`）。
`isSpace` 源码（`StringTools.hx:12-18`，三棵树相同）：

```haxe
public static function isSpace(s:String, pos:Int):Bool {
    if (s.length == 0 || pos < 0 || pos >= s.length) {
        return false;
    }
    final c = s.charCodeAt(pos);
    return (c > 8 && c < 14) || c == 32;
}
```

### 1.2 产物对照（含 sha256 与精确行号）

`runtime/StringTools.kt` 第 9 行：

| # | 树 / revision | 产物路径 | sha256 | 第 9 行 | 来源 |
|---|---|---|---|---|---|
| A | `boring-wt-cs42c805d3`（`42c805d3`，主线旧钉） | `reference/kotlin/gen/runtime/StringTools.kt` | `b7b22e37…285be0` | `return c!! > 8 && c!! < 14 \|\| c == 32` | 既有产物 |
| B | 本 worktree（`e54611c1`，主线 tip） | `reference/kotlin/gen/runtime/StringTools.kt` 与 `out/kotlin-redundant-assertion/gen/runtime/StringTools.kt` | `b7b22e37…285be0` | `return c!! > 8 && c!! < 14 \|\| c == 32` | **本人重新生成** |
| C | `dc-warn/cs-master-cc9957dd`（`cc9957dd`，master） | `out/kotlin-var-field-smartcast/gen/runtime/StringTools.kt` | `ced8a073…86b1e9` | `return c!! > 8 && c < 14 \|\| c == 32` | 既有产物 |
| D | `boring-wt-master-cc9957dd`（`cc9957dd`，本人在普通挂载点新建） | `out/kotlin-redundant-assertion/gen/runtime/StringTools.kt` | `ced8a073…86b1e9` | `return c!! > 8 && c < 14 \|\| c == 32` | **本人重新生成** |

完整哈希：

```
A = b7b22e37bd37d24d82468123b8187c3f8005e91127c32a7b33bd1beed2865be0
B = b7b22e37bd37d24d82468123b8187c3f8005e91127c32a7b33bd1beed2865be0
C = ced8a07374d72ffa84344453dde6d269cef9f8b16947b7f63b4168c6b1e98886
D = ced8a07374d72ffa84344453dde6d269cef9f8b16947b7f63b4168c6b1e98886
```

**A ≡ B、C ≡ D**：两棵树的产物都能由各自 revision 的发射器从同一份源码逐字节重放。差异是发射器差异，不是产物陈旧或生成参数差异。

两边的第 8 行（`c` 的声明）**逐字节相同**，都**没有** `!!`：

```kotlin
val c = run { val _s = s; val _i = pos; if (_i >= 0 && _i < _s.length) _s[_i].code else null }
```

即 `c` 的 Kotlin 存储是 `Int?`，冗余与否是**读取点**现象，不在声明点。这一点很重要：如果声明点提取（`val c = …!!`），三次读取都会落在非空 `Int` 上，根本不会有冗余 `!!`。

生成命令（本人在 B、D 各跑一次）：

```
# B（本 worktree，e54611c1；D 同理在 boring-wt-master-cc9957dd，cc9957dd）
export PATH="/nix/store/98pb92k7pi6g5cifmg872jn18kghaxw5-haxe-4.3.7/bin:\
/nix/store/rqx09a40a82di944xi6ydjyzx632av28-kotlin-2.4.10/bin:\
/nix/store/vd788darzi6n1k2zrj5x3kqgg03kbz93-nodejs-official-22.23.3/bin:$PATH"
export HAXELIB_PATH=/home/losses/Development/tq-workspace/.haxelib
haxe examples/kotlin.hxml          # 只生成产物；reference/kotlin/gen 已被 .gitignore 忽略
```

> `-lib boring` 投影陷阱已按任务说明绕开：本 worktree 建了 worktree 级 `.haxelib`（`boring` → 本 worktree），
> 未命中工作区级 `tq-workspace/.haxelib/boring`（指向 `boring-wt-growthkeyfix`，旧编译器）。
> 夹具 hxml 另走 `-cp packages/compiler` 显式源码根，两条路都不依赖投影。

## 2. 最小复现夹具（判据 2）

新增（本分支）：

- `tests/haxe/kotlin-redundant-assertion/probe/redundantassertion/RedundantAssertionOps.hx`
  sha256 `f45a2bc0b11171c8edfb84c5238a02533459059b9427b07b7c73a64699cc04aa`
- `tests/haxe/kotlin-redundant-assertion/probe/redundantassertion/MemberRegistryProbe.hx`
  sha256 `9a100b0210fb3333dccff52345d0bafc73d15e7d3457fabf716d929f5d20cc88`
- `tests/haxe/kotlin-redundant-assertion/kotlin-gen.hxml`（生成入口）
- `tests/haxe/kotlin-redundant-assertion/redundant-assertion.test.ts`（接入 `bun test tests/`，即 `bun run test` 收集域）

`RedundantAssertionOps.hx` 的测量函数就是 `StringTools.isSpace` 的尾巴，外加四个对照：

```haxe
public static function isSpace(s:String, pos:Int):Bool {          // 被测形状
    if (s.length == 0 || pos < 0 || pos >= s.length) return false;
    final c = s.charCodeAt(pos);
    return (c > 8 && c < 14) || c == 32;
}
public static function lowerBound(s:String, pos:Int):Bool { … return c > 8 && c < 14; }      // 无 || 尾巴
public static function threeReads(s:String, pos:Int):Bool { … }                              // 两条语句分隔
public static function eqRead(s:String, pos:Int):Bool { … return c == 32; }                  // 相等读取优先
public static function armRead(s:String, pos:Int, flag:Bool):Bool { … flag ? c > 8 : c < 14; } // 臂作用域对照
```

`MemberRegistryProbe.localMember` 是「同一事实、另一个读取点」的结构对照（§6.3）。

### 2.1 两侧生成 Kotlin（同一份源码，`RedundantAssertionOps.kt`）

主线（`e54611c1`，sha256 `590b42a46351f3d22e33fd9c0a120d6d39542a618868f46a7cb71d9989849bb6`）：

```kotlin
object RedundantAssertionOps {
    fun isSpace(s: String, pos: Int): Boolean {
        if ((s.length == 0 || pos < 0 || pos >= s.length)) { return false }
        val c = run { val _s = s; val _i = pos; if (_i >= 0 && _i < _s.length) _s[_i].code else null }
        return c!! > 8 && c!! < 14 || c == 32          // ← 第 9 行，第二个 c 多一个 !!
    }
    fun lowerBound(s: String, pos: Int): Boolean {
        val c = run { … }
        return c!! > 8 && c!! < 14                     // ← 第 14 行
    }
    fun threeReads(s: String, pos: Int): Boolean {
        val c = run { … }
        val above = c!! > 8                            // ← 第 19 行
        val below = c!! < 14                           // ← 第 20 行：跨语句也重复
        return above && below
    }
    fun eqRead(s: String, pos: Int): Boolean {
        val c = run { … }
        return c == 32                                 // ← 第 26 行：无 !!（相等读取规则）
    }
    fun armRead(s: String, pos: Int, flag: Boolean): Boolean {
        val c = run { … }
        return (if ((flag)) c!! > 8 else c!! < 14)     // ← 第 31 行：两臂都保留（正确）
    }
}
```

master（`cc9957dd`，sha256 `814c881fb7f536d2e982469a530fe9ae821e1de6a4fc2c18ba2816bea966f8be`）：**只有第 9、14、20 行的第二个 `!!` 消失**，其余逐字节相同（`eqRead`/`armRead` 两边一致）。

第 9 行差异：

```
主线 e54611c1:  return c!! > 8 && c!! < 14 || c == 32
master cc9957dd: return c!! > 8 && c < 14 || c == 32
```

### 2.2 夹具在收集套件里可跑

```
$ BORING_REDUNDANT_ASSERTION_OUT=/tmp/kra/fixture-out2 \
  bun test tests/haxe/kotlin-redundant-assertion/redundant-assertion.test.ts
(pass) a nullable local read after its own printed assertion takes no second assertion [30337.45ms]
 1 pass / 0 fail / 13 expect() calls
```

夹具的 3 个「记录值」常数与 3 条永久断言分开：永久断言（首次读取必须发 `!!`、相等读取不发、两臂都必须发）在修复后仍为真；记录值（`isSpace`/`lowerBound`/`threeReads` 各 2 个 `!!`，kotlinc 冗余警告 3 条）是**本次实测**，修复落地时必须一并下调，注释里写明了这一点。
负控（本人临时跑，跑完删除文件）：把记录值改成 `isSpace: 1` 与 `RECORDED_KOTLINC_REDUNDANT_WARNINGS = 0`，夹具立即变红并打印

```
error: isSpace emitted 2 assertions, recorded measurement is 1.
```

→ 夹具是真测量，不是同义反复。

### 2.3 顺带发现：`fixture-reachability` 的记录常数在 base 上已经过期（不属本任务改动）

`tests/fixture-reachability.test.ts:35` 记 `RECORDED_UNCOLLECTED = 35`（由 `71f39264` 落档）。在 base `e54611c1` 上实测：

```
$ bun test tests/fixture-reachability.test.ts
Expected: 35   Received: 36   (fail)
```

把本任务新增的夹具目录整个移出后再跑，**仍然 36**——即这条红与本夹具无关，是 base 上先于本任务存在的漂移（某个既有夹具目录在 `71f39264` 之后才带上 runner）。本任务**未**改动该常数（「不改现有任何测试期望」），仅在此记录：新增夹具本身 `hasCollectedTest = true`，不进入该计数。

## 3. 判据推导：三处 `c` 中哪几处应发 `!!`（判据 3）

表达式：`return (c > 8 && c < 14) || c == 32;`，`c: Int?`，`c` 是 **`final`、从不重赋值的局部**。
Kotlin 里 `&&` 比 `||` 结合更紧，故解析为 `(c > 8 && c < 14) || (c == 32)`。

### 读取 1（`c > 8`）：**必须发 `!!`**（或等价地在声明点提取一次）

Kotlin 的 `>` 是 `compareTo` 的运算符调用，**不允许对可空接收者做运算符调用**。实测（一手）：

```
$ kotlinc first-assert-missing.kt
first-assert-missing.kt:3:14: error: operator call is prohibited on a nullable receiver of type 'Int?'. Use '?.'-qualified call instead.
    return c > 8 && c < 14 || c == 32
             ^
first-assert-missing.kt:3:23: error: operator call is prohibited on a nullable receiver of type 'Int?'. Use '?.'-qualified call instead.
                      ^
rc=1
```

而声明点此时没有提取（本报告 §1.2 第 8 行），所以第一次读取必须自己带 `!!`。

### 读取 2（`c < 14`）：**不应发 `!!`**——它在语义上不可能抛，且已被 smart cast 定型为非空

两条依据，都是 Kotlin 语言规则层面：

**(a) 支配关系。** Kotlin 规定 `a && b` 先求值 `a`，仅当 `a` 为 true 才求值 `b`。要走到读取 2，`c!! > 8` 这个左操作数**必然已经被求值**。

**(b) `!!` 的定义。** Kotlin 的非空断言 `e!!` 的语义是：`e` 为 `null` 就抛 `NullPointerException`，否则返回 `e` 的**非空**值。它不是「条件检查」而是一次无条件判定——**能走到后面，就说明它没有抛**。所以读取 2 处的 `c` 必然非空，第二个 `!!` 的分支永不触发：**冗余**。

**(c) smart cast（这是让它「不需要 `!!` 也能编译」的那一步）。** Kotlin 的数据流分析会记录 `!!` 建立的非空事实，并在该断言支配的后续区间把稳定主体 smart cast 成非空类型。稳定性条件满足：`c` 是 `val` 局部、从不重赋值、不被可变闭包捕获（发射端自己的判据也是这个——`bodyWritesLocal` 的 `extractedLocals` 记录同样带 `!bodyWritesLocal(v.id)` 守卫，`KotlinExpr.hx:2675-2677`）。

kotlinc **自己把这个推理说了出来**（一手实测）：

```
mainline-StringTools.kt:9:28: warning: unnecessary non-null assertion (!!) on a non-null receiver of type 'Int'.
        return c!! > 8 && c!! < 14 || c == 32
                           ^^
```

`on a non-null receiver of type 'Int'` = 编译器在读取 2 处的 `c` 类型已经是 `Int`（不是 `Int?`）。也就是说，第二个 `!!` 不只是「看着多一个」，它作用的接收者已经被证明非空。

### 读取 3（`c == 32`）：**正确，但原因不是「证明机制覆盖到了」**

`operand()` 的断言分支带 `&& parent != OpEq && parent != OpNotEq`（`KotlinExpr.hx:3692`）：相等/不等操作数**永不**加 `!!`。Kotlin 的 `==` 是空安全的（`Int?.equals(Int)`，null 时为 false），与 Haxe 语义一致。
夹具里的 `eqRead` 把这个规则单独隔离了出来：`final c = …charCodeAt…; return c == 32;` —— **前面没有任何 `!!`**，两侧产物都是 `return c == 32`，无警告、rc=0。

所以任务描述里「三处 `c` 中只有第二个多发 `!!`，第三个正确 → 说明机制存在但覆盖不全」需要修正一处：
**第三个不是被证明机制救下的，而是被相等规则豁免的**。真正暴露问题的是「第一个发了、第二个又发一遍」，而这条规则的覆盖面由 `threeReads`（第 19/20 行跨语句也重复）和 `armRead`（两臂都必须发，正确）共同界定。

### 判据表

| 读取点 | 表达式片段 | 应否 `!!` | 理由 |
|---|---|---|---|
| 1 | `c > 8` | **应发** | 可空接收者的运算符调用非法；此前无任何非空事实 |
| 2 | `c < 14` | **不应发** | 被前一个 `!!` 支配；`!!` 非条件化，走到这里即已非空；smart cast 把它定型为 `Int` |
| 3 | `c == 32` | 不发（正确） | 相等操作数一律不加 `!!`（空安全相等），与证明机制无关 |
| 臂 | `flag ? c > 8 : c < 14` | **两处都应发** | 两臂互不支配，任一处丢了 `!!` kotlinc 直接拒绝 |

## 4. kotlinc 实测诊断与 `:80` 域（判据 4）

### 4.1 隔离单变量（一手）

| 输入 | kotlinc 2.4.10 结果 |
|---|---|
| `c!! > 8 && c!! < 14 \|\| c == 32` | rc=0，**1 条** warning：`redundant.kt:3:24: unnecessary non-null assertion (!!) on a non-null receiver of type 'Int'` |
| `c!! > 8 && c < 14 \|\| c == 32` | rc=0，**0 条** warning |
| `c > 8 && c < 14 \|\| c == 32`（首个断言缺失） | rc=1，**2 条 error**（nullable receiver 上禁止运算符调用） |

### 4.2 真的落在 `:80` 的域里（一手）

`docs/specs/style/02-translator-implementation-standard.md`：

- `:78` = "Generated code compiles without warnings on every target: kotlinc, rustc, … A translation that produces a warning is an emitter defect with the same severity as a translation that produces wrong output."
- `:80` = "Acceptance for any emitter change counts the warning lines in the target suite output that name files under the generated trees; the count is zero."

域的定义就是「命名生成树内文件的警告行」。本人用仓库既有命令（`package.json:11` 的同形调用）对主线 `e54611c1` 生成树实测：

```
$ kotlinc $(find reference/kotlin/gen -name '*.kt') -include-runtime -d /tmp/kra/gen-mainline.jar
RC=0
warning 行数（命名 reference/kotlin/gen/ 的）= 83
其中：reference/kotlin/gen/runtime/StringTools.kt:9:28: warning: unnecessary non-null assertion (!!) on a non-null receiver of type 'Int'.
```

单独编译该文件（两侧对照，一手）：

| 文件 | sha256 | kotlinc |
|---|---|---|
| 主线 `StringTools.kt` | `b7b22e37…285be0` | rc=0，**1 条** warning @ `9:28` |
| master `StringTools.kt` | `ced8a073…86b1e9` | rc=0，**0 条** warning |

**结论**：`unnecessary non-null assertion` 实测触发，且该文件正是 `reference/kotlin/gen/` 下的文件——落在 `:80` 的判定域内，是 `:78` 定义的发射器缺陷。

### 4.3 补充：自动门禁目前看不见它（转述 + 部分一手）

- 一手：CI 的警告提取域是 `grep -iE 'warn' "$LOG" | grep -E 'reference/[a-z0-9-]+/gen(-tests)?/'`（`.github/workflows/ci.yml:356`），`LOG` 是 `bun run test` 的日志（`:332`）。
- 一手：我抽查了收集域内会调 `kotlinc` 的测试，它们编译的是各自 `out/` 下的临时产物（如 `tests/ts/deferred-locals.test.ts:59` 编译 `output/boring/InvalidDeferredLocals.kt`，`tests/haxe/kotlin-var-field-smartcast/…:81` 编译 `out/kotlin-var-field-smartcast/…`），**不**编译 `reference/kotlin/gen`。
- 转述：`docs/architecture/evidence/zero-warning-gate-coverage/REPORT.md`（任务 `t-mum29cli-9c8w`）已判定该门禁在通过态下 grep 域为空、不拒警告。本人未重跑整条 `bun run test` 来复核这一点（成本高且与本任务判据无关）。

也就是说：**本缺陷落在标准域内，但当前自动门禁抓不到它**——这与「是不是缺陷」无关，但影响它是由谁发现的。

## 5. 机制定位（一手：读码 + 插桩实测）

### 5.1 主线的读取点问的是「源事实」，不是「已打印的断言」

主线 `e54611c1`，`packages/compiler/reflaxe/kotlin/kotlincompiler/KotlinExpr.hx`：

| 位置 | 内容 |
|---|---|
| `:3661` | `operand()` —— 裸局部参与比较时在这里加 `!!` |
| `:3670` | `final proven = valueProven(e);` |
| `:3692` | `&& parent != OpEq && parent != OpNotEq`（相等操作数豁免） |
| `:3696` | `rendered = hardenAppend(rendered, "!!");` |
| `:3701` | `addProofExpr(e);` —— **就在这里**把「已断言」写进记录 |
| `:2673 / :2677` | `addProofExpr`：`case TLocal(v): if (!bodyWritesLocal(v.id)) extractedLocals.set(v.id, true);` |
| `:2668` | `final extractedLocals:Map<Int, Bool> = [];` |
| `:3355` | `valueProven()` = `localPresent()`（`:3229`，源事实分析）`|| targetEntryLegal()` |
| `:3904` | `extractedLocals` 的**唯一查询读取点**（`extractedLocals.exists(v.id)`），在 `instanceField`（`:3854`）里；`:747/:760/:2707/:2715/:2718` 只是状态保存/快照内部拷贝 |

插桩实测（`-D kotlin_fold_debug`，`operand` 的 `!!` 分支内打印）：

```
# 主线 e54611c1，isSpace 的 c（TVar id=36265）：
EMITSTACK OPERAND proven=false id=36265 nullInit=false [c]     ← 第一次读取
EMITSTACK OPERAND proven=false id=36265 nullInit=false [c]     ← 第二次读取：仍 proven=false
```

即：**发射端打印了第一个 `!!`，第二个读取点问 `valueProven` 仍然回答 false。** 记录写了（`:3701` → `:2677`），但 `operand` 不查它。

### 5.2 master 的读取点问的是「已打印的断言」

master `cc9957dd` 同一个文件：

| 位置 | 内容 |
|---|---|
| `:3402` | `operand()` |
| `:3411` | `final proven = provenNonNull(e) \|\| guardProofBefore(e);` |
| `:2419 / :2422` | `addProofExpr`：`case TLocal(v): nonNullLocals.set(v.id, true);`（且 `if (!mutated.exists(v.id)) extractedLocals.set(...)`） |
| `:3146` | `provenNonNull()` 读 `nonNullLocals` |
| `:78` | `final nonNullLocals:Map<Int, Bool> = [];` |

同一插桩（master）：

```
# master cc9957dd，isSpace 的 c（TVar id=33164）：
EMITSTACK OPERAND proven=false id=33164 …     ← 只有一次：第二次读取的 proven 已为 true，分支未进入
```

（该 debug 行在 `!!` 分支体**内部**，被抑制的读取不打印任何行；这本身就是「抑制发生了」的观测。）

### 5.3 同一棵树、同一主体、两个读取点、两个答案（关键对照）

`MemberRegistryProbe.localMember` —— 一个从不重赋值的可空局部 `x`，先经成员访问读一次，再读一次：

```kotlin
fun localMember(o: MemberRegistryInner?): Boolean {
    val x = o
    val a = x!!.flag      // 第一次：断言
    return a && x.flag    // 第二次：成员访问路径查了 extractedLocals → 省掉 !!
}
```

两侧在 **`x` 的第二次读取上都抑制了 `!!`**：

```kotlin
// 主线 e54611c1（MemberRegistryProbe.kt sha256 14753de88d3895b9106420afee27f8a0eda49e1c9beba4a1620f9ddfa735b66c）
val a = x!!.flag!!      // 第一次：断言接收者（.flag 后多发一个 !!，与本判定无关）
return a && x.flag      // 第二次：成员访问路径查了 extractedLocals → 省掉 !!

// master cc9957dd（MemberRegistryProbe.kt sha256 061536c4cff1067876336eca980299a066b2ca999a7970402695e5379cde67ca）
val a = x!!.flag
return a && x.flag
```

两份产物只差 `.flag` 后那一个与本判定无关的 `!!`；**关于 `x` 的那一半逐字节相同**。
**`instanceField` 拿同一个 `extractedLocals` 成功抑制了 `x` 的第二次 `!!`，而 `operand` 对同样稳定的 `c` 没有抑制。** 这条对照把「无法证明」这一辩护彻底排除。

### 5.4 作用域纪律已经就位（说明修复不需要新机制）

`extractedLocals` 在每一个支配边界做快照/回滚：语句 `if`（`:1225`）、`while`（`:1253`）、`for`（`:1613`/`:1633`）、lambda（`:1896`）、值形式三元（`:1923`）、catch（`:2288`）。
一手验证这个纪律在两个读取点都有效：`armRead` 在**两侧**都发两个 `!!`、kotlinc **零警告**（§4.1）——若抑制忽略臂作用域，第二臂会丢 `!!` 并直接编译失败。这正是「修复 `operand` 时必须继续保持」的安全边界，已写进夹具的永久断言。

> 关于任务里点名的 `extractsAtDecl`（`:820`，条件含 `artifact.nullTestedAt(declaration)`）：本人确认它是**声明点**的判定，而本差异不在声明点——两棵树第 8 行逐字节相同、都无 `!!`。所以争论点不在 `extractsAtDecl` 一族，而在读取点 `operand` 的证明查询。本人**未**插桩 `extractsAtDecl` 去逐条拆开它对本例是哪一条合取为假（`!isNullType(v.t)` 与 `nullTestedAt` 两条都可能），这不影响本判定，但如实标注为未展开项。

## 6. 回归还是一贯差异（判据 5）

### 6.1 bisect：差异由单个 commit 引入（一手，逐字节）

候选来自 `git log -S 'guardProofBefore' -- packages/compiler/reflaxe/kotlin/kotlincompiler/KotlinExpr.hx` 的最新一条：`3fb8c565`
`feat(kotlin): consume local presence facts in function lowering`（2026-09-28 19:22，`arch/agent-guided-governance` 线，经 merge 进入 `ci/collected-suite-failure-attribution`）。
`git merge-base --is-ancestor 3fb8c565 cc9957dd` → **否**（master 早于它，2026-09-28 01:33）。该 commit 的 diff 把 `provenNonNull(e) || guardProofBefore(e)` 成批替换成 `valueProven(e)`，并新增 `KotlinPreparedFunction.hx`（master 树上没有这个文件，可自行核对）。

本人在 `/home/losses/Development/tq-workspace/boring-wt-bisect-3fb8c565`（普通挂载点，detached）用同一份夹具源码（`RedundantAssertionOps.hx` sha256 `f45a2bc0…`）在两处 revision 各生成一次：

| revision | `RedundantAssertionOps.kt` sha256 | `isSpace` 第 9 行 |
|---|---|---|
| `3fb8c565^` = `4581308dc501e3c8b59d5c31fa1943eecdbcb613` | `814c881fb7f536d2e982469a530fe9ae821e1de6a4fc2c18ba2816bea966f8be` | `return c!! > 8 && c < 14 \|\| c == 32` |
| `3fb8c565` = `3fb8c565336ab550dc8b9e956482f0ed6fbb4955` | `590b42a46351f3d22e33fd9c0a120d6d39542a618868f46a7cb71d9989849bb6` | `return c!! > 8 && c!! < 14 \|\| c == 32` |
| `e54611c1`（主线 tip） | `590b42a4…`（与 `3fb8c565` 相同） | `return c!! > 8 && c!! < 14 \|\| c == 32` |
| `cc9957dd`（master） | `814c881f…`（与 `3fb8c565^` 相同） | `return c!! > 8 && c < 14 \|\| c == 32` |

**`3fb8c565^` 的产物与 master 的产物逐字节相同；`3fb8c565` 的产物与主线 tip 的产物逐字节相同。** 所以：

- 这不是「master 与主线各有一套长期口径」的一贯差异；
- 这是 `ci/collected-suite-failure-attribution` 线上由 `3fb8c565` 引入、并在此后 10 个触碰该文件的 commit 中一直保留的**回归**；
- 该 commit 的 message/文档只声明「Kotlin 现在消费局部存在性事实，用在 **guarded reads** 与 target entry」，**没有**任何文字声明要放弃「已打印断言后的重复抑制」。因此这是一次**批量化替换的附带损失**，不是有记录的取舍。

### 6.2 一手 vs 转述

- **一手**：§1 全部哈希与行号、§2 夹具运行与负控、§3 判据（含 kotlinc 三个受控变体）、§4.1/§4.2 的全部 kotlinc rc 与警告文本、§5 的读码行号与插桩输出、§6.1 的 bisect 四格。
- **转述**：`docs/architecture/evidence/zero-warning-gate-coverage/REPORT.md` 对自动门禁抓不到警告的判定（§4.3 已标注）；任务描述里给定的两个产物事实（本人在 §1 已独立复核，结论一致）。
- **修正的转述**：任务描述说「第三个正确 → 机制存在但覆盖不全」。按 §3 的一手推导，第三个正确的直接原因是相等操作数豁免（`:3692`），不是证明机制覆盖；覆盖不全的证据应取 `threeReads`（跨语句重复）与 `operand`/`instanceField` 的对照（§5.3）。

## 7. 结论（判据 6）

**缺陷，且可定位到具体判据。**

- **为什么不是「可接受的保守发射」**：保守发射的正当理由是「发射端无法证明」。这里发射端**能**证明，而且已经证明了——`extractedLocals` 就是那条证明（由打印 `!!` 的同一个调用点写入，带 `!bodyWritesLocal` 守卫，并在所有支配边界快照回滚）。同一个事实，`instanceField` 消费、`operand` 不消费（§5.3）。所以不存在「跨 `&&` 的数据流无法建模」的困难：判定它冗余甚至不需要建模数据流——**`!!` 不是条件检查，走到第二个读取点就说明第一个没有抛**（§3(b)）。
- **具体判据**：
  1. `KotlinExpr.hx:3670` 的 `proven = valueProven(e)` 用源事实回答了渲染顺序问题；同一函数在 `:3701` 已经写下渲染顺序事实却不在 `:3670` 查询它。
  2. `extractedLocals` 的唯一查询读取点 `:3904` 只服务成员访问路径（`:3854`）。同一棵树内两个读取点对同一主体给出相反答案，与仓库契约 6「一个判断只能有一个来源」的取向相反（参见 `docs/architecture/evidence/kotlin-smartcast-predicate-conflict/CONFLICT.md` 对同类分裂的处置口径）。
  3. 该回归由 `3fb8c565` 引入，`3fb8c565^` 与 master 逐字节一致（§6.1）。
  4. 后果按仓库自己的标准定级：`02-translator-implementation-standard.md:78/:80` 把「生成代码产生警告」定为与错误输出同级的发射器缺陷，而实测警告就在 `reference/kotlin/gen/runtime/StringTools.kt:9:28`（§4.2）。
- **不夸大的部分**：这条 `!!` 不改变运行结果（第一个 `!!` 决定了语义），所以它是**警告级**缺陷，不是错值缺陷；修复不必新增机制，只需让 `operand`（及同族读取点）查询已有的 `extractedLocals`，并保住 `armRead` 那条支配边界。修复本身**不在本任务范围**，另立任务。

## 8. 复现步骤

```bash
export PATH="/nix/store/98pb92k7pi6g5cifmg872jn18kghaxw5-haxe-4.3.7/bin:\
/nix/store/rqx09a40a82di944xi6ydjyzx632av28-kotlin-2.4.10/bin:\
/nix/store/vd788darzi6n1k2zrj5x3kqgg03kbz93-nodejs-official-22.23.3/bin:$PATH"
export HAXELIB_PATH=/home/losses/Development/tq-workspace/.haxelib

# 1) 最小复现：夹具自跑（生成 + 读回 + kotlinc 实测）
cd /home/losses/Development/tq-workspace/boring-wt-redundant
BORING_REDUNDANT_ASSERTION_OUT=/tmp/kra/repro \
  bun test tests/haxe/kotlin-redundant-assertion/redundant-assertion.test.ts
cat /tmp/kra/repro/kotlinc.stderr.log        # 3 条 unnecessary non-null assertion

# 2) 接受域对照：整棵生成树
haxe examples/kotlin.hxml
sed -n '9p' reference/kotlin/gen/runtime/StringTools.kt
sha256sum reference/kotlin/gen/runtime/StringTools.kt
kotlinc $(find reference/kotlin/gen -name '*.kt') -include-runtime -d /tmp/kra/gen.jar 2>&1 \
  | grep -n "StringTools.kt"

# 3) master 侧（普通挂载点的 scratch worktree；dc-warn 是 fuse 挂载，不宜在其上编译）
#    已建：/home/losses/Development/tq-workspace/boring-wt-master-cc9957dd（detached cc9957dd）
#    重建命令：
#    cd boring-wt-mainline && git worktree add --detach ../boring-wt-master-cc9957dd cc9957dd
cd /home/losses/Development/tq-workspace/boring-wt-master-cc9957dd
haxe tests/haxe/kotlin-redundant-assertion/kotlin-gen.hxml   # 夹具已拷入
sha256sum out/kotlin-redundant-assertion/gen/redundantassertion/RedundantAssertionOps.kt
```

## 9. 未覆盖 / 未判定

- `extractsAtDecl`（`:820`）内部是哪一条合取对本例为假，未逐条插桩拆开（§5.4）；不影响本判定。
- 自动门禁抓不到该警告这一点采信既有审计（§4.3 已标转述），本人未重跑整条 `bun run test`。
- 本次只判定「同一稳定主体在已打印断言之后的重复 `!!`」这一形状。`reference/kotlin/gen` 整棵树实测有 **83** 条警告（其中 `unnecessary non-null assertion` 多条），它们形状各异、是否同因**未**判定，属于其它任务的射程。
- 未做任何发射器改动（任务非目标）；未改任何既有测试期望、P09 输入/基线与在途 Kotlin 修复。
