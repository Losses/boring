# 降级判定粒度审计（t-muk0xuwn-cr6e）

分支 audit/degradation-granularity，基线 pin 256d06bd（integration/cutover-pin）。
范围：五个目标 emitter 里决定「表达式在生成产物中的形态」的降级/包装判定点
（Array.from 包装、clone/to_string/to_vec 插入、!!/! 断言、resident 形态选择）的**判定依据**。

## 判据分级

| 判据 | 定义 | 静默失败风险 |
|---|---|---|
| 站点属性 | 静态类型 / 左值性 / 消费上下文（例：arraySlotDepth、isTypeCopy(targetType)） | 无（判据与判定同粒度） |
| 模块级属性 | RuntimeResidents.isResident(module) 等按模块计算的谓词 | 仅当参与**使用点**包装决策时属静默类 |
| 渲染文本 | StringTools.endsWith/startsWith(rendered, ...) | 仅当判错后产物仍编译且值测试仍绿时属静默类 |

静默失败类认定标准：判错不报错、产物仍编译、值测试仍绿（丢写 / 错值 / 静默复杂度爆炸）。
以下三类**不**属于静默失败，不修：

1. **幂等守卫（转换去重）**：!endsWith(x, ".clone()") 之类防止重复转换的守卫。
   判『真』失败只多一次 clone/to_string（语义等价、常数代价）；判『假』失败（漏转换）时
   Rust/Kotlin/Swift 的所有权移动与类型系统在编译期拒绝（E0382/E0308、kotlinc、swiftc）。
2. **句法归一化**：括号剥离、块形状识别、缩进/分号/字面量小数点补全。判错由目标编译器
   语法/类型错误暴露。
3. **命名/声明级**：get_、_Impl_、Fault 后缀、std/haxe 模块前缀、导入路径。不参与
   使用点形态；判错产生重复定义/缺失导入等编译期可见错误。

模块级 isResident（108 处）逐条复核结论：全部为**声明/形态选择**（文件放置、导入形态、
类型形态、扫描范围）或 spec 20 明文规定的模块级 Int32Array 形态前置条件——按任务非目标
（不动 spec 已明文的降级规则）维持。唯一参与使用点包装判定的实例（TsExpr.hx field()
FStatic 分支）已由 pin 内的 426f8876 收敛为站点级 arraySlotDepth（仅 Array<T> 槽位包
Array.from，形参解不出则生成期 Context.error）。

## 本轮修复：DegradedLvalueGuard（消费端左值边界）

两个范例缺陷的共同失败面不在「是否插入转换」的生成端，而在**消费端把带转换后缀的渲染
文本当作左值**：(v[i]).clone().field = v 形状上写进临时、静默丢写。修复落在五个目标共用
的 packages/compiler/AssignTargetPlan.hx（Rust/Kotlin/TS/Swift/Dart 的 assignTarget 全部
经由它）：

- lvalueConversionSuffixes：.clone()、.to_string()、.to_vec()、.to_owned()、.toOwned()、
  .unwrap()、.unwrap_or_default()、.slice()、.copy()、.toList()、.toMutableList()、
  .toUString()
