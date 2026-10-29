# protocol 单源化的 boring spec 阅读笔记（Stage1-P1）

生成器修订：tiqian/.haxelib/boring/git @ be1d8e45。每条记录「文件:行 + 原文片段」。

## haxe.io.Bytes / BytesBuffer（stdlib/01-haxe-io-bytes.md）
- :9-21 API 面：`Bytes.ofString(s:String):Bytes`(:12)、`b.get(pos:Int):Int`(:15)、`b.toHex():String`(:21)。
- :23 目标表示：`On the TypeScript target, haxe.io.Bytes wraps a Uint8Array over an ArrayBuffer.`
- :169 Ruling：`haxe.io.Bytes remains the Haxe source type. ... TypeScript uses Uint8Array ... BytesBuffer remains the growable sink`
- :183 修正案：`haxe.io.BytesBuffer gains add(b:Bytes):Void`。

结论：canonical 的 Writer 用 BytesBuffer(addByte/add/getBytes)，字符串经 Bytes.ofString 进缓冲；不手写 UTF-8。测试十六进制断言优先 toHex。

## Sha256（crypto/01-sha256-sha512.md）
- :9-11 API：`Sha256.make(data:Bytes):Bytes;`（第 9 行）；「portable Haxe code / No external crypto package」的原句在本文件 Implementation 段（`The source implementations are portable Haxe code. PHP and Java branches are not part of this capability.`），第 9-11 行本身只有两条签名。
- 实现 pin 内 samples/haxe/crypto/Sha256.hx（:10 `class Sha256`、:85 `public static function make(data:Bytes):Bytes`）。

结论：Canonical.digest 单源入口 = Sha256.make。

## 枚举与模式匹配（features/01-enums-and-pattern-matching.md）
- :335 TS 载荷访问：`TypeScript branches on the discriminant and then reads the payload property (error.remaining), where narrowing supplies the type. TypeScript never renders payload extraction as property access on a widened type with a cast.`

结论：生成代码按判别式收窄读载荷；Haxe 侧不写「构造枚举值再模式绑定」的回传写法（listMember 改 guard 谓词 + arrOf）。

## 控制流（features/15-control-flow.md）
- :181 TS switch 条件：`Haxe switch translates to TypeScript as a switch statement only when every case body ends in return or throw ... When a case body must fall through to shared logic, the translation uses an if/else chain on the discriminant instead.`

结论：canonical 中带循环体的分支一律提出成独立方法；switch 只保留「每臂 return/throw」或纯值臂形态。

## 表达式位块（features/43-expression-block-scopes.md）
- :5 Accepted subset：`Every statement before the final statement must be a declaration (TVar), with or without an initializer. The final statement must be a value expression.`（:7-9 为理由段。）

结论：表达式位不放 while/if；此前两条「生成器缺陷」结论（Bytes.get 未降级、模式绑定未定义）实为违反本条的源码形态所致，已撤回。

## 生成与测试配置驱动器（features/59-bundle-driver.md）
- :33-40 bundle 字段表（id/target/precision/build/run/package）。
- :62-67 输出目录：`<outRoot>/<id>/gen and <outRoot>/<id>/gen-tests. A project file may not name them.`
- :78-90 讲 generation defines 与 manifest/artifact defines（`**Generation defines.** `<target>-output` and `<target>-test-output` from the two directories above`）；rust 配方两步的代码在 Driver.hx:602-604（`cargo test --no-run` 后 `cargo test`，工作目录 <outRoot>/<id>/gen）。

## 字节序与语义的权威（既有实现 + golden）
- platforms/web/server/core/src/canonical.ts:18 `Buffer.from("TQCS", "ascii")`、:71 `setFloat64(0, value, true)`、:76/:86 `setUint32(..., true)`。
- platforms/web/server/precompute/engine/src/canonical.rs:23 `b"TQCS"`、:89 `to_le_bytes()`、:93 `to_bits().to_le_bytes()`。
- canonical.rs:54 `canonical_f64`（非有限值丢弃、±0 折 +0）；canonical.ts:303 同义；可选数值字段 = 存在标志 + f64 位（canonical.rs:382、canonical.ts:113）。
- 验收 golden：canonical.test.ts:16 起 vector0-vector3 四条 hex，Rust 单测钉同一组。

## Stage1-P5 宿主请求模型与校验（生成器修订 pin 4f412c6a）

## 结构与 typedef（features/03-structures-and-typedefs.md）
- :180 `Haxe anonymous structure typedefs translate to named `struct` declarations in Rust with public fields and derived traits (`Debug`, `Clone`, `Copy`, `PartialEq`), to named `interface` declarations in TypeScript with `readonly` properties, and to `data class` declarations in Kotlin with `val` properties.`

结论：ParagraphRequest/TextSpanInput/LineBreakSpanInput/InlineBoxInput 用 typedef 匿名结构声明，DTO 字段单源。

## 错误与结果（features/06-errors-and-results.md）
- :34 `The failure identity is a Haxe enum as ruled in docs/specs/features/01-enums-and-pattern-matching.md; the exception class carries the enum instance`（:37-51 给出 enum + `class VectorException extends haxe.Exception` 样板）。
- :314-318 Ruling：`Failure identity is a closed variant set defined once per domain and shared by all four trees`；Rust `all fallible operations return Result<T, DomainError>`；TS `throw sites construct one exception class carrying the error union value`。
- :397 `tests assert variant identity, never message content`。

结论：ParagraphRequestError 枚举逐变体承载领域错误名（EmptyParagraph/InvalidMaximumMeasure/…，名字照 paragraph.rs:72-131 validate 顺序），ParagraphRequestException 包装抛出；字节协议错误名不进来。

## 字符串长度（stdlib/06-std-modules.md）
- :318 `String.length and codeUnitAt are constant-time UTF-16 unit access;`

结论：范围与 boundary 检查直接用 text.length，对应 paragraph.rs:213-222 utf16_length 的 UTF-16 语义与 Kotlin String.length。

## 待取证（动手改 validate 形态前）
- 空白判定：Kotlin ParagraphWireCodec.kt:279 `text.isNotBlank()` 与 Rust paragraph.rs:73 `text.trim().is_empty()` 空白集不同；取证对象为 pin 内 StringTools/字符串降级发射端与 Rust 生成侧 UString trim 语义。
- throwing 方法在 rust 发射端的 fallibility 传播：取证对象为 pin 内 rust 发射端 TThrow 处理函数与生成文本。
- 字段集：decorations/inlineObjects/emphasisDotGapEm 仅在 Kotlin DTO，Rust ParagraphRequest 没有；单源取并集还是交集待队长定。

## TS 目标两个已取证的形态前提（调试取证四步见 AGENTS.md）
- Bytes.get 降级条件：reflaxe/ts/tscompiler/TsExpr.hx:2191-2192 `if (name == "get" && isBytes(stripCast(subj)))`；isBytes(:3622-3626) 要求静态类型恰为 `haxe.io.Bytes`。传 `Null<Bytes>` 不命中、退化为普通字段调用。fix：switch 分支绑定非空 Bytes 后再调 get。
- samples 类的源范围过滤：TS 模块发射拒绝项在 tscompiler/Compiler.hx:500（`value-referenced but emits no declarations`），根因是类不在 Intercept.run 声明的源范围；按 rust-common.hxml 对 samples/std 的先例把 samples 路径加进源范围。

## Stage1-P6 错误命名 NamedError 族（生成器修订 pin 4f412c6a）

## 错误与结果（features/06-errors-and-results.md）
- :314 Ruling：`Failure identity is a closed variant set defined once per domain and shared by all four trees. Each domain declares its variants in one commit touching every tree: the Haxe enum and its exception wrapper, the Rust error enum, the TypeScript error union and exception class, and the Kotlin sealed exception hierarchy.`
- :397 `tests assert variant identity, never message content`。

结论：NamedError 即领域验证错误名的跨四树闭包变体集；Haxe 枚举逐变体承载发布名，测试断言变体清单与名字逐项相等。

## 枚举与模式匹配（features/01-enums-and-pattern-matching.md）
- :5 Scope：`In the current codebase, algebraic sum types appear in Haxe as the `VectorError` enum carried by `VectorException` in `samples/boring/`, in Rust as `VectorError` in `reference/rust/src/lib.rs`, in TypeScript as the `VectorError` union carried by `VectorException` in `reference/ts/src/vector-error.ts`, and in Kotlin as the sealed `VectorException` hierarchy in `reference/kotlin/src/boring/VectorException.kt`.`
- :335 TS 载荷访问（P1 已引）：`TypeScript branches on the discriminant and then reads the payload property (error.remaining), where narrowing supplies the type.`
- 事实（pin 4f412c6a）：reference/ 目录只有 rust 与 ts，无 reference/kotlin；Kotlin 形态以 Kotlin 发射端实际生成物为准（引擎 Kotlin 目标配置生成物里的枚举是正例）。
- Rust 参考形态：reference/rust/src/lib.rs:272 `pub enum VectorError`，显示文本渲染见本 spec :61-72 的 Display 实现。
- TS 参考形态：reference/ts/src/vector-error.ts:26-31 `export type VectorError = | BadMagicError | ...` 判别联合 + :32 `describeError`。

## 三 lane 名字站点（变体集与序的权威）
- Rust：paragraph.rs:74-131 的 `named("...")` 16 名按 validate() 检查序（EmptyParagraph…InvalidInlineBoxGeometry）；main 树其余站点 normalize.rs:143/147/151/154、precomputer.rs:286/441、precompute_html.rs:582；normalize.rs:32 PARAGRAPH_CAPABILITY_ISSUES 列表含 "EmptyParagraph"。
- Kotlin：ParagraphWireCodec.kt:279-297 与 :386-397 段级 8 名（含 Kotlin 独有的 InvalidEmphasisDotGapEm），:48-144 区段检查 13 名（含 Kotlin 独有的 InvalidInlineObjectRange/Advance/VerticalGeometry 与 InvalidDecorationRange）；:56/71/106/124/136 的 Invalid*Wire 是字符串打包名，随打包消失，不进枚举。
- TS：markdown-lowering.ts:778/:815 EmptyParagraph、lifecycle.ts:265 InvalidFontSize、astro/integration.ts:110 InvalidMaximumMeasure——三处属消费侧接线（需重构建 @tiqian/ffi 包），队长裁定移交 C1 的四条 JS 接线；P6 只交付生成物（TS 目标配置生成物 publish 到 platforms/web/server/core/src/protocol-gen/）。
- 字节协议名不进枚举：ffi/native/src/nativeMain/kotlin/org/tiqian/ffi/cabi/LayoutRequestReader.kt:40-228 的 InvalidLayoutRequest* 属打包机制，割接后随打包整体删除。

## 变体集与声明序（21 名）
- 序=paragraph.rs:74-131 检查序，Kotlin 独有名插到 Kotlin lane 对应检查位：InvalidEmphasisDotGapEm 在 InvalidFontWeight 后；InvalidInlineObjectRange/InvalidInlineObjectAdvance/InvalidInlineObjectVerticalGeometry 在 InvalidInlineBoxGeometry 后；InvalidDecorationRange 末位。
- TS 三名为该集子集；与 P5 分支（cutover/stage1-p5-request-model）的 ParagraphRequestError 同名同序（P5 未并），队长裁定 (b)：P5 落地后本分支 rebase 到 main 并把 checks/exception 改指向 NamedError，退役 P5 的枚举；本阶段不碰 paragraph.rs 与 ParagraphWireCodec.kt。

## 目标配置接入
- protocol-ts.hxml / protocol-rust.hxml 加 root org.tiqian.protocol.NamedError 与 NamedErrorTest。
- 新 protocol-kotlin.hxml（按 protocol-ts.hxml 的 standalone 形态 + kotlin-common.hxml 的 kotlin 发射端行；输出目录不手抄 define，由驱动器按 spec 59:62-67 从 outRoot/<id> 派生）+ boring.json 加 protocol-kotlin 目标配置（任务书要求生成 Kotlin/TS/Rust）。
- 生成物 vendored（只从驱动器产物搬，结构与 gen 根逐项一致）：TS→platforms/web/server/core/src/protocol-gen/org/tiqian/protocol/；Rust→platforms/web/server/precompute/protocol-gen/org/tiqian/protocol/（crate tiqian-protocol-gen，engine 经 path 依赖）；Kotlin→ffi/js/src/jsMain/kotlin/org/tiqian/protocol/。

## 待取证（动手改调用点前，取证对象为 pin 内发射端函数）
- 无 exception 包装的纯枚举在三目标的渲染形态：TS 发射端为 .haxelib/boring/git/packages/compiler/reflaxe/ts/tscompiler/ 内渲染 VectorError 参考物的函数（模块发射拒绝点在 tscompiler/Compiler.hx:500）；Rust 发射端为 packages/compiler/reflaxe/rust/ 内枚举渲染函数；Kotlin 发射端为 Kotlin 编译器内枚举渲染函数。
- 生成物是否已把变体名暴露为字符串（Rust Display/str、TS kind 判别式、Kotlin 枚举名）——决定是否补 describe 类。
- Kotlin 渲染形态（enum class 还是 sealed class）——决定 Kotlin 调用点引用写法。
- mac ssh 不可达（banner 前断连）：protocol-gen 小 crate 按本机例外编译（cp -a 到 /tmp/<label>-pg，XDG_CACHE_HOME=/tmp/tq-nix-cache nix develop 内 cargo build --lib --message-format=short，跑完删 target）；整棵 precompute engine 树仍只在 mac 上构建，本阶段 engine crate 改动只做机械字面量替换并以生成 crate 的本地编译+三侧名字 diff 佐证。

## 取证结果（第一步，pin 4f412c6a；生成配置：驱动器 node boring/out/bundle/driver.js gen <bundle> --project boring.json，工作树根 nix develop 内执行，out 目录先清（PIT-54），输出目录由驱动器派生）

## 测试 lane 阻塞与目标根类补齐（pin f1b28bd3）
- Rust lane（test protocol-rust，cargo test --no-run）E0432：生成的测试文件（named_error_test.rs 与 P5 的 paragraph_request_test.rs 同形）`use crate::runtime::test as testlib;`（RustDecl.hx:2715、RustExpr.hx:9295/9339/9441 硬编码），而生成 crate 无 runtime/test 模块（gen/org/tiqian/test/trace/ 为 Haxe 测试支撑，gen/runtime/ 无 test.rs）。取证四步：源结构=protocol-rust.hxml root 缺 runtime.TestCore（packages/compiler/runtime/TestCore.hx，features/19-testing.md「Each target compiles this class into its test runtime package beside the host entry」）；发射端=RustDecl.hx:2715 的固定 import；生成物=named_error_test.rs:12；失败点=E0432。旧 pin 4f412c6a 的 RustDecl.hx:2715 同文（git show 比对）→ pin 无关的发射端/目标根类配置缺陷，P5 的 rust 测试 lane 同样不可编译（其 paragraph_request_test.rs 同形）。
- Kotlin lane（test protocol-kotlin，kotlinc 独立编译 gen+gen-tests）：TracedAssertions.kt 报 unresolved `SortedTable`/`values.at(i)`——独立编译时 runtime 包缺失；kotlin-f32/f64 目标配置的 classes.hxml 尾含 runtime.UString 与 runtime.TestCore 两个 root，本席 protocol-kotlin.hxml 独立形态漏了。
- 修复（本次目标配置接入范围内）：protocol-rust.hxml 补 root runtime.TestCore（P5 已加 SortedTable/UString）；protocol-kotlin.hxml 补 root runtime.UString 与 runtime.TestCore。清 out 目录重生成后重跑两 lane；若绿，vendored 树无变化（TestCore 属测试运行时，不进 vendored 库，P1 先例：vendored mod.rs 无测试模块）。
- TS 形态（engine-haxe/out/protocol-ts/gen/org/tiqian/protocol/NamedError.ts）：每变体一个 `readonly kind: "<Name>"` interface（:3 起）+ 判别联合 `export type NamedError`（:87）+ `Object.freeze` 常量对象 `export const NamedError`（:110）+ `compareNamedError`（:134）；NamedErrorNames.ts 为 class，静态 `variants()`（21 项声明序）与 `describe(error)`（switch 返回发布名）。名字以 kind 判别式与 describe 双通道暴露，无需补 accessor。
- Rust 形态（pin 4f412c6a，退役前）：named_error.rs `#[derive(Debug, Clone, Copy, PartialEq)] pub enum NamedError`（:2，21 变体）+ 固有 `pub fn to_string(&self) -> String`（:56-57，Display 文本即发布名）+ compare_named_error；named_error_names.rs 静态 `named_error_names_variants()`/`named_error_names_describe()`。
- Kotlin 形态（③c）：NamedError.kt `enum class NamedError`（:3，21 项）+ 顶层 `compareNamedError`；NamedErrorNames.kt `object NamedErrorNames`（:3）`variants(): MutableList<NamedError>`（:4）与 `describe(error): String`（:8，when 分支）。enum class 而非 sealed class——调用点按枚举名引用。
- 拦截器约束（pin 内 Intercept.hx）：方法名 `all` 在 CLOSED_LIST（:93），0 参调用即 fatal「collection pipeline methods accept inline function literals only」→ 访问器命名 `variants()`；测试类只许测试成员（non-test member 报「shared logic belongs in an ordinary class」）→ 黄金名单移入 NamedErrorTestSupport。
- 三侧名字 diff（pin 4f412c6a 生成物，命令：对三个 NamedErrorNames 生成文件各取 describe 分支的 21 个名字成清单后两两 diff）：TS==Rust==Kotlin==黄金 21（paragraph.rs:74-131 检查序 + Kotlin 位），逐项相等。

## 第二步（P5 落地后：rebase 到 b7169e08，pin 推进到 f1b28bd3，退役 P5 枚举）
- 生成器修订：.haxelib/boring/git reflog 04:03:06 由 4f412c6a 切到 f1b28bd3（fix(rust): emit resident modules when their types are required）；第一步三目标生成均在 04:03 前完成（属 4f412c6a），第二步三目标全部清空重生成（f1b28bd3）。
- 退役对照（对照物=变体名恒等映射，P5 枚举与 NamedError 的 21 名同名同序）：ParagraphRequestError.hx 删除；ParagraphRequestException.hx 载荷字段/构造/describe 签名 ParagraphRequestError→NamedError（switch 分支不变，变体名恒等）；ParagraphRequestTestSupport.hx:34 issueNameOf 参数→NamedError；ParagraphRequest.hx:12 文档指称→NamedError；ParagraphRequestChecks.hx 零改动（裸变体引用在枚举删除后解析到 NamedError）；hxml root 零改动（错误枚举从未是 root）。
- Rust 发射端事实（pin f1b28bd3，取证四步之第 2 步）：exception 类（extends haxe.Exception）的载荷枚举一律并入所属 exception 模块发射——Compiler.hx:985-992（payloadEnumModules/exceptionPayloads 登记）、Compiler.hx:280（载荷枚举模块不单独发射）、RustDecl.hx:1988-1989（类型引用重定向）。后果：退役后 NamedError 在 Rust 侧定义于 paragraph_request_exception.rs（21 变体 + impl Display + impl Error），无独立 named_error 模块；named_error_names.rs 从 exception 模块 import。engine crate 七站点引用路径=tiqian_protocol_gen::org::tiqian::protocol::paragraph_request_exception::NamedError（别名 ProtocolNamedError），.to_string() 走生成的 Display。P5 的 paragraph.rs 零改动（不显式命名生成错误类型，经 .map_err(|error| NamedError(error.to_string())) 消费）。
- TS 发射端事实：ParagraphRequestError.ts 不再发射（枚举源已删）→ vendored 树删除该文件；ParagraphRequestChecks.ts / ParagraphRequestException.t
## 最终 lane 读数（pin f1b28bd3，测试源修复后重生成）
- 目标根类修复后三目标 gen 全 RC=0（protocol-rust/protocol-kotlin/protocol-ts，驱动器 gen 动作）。
- 子集约束取证：Haxe 表达式 switch（21 个整数字面 case）在受保护源内触发发射端 `Unmatched patterns: _`（pin f1b28bd3，三目标 gen 步骤均报）；改语句 switch 又触 V15「variant switch carries a default arm」（rust/kotlin）与 ts 目标「variant switch subject is not a variant value」——受保护源内 switch on Int 三目标均不可用。NamedErrorTestSupport.variantAt 最终形态为 if/else 语句链（21 分支，每分支新构造值，无集合索引取值），三目标 gen 通过。
- Rust lane（test protocol-rust，cargo test，生成 crate 独立编译）：编译通过（TestCore root 补齐后 E0432 消除；E0507 经 variantAt 改造消除）。运行 9 条：7 过 2 挂。过含 NamedErrorTest 两条（theVariantListMatchesThePublishedNamesInCheckOrder、thePublishedNamesAreAllDistinct）与 ParagraphRequestTest.paragraphChecksReportTheDomainNamesInOrder（领域名序断言，rust lane 通过）。挂的两条均为主既有 P5 源级缺陷：(1) boundariesAndRangesUseTheUtf16Length（夹具 {2,3} 对 4 单元文本合法，已证）；(2) spanChecksCoverRangeFamiliesAndNumbers——四步取证：源结构=ParagraphRequestTest.hx:65 `base.textSpans = [span]` 后 :67-:82 原地变更 span 再断言；TS 生成物=gen-tests ParagraphRequestTest.test.ts:55 `base.textSpans = [span]`（引用语义，变更反映到请求，lane 过）；rust 生成物=gen paragraph_request_test.rs:365 `base.text_spans = vec![(span).clone()]`（值语义，变更不反映，base 恒为原始 {start:2,end:1} span，区间检查先行）；失败点=paragraph_request_test.rs:372 assertEqualsString("MissingTextSpanFontFamilies", issueOf(base)) 实得 InvalidTextSpanRange。Kotlin 同为值语义，同挂（lane 另有 resident 编译缺口）。两条缺陷已挂任务 t-mujl8hwo-g8cy。
- TS lane（bun test 逐文件，新 gen）：NamedErrorTest 2/2 过；ParagraphRequestTest 6/7（失败仅 P5 夹具缺陷，引用语义使 span 用例在 TS 过）；CanonicalTest 独立跑 600s 超时（P1 测试，环境负载，非本席判据对象）。
- Kotlin lane（test protocol-kotlin，kotlinc 独立编译 gen+gen-tests）：resident 运行时缺口（unreferenced residents write nothing，kotlincompiler/Compiler.hx:686-690；SortedTable 等 resident 未落 gen 树，TracedAssertions.kt 的 org.tiqian.boring.runtime.SortedTable 导入悬空，RC=1）。engine 目标配置经 tests 源集 oracle 类引用 resident 而绕过，protocol 目标配置接入无法在不污染源的前提下触发同效果；该缺口位于发射端或宿主侧，不属于本次目标根类配置问题（补 root runtime.UString/runtime.TestCore 后 TestCore 已落 gen/runtime/test/，缺口仅剩 SortedTable/UString 等未被引用 resident）。
- 三侧名 diff（新 gen）：TS/Rust/Kotlin 的 NamedErrorNames 21 名逐位相等（各 21 行，diff 无差异），与 golden（paragraph.rs:74-131 检序 + Kotlin 位序）一致。
- vendored 同步（新 gen 后复核）：rust 三件（named_error_names.rs、paragraph_request_checks.rs、paragraph_request_exception.rs）与 TS ParagraphRequestException.ts 逐字节 SAME，无需再搬；测试运行时（test_core.rs/test.rs）属生成树专属，不进 vendored（P1 先例：vendored mod.rs 无测试模块）。s 改从 ./NamedError.ts 导入并引用 NamedError.<Variant>。生成物 import 规范式在本 pin 为 .ts 后缀（P1/P5 旧 pin 产物为 .js 后缀）：server-core tsconfig 加 rewriteRelativeImportExtensions（tsc 5.9.3，build 门 noEmit=false 合法），tsc 构建通过且 lib/ 输出改写为 .js；Node 22.23.1 strip-types 直接解析 .ts 规范式（不映射 .js→.ts）。
- vendored 刷新（f1b28bd3）：TS 8 文件刷新（Canonical/JsCoerce/WireField/WireValue/ParagraphRequest/ParagraphRequestChecks/ParagraphRequestException/ParagraphRequestTestSupport）+ ParagraphRequestError.ts 删除；Rust 3 文件刷新（named_error_names/paragraph_request_checks/paragraph_request_exception）+ named_error.rs 删除 + mod.rs 去掉 named_error 模块 + _GeneratedFiles.txt 去掉该行；Kotlin 两文件与旧 pin 逐字节相同（不变）。_GeneratedFiles.txt 另补 P5 落地漏登记的 13 个文件（8 个 protocol 输入/请求模型 + 5 个 runtime），rebase 提交内完成。
- 本机例外编译（f1b28bd3 刷新后 vendored crate）：/tmp/p6-pg 复制 + XDG_CACHE_HOME=/tmp/tq-nix-cache nix develop 内 cargo build --lib --message-format=short → RC=0（Finished dev profile；既有 warning 一处在 canonical.rs:437 unused kind，P1 文件非本席改动）。
- engine crate 七站点（normalize.rs:144/148/152/155、precomputer.rs:287/442、precompute_html.rs:583）：named("<Name>") → named(&ProtocolNamedError::<Variant>.to_string())，每文件加一行 use；normalize.rs:32 PARAGRAPH_CAPABILITY_ISSUES 常量列表保留字面量（const 上下文不能调用生成的非常量访问器；名单与生成枚举的恒等由 NamedErrorTest 黄金清单+三侧 diff 锁定）。mac ssh 不可达：engine crate 本阶段不本地编译，以上站点以生成 crate 本地编译 + 变体名恒等 + paragraph.rs 零改动佐证，mac 恢复后需 cargo build 复核。
- npm 测试（cd platforms/web/server/core && npm test，Node v22.23.1）：13 pass / 3 fail / 57 skip。三处 fail 均为 main 既有（本席改动前后同一集合，逐一核对）：test/paragraph-request.test.ts 整文件 ERR_MODULE_NOT_FOUND——main 版（b7169e08 第 8-10 行）以 .js 规范式导入 .ts 源，Node ESM 不映射；改 .ts 规范式后可加载但 import { DecorationInput }（生成 typedef 仅 export type）在 Node 纯语法 strip-types 下保留为值导入报 SyntaxError（bun 全语义 lane 不受限）；test/transport.test.ts:123/:145 assert.ok(transport) 同源（.js 规范式导入 src 失败）。fonts.test.ts（FFI 错误名断言 :105-108）全部 SKIP——native addon 未在本工作树构建（build:native 需 mac/长链）。可跑的 npm 侧名字验证=驱动器 bun lane（test protocol-ts 跑 gen-tests，含 NamedErrorTest 与 ParagraphRequestTest）。
- P5b 交接（t-mujjhdqh-a7h0）：protocol-kotlin 目标配置已就绪（boring.json 第 83 行，root 现为 NamedError/NamedErrorTest）；Kotlin 出口=engine-haxe/out/protocol-kotlin/gen（驱动器派生，spec 59:62-67），vendored 出口=ffi/js/src/jsMain/kotlin/org/tiqian/protocol/（现含 NamedError.kt 与 NamedErrorNames.kt）。P5b 将请求模型类加入同一配置的 root 并从同一 gen 出口搬运。
- C1 交接（不变）：TS client 三站点 markdown-lowering.ts:778/:815、lifecycle.ts:265、astro/integration.ts:110 属 C1 四条 JS 接线；生成物出口=platforms/web/server/core/src/protocol-gen/org/tiqian/protocol/NamedError.ts（kind 判别式 + NamedError 常量对象），消费侧从该 vendored 路径导入，不复制名字字面量。
## 表二进制读写（Stage1-P2 补记，生成器修订 4f412c6a）

### BytesInput/BytesOutput 与端序（stdlib/02-haxe-io-buffers-and-inputs.md）
- :11 `haxe.io.BytesBuffer ... carries no built-in multi-byte endianness dispatch`。
- :12-13 API 面：BytesInput 提供 readByte/readInt32/readDouble/readString 与 bigEndian 属性；BytesOutput 提供 writeInt32/writeDouble。
- :15 裁定原文：`To maintain strict IEEE 754 bit-identical float representations across all targets, this repository bypasses BytesInput/BytesOutput endian methods in favor of explicit bitwise operations and haxe.io.FPHelper conversions`。
- :215 Ruling：统一原语集 `readU16/writeU16, readU32/writeU32, readF64/writeF64`，加固定长 ASCII 读写。
- :217 边界检查位置：`Bounds checking lives in reader slice extraction ... and writer capacity growth (ensure in TypeScript, growable BytesBuffer in Haxe, Vec::extend_from_slice in Rust)`。
- :24-38 样例形态：writer 手拆字节 addByte，f64 经 `FPHelper.doubleToI64` 取 high/low 两个 u32；reader 用 Bytes.get 逐字节组装。该样例是大端；TIQTBL03 全小端，出参顺序反转即可。

结论：P2 的 Reader/Writer 不用 BytesInput/BytesOutput，用 BytesBuffer.addByte + Bytes.get + FPHelper（stdlib/05:89-92 `FPHelper continues to carry binary64 bit patterns through high and low words`），与 Canonical.hx 的 Writer 同形态。

### haxe.Json 不在子集内（stdlib/ 全目录检索）
- docs/specs/ 下 grep `haxe.Json` 与 `Json.parse` 零命中；stdlib/06-std-modules.md、stdlib/12-std-string.md 均未列 JSON。
- 结论：face/typography/valueStyle/revision 四个 JSON 文本区，Haxe 侧只做字节区搬运（写入方收已序列化的 canonical JSON 文本，读取方交回原始文本），JSON.parse/stable_stringify 留平台壳；这符合 6.2 节「出口语言零手写读写代码」——JSON 解析不属于字节读写。

### TIQTBL03 布局与语义权威（既有实现）
- snapshot_table_binary.rs:9-35 布局注释：magic "TIQTBL03" 8 字节 + 12 个 u32 计数（56 字节头），string/delta 区 u32 增量自隐式零累加。
- snapshot-table-binary.ts:8-13 常量：HEADER_U32_COUNT=12、METRIC_POOL_ROW_BYTES=40、PROBE_STYLE_ROW_BYTES=25、ABSENT_METRIC_BITS=0x7ff8000000000000n。
- table-binary-writer.ts:200-253 region 顺序逐项：strings(delta+bytes)、metric 六列、valuePool(5xf64)、probe 三列、advancePool(f64)、stylePool(25B)、features(delta+bytes, 行=u16 count+count x u32)、face/typography/valueStyle/fontPreload 四个 delta+bytes、revisionText 尾区。
- metric 行排序键 (familiesRef, weight, italic, roleRef, faceSelectionRef)：snapshot_table_binary.rs:109-118 total_cmp；table-binary-writer.ts:132-137 数值比较。f64 排序比较在 Haxe 侧的形态待取证（total_cmp 与 JS < 的 NaN 行为不同；表内容 weight 为正常值时等价）。

## FPHelper.i64ToDouble 调用形态（P2 补记，修正版，pin 4f412c6a）
- 规定签名以 boring 仓库样品为准：samples/boring/BinaryReader.hx:40-44 `return haxe.io.FPHelper.i64ToDouble(low, high);`（低位字在前），同族 samples/boring/Fp32.hx:35/:52/:56 一致。
- 运行时互逆性：gen/runtime.ts doubleToI64 返回 {high: getUint32(0), low: getUint32(4)}（DataView 默认大端），i64ToDouble(low, high) 做 setUint32(0, high); setUint32(4, low)，两者严格互逆。
- 撤回：本文件早前一版把「生成出 i64ToDouble(high, low)」判为发射端缺陷，实为 P2 源码自身把参数序写反（400.0 解成 5.34416817e-315 正是高低字互换位形）；发射端按源序转发行为正确，不向 boring 提修复。
- 手册新增比对规则（队长 2026-09-27 落 PIT）：凡「目标侧签名/参数序不符」结论，第四步之前必须先从 samples/boring/** 与对应 spec 抄下同一调用的签名做比对，不得以对 std 的印象为基准。

## assembly-record 冻结产物标注（P2，提交 5d366296）

- tools/schema 两个生成器已删除，ffi/schema 的 assembly-record TS/Rust DTO 产物在 5d366296 冻结；ffi/schema/FROZEN.md 就地标注，P5 接线前不得当作可重生成产物。

## Rust decodeInto weight 读数待查（P2 遗留，pin 4f412c6a）

- 现象：同一份冻结字节（weight=400.0，LE 字节 00 00 00 00 00 00 79 40 已核在位），TS decodeInto 解出 400，Rust decodeInto 解出 0.0（27/28 快照测试，唯一失败 restore_keeps_rows_and_the_url_stable）。
- 已排除：壳层 Json 降级与字符串表映射（instrument 证实进入 decode_into 前文件字节正确、之后 TableData.metric_rows[0].weight=0.0）。
- 待办：按四步取证追 Rust 目标 TableReader.f64 的降级与 FPHelper::i64_to_double 调用（Rust 运行时签名 (low, high) 与 TS 一致，但需核对 Rust 发射端参数转发与 u32 组装路径），并核对 cutover 席 f1b28bd3 之后的发射端修正是否覆盖。

## Stage1-P5b Kotlin 侧替换的记录（pin f1b28bd3）

### rawGapEm 局部绑定（Kotlin 收窄，可回退）
- ParagraphRequestChecks.hx 的 `emphasisDotGapEm` null 检查改绑到局部 `rawGapEm` 再三元（:37-42）。
- 触发原因：Kotlin 发射端 KotlinExpr.hx:821 的 expression-if 不能对 `var` 类属性 smart-cast（`request.emphasisDotGapEm` 为 `Double?` var 属性，`if (request.emphasisDotGapEm == null) else request.emphasisDotGapEm` 中 else 分支不能把 Double? 收窄到 Double）。绑到局部 val 后 `val rawGapEm: Double?` 在条件分支内可收窄。
- 证据四步：① 源结构=ParagraphRequestChecks.hx:37-42 的 null-coalesce；② 发射端=KotlinExpr.hx:821 的 expression-if 渲染；③ 生成物=ParagraphRequestChecks.kt 的 `val rawGapEm = request.emphasisDotGapEm; val gapEm = (if ((rawGapEm == null)) 0.1 else rawGapEm)`（:5-6，else 分支 rawGapEm 收窄为 Double）；④ 失败点=不带局部绑定时代码 kotlinc 报 smart-cast impossible。
- 可回退标记：boring 里程碑下已单开条目（「var 类属性的空值收窄不发 smart cast」），发射端修好后允许回退此处形态，届时直接把 `rawGapEm` 与 `: Float` 还原为单表达式。
- 涟漪：TS vendored ParagraphRequestChecks.ts 与 Rust vendored paragraph_request_checks.rs 同为局部绑定形态，语义等价（多一个局部变量）。

### 跨字段并存坏输入的次序变化
- 13 处区段错误名从 parse* 内联 require 挪到 ParagraphRequestChecks.validate 单入口后，跨字段并存坏输入的命中名字会变。
- 具体例：`plan(workerRequest { text="中文" (2 单元); textSpans=[{start=0,end=5,...}]; inlineObjects=[{start=1,end=3,advance=18.0,ascent=14.4,descent=4.32}] })`——textSpans end 越界（5>2）且 inlineObjects end 越界（3>2）。
  - 改前（旧代码）：plan() 中先 `parseInlineObjects(inlineObjects, text.length)`（行 :168 后）再在 LayoutInput 构造中 `parseTextSpans(textSpans, locale, text.length)`。inlineObjects range 检查触发 InvalidInlineObjectRange，不进入 parseTextSpans。
  - 改后（新代码）：parse* 仅组 Input 无校验，validate 按固定序（标量 → textSpans → sourceBoundaries → lineBreakSpans → inlineBoxes → inlineObjects → decorations）。textSpans loop 先触发 InvalidTextSpanRange。
  - 名前后的变化：InvalidInlineObjectRange → InvalidTextSpanRange。
  - 仅跨字段并存时可见差异；现有 6 个错误断言测试各只触发单字段，单字段命中名不变。
- 对比表（现有 Kotlin 测试能触发的单字段坏输入，名前名后一致）：
  | 测试 | 坏输入 | 改前名 | 改后名 | 变？ |
  |------|--------|--------|--------|------|
  | emptyTextThrowsEmptyParagraph | text="" | EmptyParagraph | EmptyParagraph | 否 |
  | textSpansRangeOutOfBoundsThrowsInvalidTextSpanRange | textSpans=[{0,5}] text="你好"(2) | InvalidTextSpanRange | InvalidTextSpanRange | 否 |
  | inlineObjectsRangeOutOfBoundsThrowsInvalidInlineObjectRange | inlineObjects=[{1,5,...}] text="中文"(2) | InvalidInlineObjectRange | InvalidInlineObjectRange | 否 |
  | invalidEmphasisDotGapEmThrows(neg) | emphasisDotGapEm=-0.1 | InvalidEmphasisDotGapEm | InvalidEmphasisDotGapEm | 否 |
  | invalidEmphasisDotGapEmThrows(NaN) | emphasisDotGapEm=NaN | InvalidEmphasisDotGapEm | InvalidEmphasisDotGapEm | 否 |
  | invalidDecorationWireUnknownKindThrows | decoration kind="UnknownKind" | IllegalArgumentException(valueOf) | IllegalArgumentException(valueOf) | 否 |

### 5 个 Kotlin 独有名的触发（pin f1b28bd3，经对外入口可达）
- InvalidEmphasisDotGapEm：planWithDiagnostics(prepareRequest { emphasisDotGapEm=-0.1 })，已有测试无效。
- InvalidInlineObjectRange：plan(workerRequest { text="中文"; inlineObjects=[{1,5,18.0,14.4,4.32}] })，已有测试无效。
- InvalidInlineObjectAdvance：plan(workerRequest { text="中文"; inlineObjects=[{0,1,-1.0,14.4,4.32}] })，advance<0，新测试 inlineObjectsNegativeAdvanceThrowsInvalidInlineObjectAdvance。
- InvalidInlineObjectVerticalGeometry：plan(workerRequest { text="中文"; inlineObjects=[{0,1,18.0,Double.NaN,4.32}] })，ascent NaN，新测试 inlineObjectsNaNAscendsThrowsInvalidInlineObjectVerticalGeometry。
- InvalidDecorationRange：planWithDiagnostics(prepareRequest { text="你好世界"; decorations=[{3,2,"Underline"}] })，start≥end，新测试 decorationsReversedRangeThrowsInvalidDecorationRange。

## Stage1-C LoweringHelper 席（JS 侧四导出消费 ts 目标配置生成物，pin f1b28bd3 @ tiqian 45e65d51）

### 生成与闭包
- 驱动器：`rm -rf engine-haxe/out/ts && nix develop -c bash -c 'node <workspace>/boring/out/bundle/driver.js gen ts --project boring.json'` → `bundle driver: ok`，gen 树 282 个 `.ts`；所需九类（CjkFontRoleClassifier / FontRole / FontRoleContext / InlineShapingStylePolicy / TextRange / QuotePairAnalyzer / ContextualDashEllipsisRoleResolver / UnicodeEmojiPresentationData / UnicodeSymbolData）全部在场，靠测试入口传递编译进 ts 目标配置，无需加根（队长主检出实测同结论，405 个 .ts 口径含 gen-tests）。
- 闭包 31 文件 / 201.5 KB（import 闭包脚本实测，含 `runtime.ts`）；vendored 落 `ffi/js/npm/engine-gen/`。与 Font 席已落文件 cmp 逐字节相同 → 生成确定性成立，合并 add/add 无冲突。

### Node 直载失败（为什么必须 tsc 编译路线）
- `engine-gen/org/tiqian/core/TextRangeError.ts`（1-17 行）整体为 interface/type 别名，零运行时导出；`TiqianIllegalArgumentException.ts:3` `import { TextRangeError } from "./TextRangeError.ts"` 是值导入形态。
- Node v22.23.1：`--experimental-strip-types` 与 `--experimental-transform-types` 下 import 均报 `The requested module './TextRangeError.ts' does not provide an export named 'TextRangeError'` → 生成 TS 不经 tsc 编译无法被 Node 链接；故 npm 包走 tsc（`rewriteRelativeImportExtensions` 把 `.ts` 规范式重写为 `.js`，P6 server-core 先例）。
- 同因排除「Kotlin/JS @JsModule 引 .ts」路线：需要额外 TS→JS 编译步骤（Clreq 席闸门同判）。

### tsc 配方与有界放宽（出口：T1/T2）
- 配方（LineBreak 落地后的共享配置 `ffi/js/npm/tsconfig.engine-gen.json`）：tsc 5.9.3，`target es2022 / module nodenext / rewriteRelativeImportExtensions / outDir runtime/engine-gen / rootDir engine-gen / include engine-gen/**/*.ts`，由 `build-runtime.ts` 在 Gradle Sync 之后对全闭包（四席并集）一次编译；tsc 默认档无 strict 键（即 strictNullChecks 未开）。
- 唯一放宽：`strictNullChecks: false` 以显式键仅落在 vendored 目录自身配置 `ffi/js/npm/engine-gen/tsconfig.json`（包级/工作区级 tsconfig 不写显式放宽键，闸门裁定；该局部配置即本目录的 strict 姿态与放宽记录的规范位置）。命中的具体诊断：TS2322 @ `engine-gen/org/tiqian/font/FontRoleContext.ts:13`（`this.regionHint = regionHint;`，参数 `regionHint?: string | null` 的 `undefined` 可能不可赋给字段 `readonly regionHint: string | null`）——生成代码不可手改，放宽有界。取消条件：T1/T2（tiqian TypeScript 严格档清零与 boring 自身 TS 严格档转绿）落地、发射端产出 strict 干净构造器后，删掉该键并以 strict 重编验证。

### 旧产物 JS 可见错误名（旧 runtime 实测，47 例 fixture dump 基线）
- TextRange 校验抛 Kotlin data object，JS `error.name` 是对象名：`NegativeStart` / `StartGreaterThanEnd`（非 sealed 基类名）；消息与生成物 `TiqianIllegalArgumentException.describe`（`TiqianIllegalArgumentException.ts:14-25`）逐字一致："TextRange start must be non-negative." / "TextRange start must not be greater than end."
- `classifyFontRoles` size 不符：`require` → JS `error.name = IllegalArgumentException`，消息 "starts and ends must have the same size"。
- 越界输入（`("中", 5, 7)`）：旧产物返回 `"other"`（Kotlin/JS `String[index]` 越界得 NUL，`codePointAtCompat`（FontPolicy.kt:161-169）回 0 → Unknown），生成 TS 同（`charCodeAt` NaN → Unknown，`CjkFontRoleClassifier.ts` classify 首行）——一致，facade 无需补 guard。
- facade 归一：catch 生成 `TiqianIllegalArgumentException`（`error.error.kind`）按对象名重抛；size 校验按 `IllegalArgumentException` 重抛（`ffi/js/npm/src/loweringhelper-facade.mjs`）。

### 生成物 contextual 链入口（调用形态）
- `QuotePairAwareFontRoleClassifier.withContextualQuoteRoles(base, text, context)`（`QuotePairAnalyzer.ts:216-243`，静态在 Aware 包装类上，不在 QuotePairAnalyzer 上）；`ContextualDashEllipsisRoles.withContextualDashEllipsisRoles(base, text, context)`（`ContextualDashEllipsisRoleResolver.ts:209-236`，静态在 `ContextualDashEllipsisRoles` 载体类上）。与 Haxe 测试调用形态一致（`ContextualRoleExtensionCoverageTest.hx:27-36`）；链序 quote → dash/ellipsis 同 Kotlin facade（LoweringHelperExports.kt:86-89 改前序）。

### 验收读数
- 47 例 fixture dump（`node .tq-logs/js-lh/dump.mjs <module> <out.json>`）：旧产物 `runtime/Tiqian-tiqian-ffi-js.mjs` 与改后 facade（`tsc -p engine-gen/tsconfig.json` 后 `runtime/loweringhelper-facade.mjs`）`diff` 为空，逐字节一致（含 16 属性清单顺序、diverge@0..15、clamp、全部错误名与消息）。
- `./gradlew :ffi:js:jsNodeTest`（GRADLE_USER_HOME=<工作树>/.gradle-home，nix develop 内 JDK 25）：改 Kotlin 后 BUILD SUCCESSFUL。`assembleNpmPackage` 的 Sync 会清 runtime/（与 Font 席互证）——vendored 在 engine-gen/、构建经 build-runtime.ts 在 Sync 后复制（LineBreak 席机制）。`f32` 口径不适用：四导出零数值输出。
## Stage1-落地JS-Font（FontExports 消费 ts 目标配置生成物，pin f1b28bd3）

## font 类如何进 TS 产物（队长裁决 (c) 的取证链）
- 目标配置与根：引擎 ts 配置（boring.json `ts`，rootsFile engine-haxe/targets/ts.hxml，include engine-haxe/targets/classes.hxml）。classes.hxml 是六个引擎目标配置共用的根清单（:75、:155-:165 只列 font 的数据与测试类），font 的能力类本体（CjkFontRoleClassifier/FontPolicy/FontMetrics 等）未列为根。
- 进入方式：靠根类的引用闭包传递编译进产物。实测（本工作树，rm -rf engine-haxe/out 后 driver gen ts，RC=0，405 个 .ts）：engine-haxe/out/ts/gen/org/tiqian/font/ 24 文件，含本席所需的 FontMetrics.ts（FontMetricsRequest/StubFontMetricsResolver）、FontPolicy.ts（FontRequest/FontCandidate/FontDecision/FallbackResolver）、PreferCjkForAmbiguousPunctuationResolver.ts、FontRole.ts、FontMetricSource.ts、core/TextRange.ts。
- 改法：不加根、不动 classes.hxml、不动 protocol 目标配置（队长裁决）；直接消费既有 ts 目标配置生成物，vendored 只搬所需闭包。

## vendored 闭包与打包约束
- 闭包（14 文件，import 全部相对 .ts 范式，零 @tiqian/runtime 依赖）：org/tiqian/font/ 11 个（FontMetrics/RawFontMetrics/BaselineClass/BaselinePolicy/FontMetricSource/FontMetricsPolicy/FontRole/LayoutFontMetrics/MetricBox/FontPolicy/PreferCjkForAmbiguousPunctuationResolver）+ org/tiqian/core/ 3 个（TextRange/TiqianIllegalArgumentException/TextRangeError）。落点 ffi/js/npm/engine-gen/。
- 硬约束（实测）：`./gradlew :ffi:js:assembleNpmPackage` 会清空重建 ffi/js/npm/runtime/（先放的 vendored 文件被抹掉），vendored 生成物与 TS 源不能放 runtime/ 下；package.json files 只发布 runtime/，facade 须把 engine-gen 打进 runtime 产物——入口机制归 LineBreak 席统一落地。

## 对外数值口径（TCN-45，队长 2026-09-27 裁决）
- 旧 Kotlin/JS 出口数值带 f32 网格伪影：FontExportsTest.kt:43 钉 descent=5.184000015258789（f64 应为 18*0.288=5.184）。基线 dump 48 用例（/tmp/font-dump.mjs 对旧 bundle，/tmp/font-baseline.txt）证实小数尺寸输入普遍带伪影。
- 新判据：JSON 形状（字段名/序/可空省略规则）、错误名与错误类型、f64 语义数值与旧产物一致；不模拟 f32。依据：引擎几何本身 binary32（研究文档第 7 节第 1 条），喂回引擎后得同一 f32 结果，可观察排版行为不变。
- 迁移断言：FontExportsTest.kt 两条 metrics 用例随迁 TS 侧，保留输入与结构，仅期望数值按 f64 改写。

## 请求模型解析：仍是手写壳
- FontMetricsRequest/FontRequest 的 JSON 解析本轮保留为手写薄壳（ffi/js/npm/src/fontFunctions.ts 内 parse*，语义逐条对照 WireJson.kt:28-58/82-90），未进任何协议目标配置；请求模型单源化留给后续模块。此壳迁移时语义保真点：字段缺省（fontKey=""/fontSize=NaN/role=Unknown/locale=""/fontWeight=400/italic=false）、role 非法串抛 IllegalArgumentException（Kotlin FontRole.valueOf）、数组元素非串填空串。

## 比对读数（pin f1b28bd3，ts 目标配置本机驱动器 gen RC=0）
- 同 fixture 矩阵 diff 旧 bundle 与新适配器：48 行中 16 行有差异，全部是 metrics 数值的 f32→f64 位（如 16.1 尺寸 ascent 18.676000595092773→18.676000000000002），fallback 6 行与错误行为（THROW:IllegalArgumentException）逐字节一致。
- f64 精确值注意点：18*0.288 的 f64 最短表示是 5.183999999999999（非 5.184），迁移金值按实际最短表示钉（font-facade.test.mjs）。

## 入口接线（rebase 到 e5b2b6b5 后，照 LineBreak 形态）
- src/font-facade.mjs：纯 JS 线翻译（JSON 进出、IllegalArgumentException 名字保真），import 编译产物 ./engine-gen/**.js；src/fontFunctions.ts（TS 版适配器，提交 c4f31b4b 内）被此形态取代后删除。
- facade.mjs/facade.d.mts：font 两名从 Kotlin 生成物解绑改由 font-facade 提供，12 名与顺序不变；build-runtime.ts 的 facade 拷贝清单加 font-facade.mjs。
- Kotlin 侧删除：FontExports.kt 整文件；WireJson.kt 的 parseFontMetricsRequestJson/parseFontRequestJson（唯一使用方是 FontExports.kt；appendFontMetricsRequestJson 留守，JsCallbackAdapters/WireJsonTest 仍用）；FontExportsTest.kt 删两条 metrics 用例，classifyFontRole 两条留守（对象是 LoweringHelper 导出，属 js-lh 席）。
- 发射端偏差（vendored 副本就地修正并记录）：TiqianIllegalArgumentException.ts 的 import 语句对 TextRangeError 取值导入，而 TextRangeError.ts 只发射类型联合，Node 类型剥离无法链接；vendored 副本改 import type。boring 里程碑侧已知的同类发射端缺口，发射端修复后可回退。

## Stage1-P3 plan 模型与序列化（生成器修订 256d06bd）

### 模块名与文件名的解析（Haxe 主类型规则）
- 现象：`org.tiqian.protocol.Plan` 作为 root 报「Type not found : org.tiqian.protocol.Plan」——因为 Plan 是 typedef，定义在 PlanModel.hx 里，Haxe 按文件名解析主类型。
- 规则：一个 .hx 文件里的类型，只有与文件名同名的是主类型（`org.tiqian.protocol.Foo` 直连）；其余是子类型，全名为 `org.tiqian.protocol.Foo.Bar`，需用 `Plan.PlanLine` 引用或 import 模块。
- fix：Plan 系 typedef 都塞进 Plan.hx（Plan 是主类型），证据类（PlanLine/PlanCell/PlanInlineEdge/…）以 `Plan.PlanLine` 形式引用；PlanSchema 独立成 PlanSchema.hx 才能作为 root。

### Null<T> 收窄（Haxe 4.3 编译器，非 boring 发射端）
- 现象：protocol 束 struct 字段 Null<T> 绑到 local final 后 `if (v != null)` 再传 `Std.string(v)` 仍报「Std.string does not accept Null<T> operands」。Pin 256d06bd 含 Kotlin var smart cast 修复，但错误依旧——这是 Haxe 4.3 自身的 null-safety，final 局部不做流式收窄。
- fix：显式 `(v : T)` 转换（ParagraphRequestChecks.hx:43 先例）。
- 配套：struct 数组 `arr[i]` 返回 Null<T>，用 `for (x in arr)` for-each + first 标志替代下标循环。

### static 字段初始化限制
- `public static inline var X = Revision.Y` 报「Inline variable initialization must be a constant value」；改 `static final` 后报「static field initializers accept null, literal, array, and construction forms only」。fix：字面量 + 漂移断言（PlanSchemaTest.planSchemaConstantsAlignWithRevision）。

### PlanJson.encode 架构
- encode(plan:Plan):String 从 Plan typedef 直接串行化；renderEvidence 的 gating 在 lowering（LayoutResult→Plan）阶段完成，Plan 的 Null/空数组即「省略」。
- 字段序照 PreparedParagraph.kt:73-154：schema/layoutRevision/width/height/lines → 每行 rangeStart…endReason/cells → 每 cell rangeStart…leadingLayoutAdvance/shapingBoundary?/openTypeFeatures? → evidence（inlineObject/advance/renderFontFamily/dashStrategy 块/punctuation 块/latin/style）→ 段级 evidence（fontSize/overlayWidth/emphasisRanges/inlineEdges/rubyDecisions/bopomofoDecisions/decorationSegments/emphasisDots）。
- endReason 用 switch 转字符串（NamedErrorNames.describe 先例），不用 Type.enumConstructor。

### 闸门（tq-vendor-check.sh 双向）
- 新增闸门：vendored 生成树 ↔ 驱动器产物双向比对，extras 与 full 挂载的 missing 都必须为零。engine/src/commonMain/kotlin/org/tiqian/protocol/ 是尚未登记进闸门的挂载（只有 rust 与两棵 TS 登记了），搬运必须逐字节等于 engine-haxe/out/protocol-kotlin 产物。
