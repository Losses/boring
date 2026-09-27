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
- 命中即 Context.error，带 file/pos（站点位置），**不静默降级**。

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
| rust/rustcompiler/RustExpr.hx:12493 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:12513 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:12514 | 幂等守卫（转换去重） | 否 | 转换后缀去重。不修。 |
| rust/rustcompiler/RustExpr.hx:12527 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:12559 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:12567 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:12593 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:12616 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:12623 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:12673 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:12933 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:13055 | 形态识别（类型构造前缀） | 否 | u32:: 前缀识别。不修。 |
| rust/rustcompiler/RustExpr.hx:13078 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:14319 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:14321 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:14331 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:14332 | 句法归一化（块形状） | 否 | { 块前缀识别。不修。 |
| rust/rustcompiler/RustExpr.hx:14383 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:14438 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:14455 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:14471 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:14673 | 类型文本判定（类型级） | 否 | 以类型渲染文本判定，属类型级判据（站点属性的投影）。不改。 |
| rust/rustcompiler/RustExpr.hx:14683 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:14710 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:14711 | 形态识别（解引用前缀） | 否 | (* 前缀识别。不修。 |
| rust/rustcompiler/RustExpr.hx:14722 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:14760 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:14775 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:14776 | 形态识别（借用前缀） | 否 | 借用前缀识别；漏判由 rustc 拒绝。不修。 |
| rust/rustcompiler/RustExpr.hx:14778 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:14779 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:14841 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:14879 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:14887 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:14922 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:14928 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:14962 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:15025 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:15026 | 类型文本判定（类型级） | 否 | 以类型渲染文本判定，属类型级判据（站点属性的投影）。不改。 |
| rust/rustcompiler/RustExpr.hx:15029 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:15075 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:15087 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:15091 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:15092 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:15093 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:15094 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:15270 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:15286 | 幂等守卫（as_str 去重） | 否 | as_str 后缀剥离；漏判由 rustc 拒绝。不修。 |
| rust/rustcompiler/RustExpr.hx:15293 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:15552 | 类型文本判定（类型级） | 否 | 以类型渲染文本判定，属类型级判据（站点属性的投影）。不改。 |
| rust/rustcompiler/RustExpr.hx:15567 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:15674 | 类型文本判定（类型级） | 否 | 以类型渲染文本判定，属类型级判据（站点属性的投影）。不改。 |
| rust/rustcompiler/RustExpr.hx:15684 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:15814 | 形态识别（类型构造前缀） | 否 | u32:: 前缀识别。不修。 |
| rust/rustcompiler/RustExpr.hx:15821 | 形态识别（类型构造前缀） | 否 | 同上。不修。 |
| rust/rustcompiler/RustExpr.hx:15835 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| rust/rustcompiler/RustExpr.hx:15931 | 形态识别（.len() 后缀） | 否 | len() 识别；漏判由 rustc 拒绝。不修。 |
| rust/rustcompiler/RustExpr.hx:16114 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:16128 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:16129 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:16130 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| rust/rustcompiler/RustExpr.hx:16185 | 幂等守卫（转换去重） | 否 | 去重守卫：判『真』失败只重复一次转换（语义等价）；判『假』失败时值移动/类型不匹配被 rustc 拒绝（E0382/E0308）。赋值目标另由 DegradedLvalueGuard 设防。不修。 |
| kotlin/kotlincompiler/Compiler.hx:373 | 命名/声明级（非形态判定） | 否 | 命名约定/模块前缀判定，不参与使用点形态。不修。 |
| kotlin/kotlincompiler/Compiler.hx:377 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| kotlin/kotlincompiler/Compiler.hx:384 | 命名/声明级（非形态判定） | 否 | 声明文本解析。不修。 |
| kotlin/kotlincompiler/Compiler.hx:739 | 命名/声明级（非形态判定） | 否 | 相对路径前缀。不修。 |
| kotlin/kotlincompiler/KotlinExpr.hx:1716 | 命名/声明级（非形态判定） | 否 | 命名约定/模块前缀判定，不参与使用点形态。不修。 |
| kotlin/kotlincompiler/KotlinExpr.hx:2108 | 幂等守卫（空断言去重） | 否 | Kotlin !! 去重：漏加被 kotlinc 拒绝，重复加语义等价。不修。 |
| kotlin/kotlincompiler/KotlinExpr.hx:2159 | 类型文本判定（类型级） | 否 | 以类型渲染文本判定，属类型级判据（站点属性的投影）。不改。 |
| kotlin/kotlincompiler/KotlinExpr.hx:2234 | 类型文本判定（类型级） | 否 | elementText 为元素类型文本（可空性），类型级判据。不改。 |
| kotlin/kotlincompiler/KotlinExpr.hx:2685 | 注释/非判定 | 否 | 该行为注释文本。无产物影响。 |
| kotlin/kotlincompiler/KotlinExpr.hx:3372 | 命名/声明级（非形态判定） | 否 | 命名约定/模块前缀判定，不参与使用点形态。不修。 |
| kotlin/kotlincompiler/KotlinExpr.hx:3512 | 命名/声明级（非形态判定） | 否 | 命名约定/模块前缀判定，不参与使用点形态。不修。 |
| kotlin/kotlincompiler/KotlinExpr.hx:3639 | 幂等守卫（空断言去重） | 否 | Kotlin !! 去重：漏加被 kotlinc 拒绝，重复加语义等价。不修。 |
| kotlin/kotlincompiler/KotlinExpr.hx:4657 | 句法归一化（if 块形状） | 否 | if ( 前缀识别；判错由 kotlinc 语法错误暴露。不修。 |
| kotlin/kotlincompiler/KotlinExpr.hx:4710 | 句法归一化（if 块形状） | 否 | 同上。不修。 |
| kotlin/kotlincompiler/KotlinExpr.hx:4765 | 幂等守卫（空断言去重） | 否 | Kotlin !! 去重：漏加被 kotlinc 拒绝，重复加语义等价。不修。 |
| kotlin/kotlincompiler/KotlinDecl.hx:1376 | 类型文本判定（类型级） | 否 | retType 可空 ? 判定，类型级判据。不改。 |
| swift/swiftcompiler/SwiftExpr.hx:753 | 幂等守卫（空断言去重） | 否 | Swift ! 去重：漏加/重复加均被 swiftc 编译错误拒绝。不修。 |
| swift/swiftcompiler/SwiftExpr.hx:760 | 幂等守卫（空断言去重） | 否 | Swift ! 去重：漏加/重复加均被 swiftc 编译错误拒绝。不修。 |
| swift/swiftcompiler/SwiftExpr.hx:930 | 形态识别（Some/借用/块前缀） | 否 | 识别已渲染形态避免重复包裹或追踪收窄；漏判由 rustc/kotlinc 类型不匹配拒绝，误判为冗余判定。不修。 |
| swift/swiftcompiler/SwiftExpr.hx:1059 | 幂等守卫（空断言去重） | 否 | Swift ! 去重：漏加/重复加均被 swiftc 编译错误拒绝。不修。 |
| swift/swiftcompiler/SwiftExpr.hx:1085 | 幂等守卫（空断言去重） | 否 | Swift ! 去重：漏加/重复加均被 swiftc 编译错误拒绝。不修。 |
| swift/swiftcompiler/SwiftExpr.hx:1538 | 命名/声明级（非形态判定） | 否 | 命名约定/模块前缀判定，不参与使用点形态。不修。 |
| swift/swiftcompiler/SwiftExpr.hx:1570 | 命名/声明级（非形态判定） | 否 | Builder 类名后缀。不修。 |
| swift/swiftcompiler/SwiftExpr.hx:1704 | 句法归一化（浮点字面量形状） | 否 | 字面量小数点补全；判错由 swiftc 拒绝。不修。 |
| swift/swiftcompiler/SwiftExpr.hx:1779 | 幂等守卫（空断言去重） | 否 | Swift ! 去重：漏加/重复加均被 swiftc 编译错误拒绝。不修。 |
| swift/swiftcompiler/SwiftExpr.hx:1829 | 句法归一化（if 块形状） | 否 | (if ( 前缀识别。不修。 |
| swift/swiftcompiler/SwiftExpr.hx:1865 | 幂等守卫（空断言去重） | 否 | Swift ! 去重：漏加/重复加均被 swiftc 编译错误拒绝。不修。 |
| swift/swiftcompiler/SwiftExpr.hx:1901 | 形态识别（Optional 包裹前缀） | 否 | Optional( 前缀识别；漏/误由 swiftc 类型错误拒绝。不修。 |
| swift/swiftcompiler/SwiftExpr.hx:2140 | 命名/声明级（非形态判定） | 否 | 字段名后缀匹配。不修。 |
| swift/swiftcompiler/SwiftExpr.hx:2415 | 幂等守卫（空断言去重） | 否 | Swift ! 去重：漏加/重复加均被 swiftc 编译错误拒绝。不修。 |
| swift/swiftcompiler/SwiftExpr.hx:2423 | 幂等守卫（空断言去重） | 否 | Swift ! 去重：漏加/重复加均被 swiftc 编译错误拒绝。不修。 |
| swift/swiftcompiler/SwiftExpr.hx:2450 | 幂等守卫（空断言去重） | 否 | Swift ! 去重：漏加/重复加均被 swiftc 编译错误拒绝。不修。 |
| swift/swiftcompiler/SwiftExpr.hx:2715 | 命名/声明级（非形态判定） | 否 | 命名约定/模块前缀判定，不参与使用点形态。不修。 |
| swift/swiftcompiler/SwiftExpr.hx:2825 | 命名/声明级（非形态判定） | 否 | 命名约定/模块前缀判定，不参与使用点形态。不修。 |
| swift/swiftcompiler/SwiftExpr.hx:2982 | 幂等守卫（空断言去重） | 否 | Swift ! 去重：漏加/重复加均被 swiftc 编译错误拒绝。不修。 |
| swift/swiftcompiler/SwiftExpr.hx:3007 | 幂等守卫（空断言去重） | 否 | Swift ! 去重：漏加/重复加均被 swiftc 编译错误拒绝。不修。 |
| swift/swiftcompiler/SwiftExpr.hx:4849 | 命名/声明级（非形态判定） | 否 | 行标记识别（生成物后处理）。不修。 |
| swift/swiftcompiler/SwiftExpr.hx:5192 | 类型文本判定（类型级） | 否 | 以类型渲染文本判定，属类型级判据（站点属性的投影）。不改。 |
| swift/swiftcompiler/SwiftFallibility.hx:287 | 命名/声明级（非形态判定） | 否 | 导入路径/文件前缀判定，不参与使用点形态。不修。 |
| swift/swiftcompiler/SwiftFallibility.hx:374 | 命名/声明级（非形态判定） | 否 | 导入路径/文件前缀判定，不参与使用点形态。不修。 |
| swift/swiftcompiler/SwiftDecl.hx:112 | 命名/声明级（非形态判定） | 否 | 命名约定/模块前缀判定，不参与使用点形态。不修。 |
| swift/swiftcompiler/SwiftDecl.hx:206 | 命名/声明级（非形态判定） | 否 | 命名约定/模块前缀判定，不参与使用点形态。不修。 |
| swift/swiftcompiler/SwiftDecl.hx:648 | 类型文本判定（类型级） | 否 | declaredType 可空 ? 判定，类型级判据。不改。 |
| swift/swiftcompiler/SwiftInoutParams.hx:69 | 命名/声明级（非形态判定） | 否 | 导入路径/文件前缀判定，不参与使用点形态。不修。 |
| swift/swiftcompiler/SwiftInoutParams.hx:91 | 命名/声明级（非形态判定） | 否 | 导入路径/文件前缀判定，不参与使用点形态。不修。 |
| swift/swiftcompiler/SwiftInoutParams.hx:92 | 命名/声明级（非形态判定） | 否 | 导入路径/文件前缀判定，不参与使用点形态。不修。 |
| dart/dartcompiler/DartExpr.hx:1930 | 命名/声明级（非形态判定） | 否 | 命名约定/模块前缀判定，不参与使用点形态。不修。 |
| dart/dartcompiler/DartExpr.hx:4017 | 命名/声明级（非形态判定） | 否 | 行前缀剥离。不修。 |
| dart/dartcompiler/DartExpr.hx:4040 | 句法归一化（分号） | 否 | return 分号归一化。不修。 |
| dart/dartcompiler/DartExpr.hx:4805 | 命名/声明级（非形态判定） | 否 | 命名约定/模块前缀判定，不参与使用点形态。不修。 |
| dart/dartcompiler/Compiler.hx:162 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| dart/dartcompiler/Compiler.hx:171 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| dart/dartcompiler/Compiler.hx:180 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| dart/dartcompiler/DartDecl.hx:118 | 命名/声明级（非形态判定） | 否 | 命名约定/模块前缀判定，不参与使用点形态。不修。 |
| dart/dartcompiler/DartDecl.hx:138 | 命名/声明级（非形态判定） | 否 | 命名约定/模块前缀判定，不参与使用点形态。不修。 |
| dart/dartcompiler/DartDecl.hx:286 | 命名/声明级（非形态判定） | 否 | 命名约定/模块前缀判定，不参与使用点形态。不修。 |
| dart/dartcompiler/DartType.hx:242 | 类型文本判定（类型级） | 否 | 可空 ? 补全，类型级判据。不改。 |
| ts/tscompiler/TsStringBufParams.hx:63 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| ts/tscompiler/TsImports.hx:27 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| ts/tscompiler/TsImports.hx:109 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| ts/tscompiler/TsImports.hx:133 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| ts/tscompiler/Compiler.hx:277 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| ts/tscompiler/Compiler.hx:289 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| ts/tscompiler/Compiler.hx:404 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| ts/tscompiler/Compiler.hx:453 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| ts/tscompiler/Compiler.hx:608 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| ts/tscompiler/TsExpr.hx:1681 | 模块级属性 → 已收敛站点级 | 否（已站点级） | pin 426f8876 已改为 arraySlotDepth 站点判定（仅 Array<T> 槽位包 Array.from，形参解不出则生成期报错）；residency 仅为 Int32Array 形态前置（spec 20）。维持。 |
| ts/tscompiler/TsType.hx:79 | 模块级属性（resident） | 否 | 声明/类型形态选择（文件放置、导入形态、类型形态，spec 20 规定的模块级形态本身）；判错产生导入缺失/形态不匹配的编译错误，非静默。不修。 |
| rust/rustcompiler/RustImports.hx:80 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustType.hx:120 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustType.hx:196 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/Compiler.hx:110 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/Compiler.hx:122 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/Compiler.hx:283 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/Compiler.hx:1172 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustDecl.hx:1245 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:4117 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:4894 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:5857 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:5863 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:7485 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:7488 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:7535 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:7612 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:7623 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:7738 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:7786 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:7798 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:7828 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:7834 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:7836 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:7959 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:7984 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:8047 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:8103 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:8106 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:8227 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:8232 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:8237 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:9314 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:9333 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:9365 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:9428 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:9605 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:9987 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:10682 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:10712 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:10743 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:10832 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:10963 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:10967 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:11099 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:12785 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:12797 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:12806 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:12899 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:12960 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| rust/rustcompiler/RustExpr.hx:14854 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| kotlin/kotlincompiler/KotlinType.hx:96 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| kotlin/kotlincompiler/Compiler.hx:92 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| kotlin/kotlincompiler/Compiler.hx:112 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| kotlin/kotlincompiler/Compiler.hx:274 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| kotlin/kotlincompiler/KotlinImports.hx:76 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| kotlin/kotlincompiler/KotlinImports.hx:114 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| swift/swiftcompiler/SwiftFallibility.hx:65 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| swift/swiftcompiler/SwiftImports.hx:34 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| swift/swiftcompiler/SwiftImports.hx:116 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| swift/swiftcompiler/Compiler.hx:119 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| swift/swiftcompiler/Compiler.hx:132 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| swift/swiftcompiler/Compiler.hx:250 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| swift/swiftcompiler/Compiler.hx:251 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| swift/swiftcompiler/Compiler.hx:264 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| swift/swiftcompiler/Compiler.hx:265 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| swift/swiftcompiler/Compiler.hx:312 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| swift/swiftcompiler/Compiler.hx:403 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| swift/swiftcompiler/SwiftType.hx:27 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| swift/swiftcompiler/SwiftType.hx:121 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| swift/swiftcompiler/SwiftType.hx:192 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| swift/swiftcompiler/SwiftInoutParams.hx:68 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| dart/dartcompiler/DartExpr.hx:1924 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| dart/dartcompiler/DartExpr.hx:4485 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| dart/dartcompiler/DartImports.hx:38 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| dart/dartcompiler/DartImports.hx:194 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| dart/dartcompiler/DartImports.hx:195 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| dart/dartcompiler/DartImports.hx:224 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| dart/dartcompiler/DartImports.hx:235 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| dart/dartcompiler/DartImports.hx:272 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| dart/dartcompiler/Compiler.hx:162 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| dart/dartcompiler/Compiler.hx:171 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| dart/dartcompiler/Compiler.hx:180 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| dart/dartcompiler/Compiler.hx:196 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| dart/dartcompiler/Compiler.hx:227 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| dart/dartcompiler/Compiler.hx:239 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| dart/dartcompiler/Compiler.hx:253 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| dart/dartcompiler/Compiler.hx:389 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| dart/dartcompiler/Compiler.hx:390 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| dart/dartcompiler/Compiler.hx:403 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| dart/dartcompiler/Compiler.hx:404 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| dart/dartcompiler/Compiler.hx:457 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| dart/dartcompiler/Compiler.hx:496 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| dart/dartcompiler/DartDecl.hx:645 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| dart/dartcompiler/DartType.hx:79 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |
| dart/dartcompiler/DartType.hx:174 | 模块级属性（resident） | 否 | 声明级决策（放置/导入/扫描范围）；未发现参与使用点包装的实例，判错由编译期可见错误暴露。不修。 |