- lvalueConversionWrappers：Array.from(、toMutableList(、toList(、List.from(（顶层包裹
  判定，配平括号）
- 判据是 place 路径感知的（lvalueConversionHit，纯文本谓词，可无 TypedExpr 探测）：先
  屏蔽内部可变性读者 lock().unwrap() / borrow[_mut]().unwrap() / borrow[_mut]()（它们
  产 place，写入经解引用落在 Mutex/RefCell 内部，不丢写），再在「转换位于 place 路径
  终点（整条目标文本以转换结尾且头部无顶层解引用 *）」或「转换处于路径中途（后随 . 或
  [）」时报 Context.error，带 file/pos（站点位置），**不静默降级**。
- 对照形状（tests/degradation-probe/guard-probe.hxml，GUARD-PROBE-OK / RC=0）：
  *remaining.lock().unwrap() → 不报（deref 头 + 内部可变性读者）；(v[0]).clone().field、
  self.f.clone()、x.to_string()、opt.unwrap()、Array.from(RANGES) → 报。

该修复不改变任何合法使用点的形态（见下方零漂移证据），只把「转换文本流入左值」从静默
丢写升级为生成期报错。

## SOP 逐条证据

### 1) 全部候选判定点清单

枚举方式：grep -rn 'StringTools.endsWith|StringTools.startsWith' 与 'isResident'
（去 Test 文件）覆盖五个目标的全部文本启发式与 resident 判定点，共 436 条。逐条标注见
文末「逐条清单」表（类别 / 静默失败类 / 结论三列）。分布：命名/声明级 57、句法归一化
约 49、形态识别约 100、幂等守卫（转换/断言去重）约 84、类型文本判定 29、模块级
resident 108+1（已收敛）。

### 2) 静默失败类的处置

- RustExpr.hx:4702（armOwnershipClone）、:5941（BranchArmMoveClone）、:5957
  （cloneBorrowedReceiverBranch）、:565（Some 边界去重）：范例缺陷族。生成端的文本去重
  语义保留（漏 clone 被 rustc 拒绝，非静默）；其静默面（转换文本流入左值）由
  DegradedLvalueGuard 在生成期报错并带 file/pos。**已修（消费端）。**
- 其余 .clone()/.to_string()/.to_vec()/.unwrap() 后缀判定（约 60 处）：幂等去重（理由见
  上），消费端同样受 DegradedLvalueGuard 保护。不修。
- Kotlin !!、Swift ! 去重（18 处）：漏加/重复加均被 kotlinc/swiftc 编译期拒绝。不修。
- isResident 108 处：声明级/spec 规定形态，非使用点包装；唯一使用点实例已在 pin 内收敛
  （426f8876）。不修，理由如上。

### 3) 改前/改后生成产物差异

**DegradedLvalueGuard 零漂移证明**：以 stash/恢复方式对同一棵树分别用「pin」与
「pin + 本轮改动」驱动同一 driver 生成：

- boring 自有项目 ts/kotlin/rust 三棵树：diff -rq 均**为空**（0 文件差异）。
- tiqian 项目 ts、kotlin-f64、protocol-rust、protocol-kotlin 四棵树：diff -rq 均**为空**。

即受保护的使用点只在非法上下文（转换文本流入左值）改变行为——从静默产码变为生成期
报错——其余使用点形态完全不变。

**426f8876（范例 1）的改前/改后形态差异（ts）**：以 426f8876^（f1b28bd3）与 pin 各生成
tiqian ts 树，差异恰为 13 个数据表消费文件，全部同形：

    - let high = Math.trunc(Array.from(RANGES).length >> 1) - 1;   // 每次访问复制整表
    + let high = Math.trunc(RANGES.length >> 1) - 1;               // 原生读取
    - const start = Array.from(RANGES)[base]!;
    + const start = RANGES[base]!;

即使用点只在「非 Array<T> 消费槽位」收回转换，其余树无差异。rust/kotlin 侧由本轮零漂移
证明与各自既有 suite 覆盖（VectorSort 元素搬移的 Rust/Kotlin 版本由 cargo test 与 kotlin
stage1 套件运行）。

### 4) 运行时见证

tests/ts/degradation-lvalue.test.ts（bun test，运行生成产物本体）：

1. 数组元素槽位写回后读回：VectorSort.byCodePoint 反复执行 records[read + 1] =
   records[read]，断言读回顺序、值与规模（长度 4、原地同引用）。
2. 相邻键驱动多次元素搬移后按下标读回字段值（out[0].codePoint === 10）。
3. 数据表访问规模见证：ScriptEvidenceTable.classify 全域探针（0..0x10FFFF 及越界），
   断言查表路径走完整 Int32Array 且无逐访问复制（与 data-tables.test.ts 的形状断言互补，
   本条为值/行为断言）。

本轮唯一的生成端行为变更是「静默产码 → 生成期报错」，故其见证为生成期（file/pos
报错），运行时见证由上述写回-读回用例承担；形状断言不作为证据提交。

### 5) 审计清单入库

见下表（436 行）：位置 / 类别 / 是否静默失败类 / 结论。本轮不修的条目均在结论列写明
理由（幂等去重 / 句法归一化 / 命名声明级 / 类型级 / spec 规定模块形态）。

## 逐条清单

| 位置 | 类别 | 静默失败类 | 结论 |
|---|---|---|---|
| ts/tscompiler/TsDecl.hx:460 | 命名/声明级（非形态判定） | 否 | 命名约定/模块前缀判定，不参与使用点形态。不修。 |
| ts/tscompiler/TsDecl.hx:477 | 命名/声明级（非形态判定） | 否 | 命名约定/模块前缀判定，不参与使用点形态。不修。 |
| ts/tscompiler/TsImports.hx:350 | 命名/声明级（非形态判定） | 否 | 导入路径/文件前缀判定，不参与使用点形态。不修。 |
| ts/tscompiler/TsImports.hx:402 | 命名/声明级（非形态判定） | 否 | 导入路径/文件前缀判定，不参与使用点形态。不修。 |
| ts/tscompiler/TsExpr.hx:439 | 幂等守卫（空断言去重） | 否 | Swift ! 去重：漏加/重复加均被 swiftc 编译错误拒绝。不修。 |
| ts/tscompiler/TsExpr.hx:1740 | 命名/声明级（非形态判定） | 否 | 命名约定/模块前缀判定，不参与使用点形态。不修。 |
| ts/tscompiler/TsExpr.hx:1834 | 命名/声明级（非形态判定） | 否 | 命名约定/模块前缀判定，不参与使用点形态。不修。 |
| ts/tscompiler/TsExpr.hx:3360 | 命名/声明级（非形态判定） | 否 | 生成物行前缀剥离（文档行处理）。不修。 |
| rust/rustcompiler/RustImports.hx:134 | 命名/声明级（非形态判定） | 否 | 导入路径/文件前缀判定，不参与使用点形态。不修。 |
| rust/rustcompiler/RustImports.hx:231 | 命名/声明级（非形态判定） | 否 | 导入路径/文件前缀判定，不参与使用点形态。不修。 |
| rust/rustcompiler/RustShapeParse.hx:39 | 句法归一化（括号/块形状） | 否 | 括号剥离与块形状识别；判错只影响括号写法且由 rustc 语法/类型错误暴露。不修。 |
| rust/rustcompiler/RustShapeParse.hx:41 | 句法归一化（括号/块形状） | 否 | 括号剥离与块形状识别；判错只影响括号写法且由 rustc 语法/类型错误暴露。不修。 |
| rust/rustcompiler/RustShapeParse.hx:47 | 句法归一化（括号/块形状） | 否 | 括号剥离与块形状识别；判错只影响括号写法且由 rustc 语法/类型错误暴露。不修。 |
| rust/rustcompiler/RustShapeParse.hx:52 | 句法归一化（括号/块形状） | 否 | 括号剥离与块形状识别；判错只影响括号写法且由 rustc 语法/类型错误暴露。不修。 |
| rust/rustcompiler/RustShapeParse.hx:58 | 句法归一化（括号/块形状） | 否 | 括号剥离与块形状识别；判错只影响括号写法且由 rustc 语法/类型错误暴露。不修。 |
| rust/rustcompiler/RustShapeParse.hx:66 | 句法归一化（括号/块形状） | 否 | 括号剥离与块形状识别；判错只影响括号写法且由 rustc 语法/类型错误暴露。不修。 |
| rust/rustcompiler/RustShapeParse.hx:68 | 句法归一化（括号/块形状） | 否 | 括号剥离与块形状识别；判错只影响括号写法且由 rustc 语法/类型错误暴露。不修。 |
| rust/rustcompiler/RustShapeParse.hx:83 | 句法归一化（括号/块形状） | 否 | 括号剥离与块形状识别；判错只影响括号写法且由 rustc 语法/类型错误暴露。不修。 |
| rust/rustcompiler/RustShapeParse.hx:85 | 句法归一化（括号/块形状） | 否 | 括号剥离与块形状识别；判错只影响括号写法且由 rustc 语法/类型错误暴露。不修。 |
| rust/rustcompiler/RustShapeParse.hx:91 | 句法归一化（括号/块形状） | 否 | 括号剥离与块形状识别；判错只影响括号写法且由 rustc 语法/类型错误暴露。不修。 |
| rust/rustcompiler/RustShapeParse.hx:96 | 句法归一化（括号/块形状） | 否 | 括号剥离与块形状识别；判错只影响括号写法且由 rustc 语法/类型错误暴露。不修。 |
| rust/rustcompiler/RustShapeParse.hx:103 | 句法归一化（括号/块形状） | 否 | 括号剥离与块形状识别；判错只影响括号写法且由 rustc 语法/类型错误暴露。不修。 |
| rust/rustcompiler/RustShapeParse.hx:113 | 句法归一化（括号/块形状） | 否 | 括号剥离与块形状识别；判错只影响括号写法且由 rustc 语法/类型错误暴露。不修。 |
| rust/rustcompiler/RustShapeParse.hx:122 | 句法归一化（括号/块形状） | 否 | 括号剥离与块形状识别；判错只影响括号写法且由 rustc 语法/类型错误暴露。不修。 |
| rust/rustcompiler/RustShapeParse.hx:125 | 句法归一化（括号/块形状） | 否 | 括号剥离与块形状识别；判错只影响括号写法且由 rustc 语法/类型错误暴露。不修。 |
| rust/rustcompiler/RustShapeParse.hx:132 | 句法归一化（括号/块形状） | 否 | 括号剥离与块形状识别；判错只影响括号写法且由 rustc 语法/类型错误暴露。不修。 |
| rust/rustcompiler/RustShapeParse.hx:138 | 句法归一化（括号/块形状） | 否 | 括号剥离与块形状识别；判错只影响括号写法且由 rustc 语法/类型错误暴露。不修。 |
| rust/rustcompiler/RustShapeParse.hx:140 | 句法归一化（括号/块形状） | 否 | 括号剥离与块形状识别；判错只影响括号写法且由 rustc 语法/类型错误暴露。不修。 |
| rust/rustcompiler/RustShapeParse.hx:142 | 句法归一化（括号/块形状） | 否 | 括号剥离与块形状识别；判错只影响括号写法且由 rustc 语法/类型错误暴露。不修。 |
| rust/rustcompiler/RustShapeParse.hx:146 | 句法归一化（括号/块形状） | 否 | 括号剥离与块形状识别；判错只影响括号写法且由 rustc 语法/类型错误暴露。不修。 |
| rust/rustcompiler/RustShapeParse.hx:164 | 句法归一化（括号/块形状） | 否 | 括号剥离与块形状识别；判错只影响括号写法且由 rustc 语法/类型错误暴露。不修。 |
| rust/rustcompiler/RustShapeParse.hx:170 | 句法归一化（括号/块形状） | 否 | 括号剥离与块形状识别；判错只影响括号写法且由 rustc 语法/类型错误暴露。不修。 |
| rust/rustcompiler/RustShapeParse.hx:215 | 句法归一化（括号/块形状） | 否 | 括号剥离与块形状识别；判错只影响括号写法且由 rustc 语法/类型错误暴露。不修。 |
| rust/rustcompiler/RustShapeParse.hx:217 | 句法归一化（括号/块形状） | 否 | 括号剥离与块形状识别；判错只影响括号写法且由 rustc 语法/类型错误暴露。不修。 |
| rust/rustcompiler/RustShapeParse.hx:225 | 句法归一化（括号/块形状） | 否 | 括号剥离与块形状识别；判错只影响括号写法且由 rustc 语法/类型错误暴露。不修。 |
| rust/rustcompiler/RustShapeParse.hx:320 | 句法归一化（括号/块形状） | 否 | 括号剥离与块形状识别；判错只影响括号写法且由 rustc 语法/类型错误暴露。不修。 |
| rust/rustcompiler/RustShapeParse.hx:331 | 句法归一化（括号/块形状） | 否 | 括号剥离与块形状识别；判错只影响括号写法且由 rustc 语法/类型错误暴露。不修。 |
| rust/rustcompiler/Compiler.hx:1152 | 命名/声明级（非形态判定） | 否 | 命名约定/模块前缀判定，不参与使用点形态。不修。 |
| rust/rustcompiler/Compiler.hx:1153 | 命名/声明级（非形态判定） | 否 | 命名约定/模块前缀判定，不参与使用点形态。不修。 |
| rust/rustcompiler/Compiler.hx:1327 | 命名/声明级（非形态判定） | 否 | 命名约定/模块前缀判定，不参与使用点形态。不修。 |
| rust/rustcompiler/Compiler.hx:1328 | 命名/声明级（非形态判定） | 否 | 命名约定/模块前缀判定，不参与使用点形态。不修。 |
| rust/rustcompiler/Compiler.hx:1645 | 命名/声明级（非形态判定） | 否 | 命名约定/模块前缀判定，不参与使用点形态。不修。 |
| rust/rustcompiler/Compiler.hx:1646 | 命名/声明级（非形态判定） | 否 | 命名约定/模块前缀判定，不参与使用点形态。不修。 |
| rust/rustcompiler/Compiler.hx:1749 | 命名/声明级（非形态判定） | 否 | 命名约定/模块前缀判定，不参与使用点形态。不修。 |
| rust/rustcompiler/Compiler.hx:1750 | 命名/声明级（非形态判定） | 否 | 命名约定/模块前缀判定，不参与使用点形态。不修。 |
| rust/rustcompiler/Compiler.hx:1882 | 命名/声明级（非形态判定） | 否 | 命名约定/模块前缀判定，不参与使用点形态。不修。 |
| rust/rustcompiler/Compiler.hx:1883 | 命名/声明级（非形态判定） | 否 | 命名约定/模块前缀判定，不参与使用点形态。不修。 |
| rust/rustcompiler/ParenFold.hx:70 | 句法归一化（括号/块形状） | 否 | 括号剥离与块形状识别；判错只影响括号写法且由 rustc 语法/类型错误暴露。不修。 |
| rust/rustcompiler/ParenFold.hx:71 | 句法归一化（括号/块形状） | 否 | 括号剥离与块形状识别；判错只影响括号写法且由 rustc 语法/类型错误暴露。不修。 |
| rust/rustcompiler/ParenFold.hx:87 | 句法归一化（括号/块形状） | 否 | 括号剥离与块形状识别；判错只影响括号写法且由 rustc 语法/类型错误暴露。不修。 |
| rust/rustcompiler/ParenFold.hx:95 | 句法归一化（括号/块形状） | 否 | 括号剥离与块形状识别；判错只影响括号写法且由 rustc 语法/类型错误暴露。不修。 |
| rust/rustcompiler/ParenFold.hx:123 | 句法归一化（括号/块形状） | 否 | 括号剥离与块形状识别；判错只影响括号写法且由 rustc 语法/类型错误暴露。不修。 |
| rust/rustcompiler/ParenFold.hx:135 | 句法归一化（括号/块形状） | 否 | 括号剥离与块形状识别；判错只影响括号写法且由 rustc 语法/类型错误暴露。不修。 |
| rust/rustcompiler/RustDecl.hx:910 | 形态识别（字面量形状） | 否 | 判断诊断消息是否已是字符串字面量；漏判由 rustc 语法错误暴露。不修。 |
| rust/rustcompiler/RustDecl.hx:1162 | 命名/声明级（非形态判定） | 否 | 命名约定/模块前缀判定，不参与使用点形态。不修。 |
| rust/rustcompiler/RustDecl.hx:1550 | 类型文本判定（类型级） | 否 | 以类型渲染文本判定，属类型级判据（站点属性的投影）。不改。 |
| rust/rustcompiler/RustDecl.hx:1555 | 类型文本判定（类型级） | 否 | 以类型渲染文本判定，属类型级判据（站点属性的投影）。不改。 |
| rust/rustcompiler/RustDecl.hx:1825 | 句法归一化（缩进） | 否 | 去缩进归一化，语义无关。不修。 |
| rust/rustcompiler/RustDecl.hx:2181 | 类型文本判定（类型级） | 否 | 以类型渲染文本判定，属类型级判据（站点属性的投影）。不改。 |
| rust/rustcompiler/RustDecl.hx:2182 | 类型文本判定（类型级） | 否 | 以类型渲染文本判定，属类型级判据（站点属性的投影）。不改。 |
| rust/rustcompiler/RustDecl.hx:2183 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustDecl.hx:2224 | 类型文本判定（类型级） | 否 | argType 类型文本判定。不改。 |
| rust/rustcompiler/RustDecl.hx:2230 | 类型文本判定（类型级） | 否 | 以类型渲染文本判定，属类型级判据（站点属性的投影）。不改。 |
| rust/rustcompiler/RustDecl.hx:2275 | 形态识别（字面量形状） | 否 | 字符串字面量补 to_string；漏判/误判均被 rustc E0308 拒绝。不修。 |
| rust/rustcompiler/RustDecl.hx:2279 | 类型文本判定（类型级） | 否 | 以类型渲染文本判定，属类型级判据（站点属性的投影）。不改。 |
| rust/rustcompiler/RustDecl.hx:2280 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustDecl.hx:2281 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustDecl.hx:2329 | 类型文本判定（类型级） | 否 | 以类型渲染文本判定，属类型级判据（站点属性的投影）。不改。 |
| rust/rustcompiler/RustDecl.hx:2353 | 命名/声明级（非形态判定） | 否 | 命名约定/模块前缀判定，不参与使用点形态。不修。 |
| rust/rustcompiler/RustDecl.hx:3133 | 命名/声明级（非形态判定） | 否 | 命名约定/模块前缀判定，不参与使用点形态。不修。 |
| rust/rustcompiler/RustConversions.hx:77 | 句法归一化（括号/块形状） | 否 | 括号剥离与块形状识别；判错只影响括号写法且由 rustc 语法/类型错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:469 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:473 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:562 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:565 | 幂等守卫（转换去重）→ 消费端已设防 | 是 | Some 包裹边界的去重：漏包时值移动被 rustc 拒绝（非静默），重复包语义等价；消费端由 DegradedLvalueGuard 覆盖。已修（消费端）。 |
| rust/rustcompiler/RustExpr.hx:566 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:711 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:1470 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:1508 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:1525 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:1579 | 形态识别（Option 解包形态追踪） | 否 | forcingReadLocals 追踪：漏判由 rustc Option 类型不匹配拒绝；误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:1637 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:1671 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:1673 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:1723 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:1774 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:1855 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:1866 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:1894 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:1900 | 类型文本判定（类型级） | 否 | 以类型渲染文本判定，属类型级判据（站点属性的投影）。不改。 |
| rust/rustcompiler/RustExpr.hx:1909 | 类型文本判定（类型级） | 否 | 以类型渲染文本判定，属类型级判据（站点属性的投影）。不改。 |
| rust/rustcompiler/RustExpr.hx:1912 | 类型文本判定（类型级） | 否 | 以类型渲染文本判定，属类型级判据（站点属性的投影）。不改。 |
| rust/rustcompiler/RustExpr.hx:1917 | 类型文本判定（类型级） | 否 | 以类型渲染文本判定，属类型级判据（站点属性的投影）。不改。 |
| rust/rustcompiler/RustExpr.hx:1956 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:1957 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:1968 | 类型文本判定（类型级） | 否 | 以类型渲染文本判定，属类型级判据（站点属性的投影）。不改。 |
| rust/rustcompiler/RustExpr.hx:1969 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:1993 | 类型文本判定（类型级） | 否 | 以类型渲染文本判定，属类型级判据（站点属性的投影）。不改。 |
| rust/rustcompiler/RustExpr.hx:2049 | 命名/声明级（非形态判定） | 否 | 命名约定/模块前缀判定，不参与使用点形态。不修。 |
| rust/rustcompiler/RustExpr.hx:2095 | 命名/声明级（非形态判定） | 否 | 命名约定/模块前缀判定，不参与使用点形态。不修。 |
| rust/rustcompiler/RustExpr.hx:2182 | 命名/声明级（非形态判定） | 否 | 命名约定/模块前缀判定，不参与使用点形态。不修。 |
| rust/rustcompiler/RustExpr.hx:2339 | 命名/声明级（非形态判定） | 否 | 命名约定/模块前缀判定，不参与使用点形态。不修。 |
| rust/rustcompiler/RustExpr.hx:2365 | 命名/声明级（非形态判定） | 否 | 命名约定/模块前缀判定，不参与使用点形态。不修。 |
| rust/rustcompiler/RustExpr.hx:3387 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:3394 | 类型文本判定（类型级） | 否 | 以类型渲染文本判定，属类型级判据（站点属性的投影）。不改。 |
| rust/rustcompiler/RustExpr.hx:3424 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:3971 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:3978 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:3992 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:4049 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:4065 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:4066 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:4070 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:4107 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:4108 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:4109 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:4140 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:4141 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:4142 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:4169 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:4170 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:4171 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:4351 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:4366 | 形态识别（收窄绑定追踪） | 否 | 收窄绑定名匹配；误判导致冗余收窄判定，漏判由 rustc 拒绝。不修。 |
| rust/rustcompiler/RustExpr.hx:4393 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:4396 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:4397 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:4398 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:4538 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:4581 | 调试痕迹（非判定） | 否 | emissionTrace 位置参数；无产物影响。不修。 |
| rust/rustcompiler/RustExpr.hx:4608 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:4686 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:4687 | 形态识别（解引用前缀） | 否 | 4702 同函数（narrowedText '*' 前缀识别）；漏/误由 rustc 类型不匹配拒绝；消费端由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:4688 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:4689 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:4702 | 幂等守卫（转换去重）→ 消费端已设防 | 是 | 本条即范例缺陷族：endsWith('.clone()') 去重 + 消费方把转换文本当左值 → 静默丢写。本轮在 AssignTargetPlan.assignTarget 增加 DegradedLvalueGuard（生成期 Context.error，带 file/pos），转换文本流入赋值目标即报错；本条去重语义保留。已修（消费端）。 |
| rust/rustcompiler/RustExpr.hx:4718 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:4749 | 句法归一化（块形状） | 否 | ({…}) 块形状识别；判错由 rustc 语法错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:4752 | 形态识别（解引用前缀） | 否 | 同 4687。不修。 |
| rust/rustcompiler/RustExpr.hx:4781 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:4782 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:4788 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:4789 | 形态识别（解引用前缀） | 否 | 匹配臂 Some 包裹的前缀识别；漏/误均被 rustc 类型不匹配拒绝。不修。 |
| rust/rustcompiler/RustExpr.hx:4790 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:4913 | 句法归一化（浮点字面量形状） | 否 | 字面量小数点补全；判错由 rustc 语法错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:5050 | 幂等守卫（转换去重） | 否 | 数组字面量元素 clone 去重；漏 clone → vec! 宏内值移动被 rustc E0382 拒绝，非静默。不修。 |
| rust/rustcompiler/RustExpr.hx:5148 | 幂等守卫（方法调用去重） | 否 | is_none() 后缀识别；漏判由 rustc bool/Option 类型错误拒绝。不修。 |
| rust/rustcompiler/RustExpr.hx:5150 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:5158 | 站点属性 + 去重 | 否 | 元素文本选择以 AST 形状（TConst/TLocal）为主判据，文本后缀仅去重；漏 clone 由 rustc E0382 拒绝。不修。 |
| rust/rustcompiler/RustExpr.hx:5418 | 形态识别（元组字段追踪） | 否 | 替换表后缀追踪；误判为冗余判定，漏判由 rustc 拒绝。不修。 |
| rust/rustcompiler/RustExpr.hx:5910 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:5941 | 幂等守卫（转换去重）→ 消费端已设防 | 是 | 同 4702 族（BranchArmMoveClone 去重）。漏 clone 由 rustc E0382 拒绝；转换文本流入左值由 DegradedLvalueGuard 生成期报错。已修（消费端）。 |
| rust/rustcompiler/RustExpr.hx:5953 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:5957 | 幂等守卫（转换去重）→ 消费端已设防 | 是 | 同 4702 族（cloneBorrowedReceiverBranch 去重）。同上。已修（消费端）。 |
| rust/rustcompiler/RustExpr.hx:6122 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:6177 | 句法归一化（分号） | 否 | 语句分号归一化。不修。 |
| rust/rustcompiler/RustExpr.hx:6305 | 命名/声明级（非形态判定） | 否 | std/runtime 模块前缀判定。不修。 |
| rust/rustcompiler/RustExpr.hx:6306 | 命名/声明级（非形态判定） | 否 | 命名约定/模块前缀判定，不参与使用点形态。不修。 |
| rust/rustcompiler/RustExpr.hx:6372 | 类型文本判定（类型级） | 否 | 以类型渲染文本判定，属类型级判据（站点属性的投影）。不改。 |
| rust/rustcompiler/RustExpr.hx:6439 | 类型文本判定（类型级） | 否 | 以类型渲染文本判定，属类型级判据（站点属性的投影）。不改。 |
| rust/rustcompiler/RustExpr.hx:6692 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:6693 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:7082 | 形态识别（.len() 后缀） | 否 | len() 识别用于整除特判；漏判由 rustc 类型错误拒绝。不修。 |
| rust/rustcompiler/RustExpr.hx:7264 | 类型文本判定（类型级） | 否 | u32 后缀（reinterpret 已转换文本）判定；属转换后文本的类型标记，误判由 rustc E0308 拒绝。不修。 |
| rust/rustcompiler/RustExpr.hx:7270 | 类型文本判定（类型级） | 否 | 同 7264（u32 reinterpret 标记）；误判由 rustc E0308 拒绝。不修。 |
| rust/rustcompiler/RustExpr.hx:7343 | 类型文本判定（类型级） | 否 | 以类型渲染文本判定，属类型级判据（站点属性的投影）。不改。 |
| rust/rustcompiler/RustExpr.hx:7508 | 句法归一化（match 块括号） | 否 | (match 剥外层括号；判错由 rustc 语法错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:7509 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:7511 | 句法归一化（match 块括号） | 否 | 同上。不修。 |
| rust/rustcompiler/RustExpr.hx:7512 | 句法归一化（match 块括号） | 否 | 同上。不修。 |
| rust/rustcompiler/RustExpr.hx:7522 | 句法归一化（match 块括号） | 否 | 同上。不修。 |
| rust/rustcompiler/RustExpr.hx:7537 | 形态识别（类型构造前缀） | 否 | i32:: 前缀识别；误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:7550 | 形态识别（类型构造前缀） | 否 | 同上。不修。 |
| rust/rustcompiler/RustExpr.hx:7646 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:7657 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:7902 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:7925 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:8243 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:9175 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:9176 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:9178 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:9190 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:9402 | 命名/声明级（非形态判定） | 否 | 命名约定/模块前缀判定，不参与使用点形态。不修。 |
| rust/rustcompiler/RustExpr.hx:9607 | 形态识别（类型构造前缀） | 否 | usize:: 前缀识别。不修。 |
| rust/rustcompiler/RustExpr.hx:9608 | 形态识别（类型构造前缀） | 否 | 同上。不修。 |
| rust/rustcompiler/RustExpr.hx:9631 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:9844 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:10259 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:10263 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:10695 | 幂等守卫（unwrap_or_default 去重） | 否 | 漏判由 rustc 类型错误拒绝。不修。 |
| rust/rustcompiler/RustExpr.hx:11253 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:12119 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:12132 | 命名/声明级（非形态判定） | 否 | 命名约定/模块前缀判定，不参与使用点形态。不修。 |
| rust/rustcompiler/RustExpr.hx:12172 | 命名/声明级（非形态判定） | 否 | 命名约定/模块前缀判定，不参与使用点形态。不修。 |
| rust/rustcompiler/RustExpr.hx:12210 | 幂等守卫（传播去重） | 否 | fallible 后缀去重；漏判由 rustc 拒绝。不修。 |
| rust/rustcompiler/RustExpr.hx:12211 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:12315 | 幂等守卫（转换去重） | 否 | 转换后缀去重；同 4702 族判定，消费端由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:12316 | 幂等守卫（转换去重） | 否 | 同上。不修。 |
| rust/rustcompiler/RustExpr.hx:12360 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:12367 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:12373 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:12374 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:12387 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:12388 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:12389 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:12390 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:12407 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:12450 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:12489 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:12490 | 形态识别（解引用前缀） | 否 | (* 前缀识别。不修。 |
| rust/rustcompiler/RustExpr.hx:12492 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |