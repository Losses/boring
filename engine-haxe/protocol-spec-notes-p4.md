# protocol 单源化的 boring spec 阅读笔记（Stage1-P4：manifest 结构与 revision 常量族）

生成器修订：tiqian-wt-p4/.haxelib/boring/git @ 4f412c6a（clean）。每条记录「文件:行 + 原文片段」。
闸门裁决记录：范围（S1 常量族=9 常量、S2 新目标配置、S3 C 头保守+防漂移断言、S4 工作树本地 git 提交）见 2026-09-27 闸门回话。

## 常量形态（features/30-static-fields.md）
- :27-30 现形表：TS 声明被丢弃（缺陷）/ Kotlin "renders correctly as `const val limit: Int = 4096`" / Rust "renders correctly as `pub const limit: u32 = 4096`"。
- Ruling 1（:55-70 表）：TS 补声明 `public static readonly limit: number = 4096;`（类内）、Kotlin 标量与字符串字面保留 const val（:74 "scalar and string literals keep the const val form"）、Rust 标量与字符串字面保留关联 const（:70 "Rust keeps the associated pub const"）。
- Ruling 2（:72-75）：准许初始化值 = null、Bool、Int、Float 字面、String 字面、空数组——本族 9 常量全在表内。
- Ruling 6（:115-119）："Scalar and string static final constants keep the forms that already render on Kotlin and Rust and gain their declarations on TypeScript... Reads of constants stay direct references on all five targets; no lock or wrapper applies to the const form."

## 静态访问（features/16-static-object-access.md）
- :53-54："Type.staticMember is legal on every target"——消费侧直读 Revision.X（TS Revision.LAYOUT_REVISION、Rust Revision::LAYOUT_REVISION、Kotlin Revision.LAYOUT_REVISION）。

## 目标配置与输出目录（features/59-bundle-driver.md）
- :42-50 字段表：id/target/haxeArgs/build/run/package；:45 "One of `haxe`, `ts`, `kotlin`, `rust`, `swift`, `dart`."。
- :58-62 输出目录由驱动器派生 `<outRoot>/<id>/gen` 与 `<outRoot>/<id>/gen-tests`，项目文件不得命名。
- :63-64 generation defines `<target>-output` / `<target>-test-output`。
- :76-87 配方表：haxe 目标 "Build: `haxe` over the reference entry；Run: `bun` on the emitted js；Pack spawns: nothing"；ts 目标 build=none。
- 实现取证（tools/bundle/Driver.hx @ 4f412c6a）：
  - :441-446 genArgs：`if (bundle.target != "haxe")` 才追加 `-D <target>-output=...` 与 `-D <target>-test-output=...`——**haxe 目标没有输出目录 define**，js 输出路径由 hxml 自己的 -js 给（:574-583 测试步同理自带 -js <gen>/test-main.js）。
  - :501-503 step 的 workDir 默认 project.root（工作树根）——生成头入口按相对路径写 out/protocol-c/gen/ 与 cwd 一致。
  - :545-546 gen 前先 makeDirs(gen) 与 makeDirs(genTests)——haxe 目标 gen 时 out/protocol-c/gen 已存在，入口写文件不依赖自造目录。

## 平台模块与子集边界（stdlib/06-std-modules.md、stdlib/17-platform-modules.md）
- 06:17-32：保留命名空间 haxe.*（子集翻译的 std 面）与 std.*（samples/std/ 自有模块）；06:49-62 平台模块是第三类（extern 类、调用点内联发射、宿主无该能力时发射抛错桩）。
- 17:36-55 std.Fs 面：exists/readText/writeText/appendText/makeDirs/readDir/isDirectory；17:225-228 失败契约（抛 haxe.Exception 映射）。
- 结论：四语言子集约束的是五个生成目标（reflaxe 编译器）编译的源；target=haxe 配置走 stock Haxe，不受子集约束。CHeader.hx 用 sys.io.File（stock Haxe js 宿主面），只作 protocol-c（haxe 目标）的根类，五个生成目标配置的根类列表都不含它。std.Fs 在 stock Haxe 下是 extern 无实现（js 端运行期 ReferenceError），故 haxe 目标入口用 sys.io.File 而非 std.Fs。

## Kotlin 发射端取证（packages/compiler/reflaxe/kotlin/kotlincompiler/KotlinDecl.hx @ 4f412c6a）
- :1216 `final kw = field.isFinal && StaticFieldHelper.isConstValue(field) ? "const val" : (field.isFinal ? "val" : "var");`——static final + 常量值 → const val（与 30:74 一致）；静态字段在类声明体内发射（object/companion 由类声明发射决定，以生成文本为准）。

## 五处声明与 C ABI 抄写清单（工作树 5cb8f982 实测）
- "tiqian-layout-v2" 代码声明共 5 处：
  1. engine/src/commonMain/kotlin/org/tiqian/layout/PreparedParagraph.kt:16 `public const val PREPARED_PARAGRAPH_LAYOUT_REVISION: String = "tiqian-layout-v2"`
  2. platforms/web/client/core/src/engine/prepare-paragraph-layout.ts:128 `const PREPARED_LAYOUT_REVISION = 'tiqian-layout-v2';`（同文件 :18 已从 snapshot-schema.js 导入 LAYOUT_REVISION；:251/:295 使用本地常量）
  3. platforms/web/client/core/src/sampler/snapshot/snapshot-schema.ts:3 `export const LAYOUT_REVISION = "tiqian-layout-v2";`
  4. platforms/web/server/precompute/engine/src/schema.rs:12 `pub const LAYOUT_REVISION: &str = "tiqian-layout-v2";`
  5. platforms/web/server/precompute/engine/src/plan.rs:16 `pub const PLAN_LAYOUT_REVISION: &str = "tiqian-layout-v2";`
- 常量族其余手写声明：schema.rs:9（SNAPSHOT_SCHEMA）、:15（RENDER_REVISION）、:18（FONT_SOURCE_POLICY）、:21（FONT_BACKEND_REVISION）、:24（FONT_REPLAY_REVISION）、:27（FONT_REPLAY_TRANSPORT）；session.rs:22（BACKEND_REVISION，FONT_BACKEND_REVISION 的异名重复）、:23（FONT_REPLAY_REVISION 重复）；snapshot_manifest.rs:330 字面 2.0（SNAPSHOT_TABLES_SCHEMA 的隐式声明）；snapshot-schema.ts:1-2（SNAPSHOT_SCHEMA、SNAPSHOT_TABLES_SCHEMA）。
- C ABI 常量 TIQIAN_FONT_BACKEND_PROTOCOL_REVISION=2 共 4 处：
  1. engine/src/nativeInterop/cinterop/tiqian_font_backend.h:23 `#define TIQIAN_FONT_BACKEND_PROTOCOL_REVISION 2u`（cinterop def 只列 tiqian_font_backend.h，engine/build.gradle.kts:161-164）
  2. ffi/rust/tiqian/src/font_backend.rs:18 `pub const FONT_BACKEND_PROTOCOL_REVISION: u32 = 2;`（纯 Rust 镜像，build.rs 只链接不编 C）
  3. engine/src/nativeMain/kotlin/org/tiqian/shaping/NativeFontBackendVtable.kt:18 `internal const val PROTOCOL_REVISION: UInt = 2u`（注释 "Must equal TIQIAN_FONT_BACKEND_PROTOCOL_REVISION in tiqian_font_backend.h"）
  4. ffi/native/src/linuxX64Test/kotlin/org/tiqian/ffi/cabi/LayoutAbiTest.kt:98 `private const val FONT_BACKEND_PROTOCOL_REVISION: UInt = 2u`
- 测试数据/golden 里的同名字面（tests/*.rs fixture、precompute-html-golden.txt、各测试断言）是数据不是声明，不动。

## 生成与验证命令（工作树根）
- 生成（先清空）：rm -rf engine-haxe/out/protocol-{ts,rust,kotlin,c} 后
  nix develop -c bash -c 'node /home/losses/Development/tq-workspace/boring/out/bundle/driver.js gen protocol-ts protocol-rust protocol-kotlin protocol-c --project boring.json'
  （本机 nix 需要 XDG_CACHE_HOME 指向工作区内目录，否则 fetcher cache 只读——DSH 文件沙箱限制，非 nix 缺陷。）
- C 头：gen 后 bun engine-haxe/out/protocol-c/gen/c-header.js（cwd=工作树根）→ out/protocol-c/gen/tiqian_protocol_constants.h。
- TS：(cd platforms/web/client/core && npm test) 与 (cd platforms/web/server/core && npm test)。
- Rust（只在 mac）：cargo build -p tiqian-protocol-gen --lib --tests，走 /tmp/tq-mac-gen.lock 与 scripts/tq-mac-gen.sh，产物 ~/tq-dc/<label>。
- Kotlin：./gradlew :engine:compileKotlinJvm（最小）至 :engine:jvmTest。
- 防漂移断言：precompute engine 测试（schema.rs 测试块扩展）钉「生成 crate 常量 == 字面」与「tiqian ffi 镜像 == 生成值」，并解析 cinterop 目录的 tiqian_font_backend.h 断言 #define 值与生成值相等。

## 生成形态实测（4f412c6a，本轮 gen 四个目标配置后读取 engine-haxe/out/protocol-{ts,rust,kotlin}/gen 与 out/protocol-c/gen）
- TS（out/protocol-ts/gen/org/tiqian/protocol/Revision.ts）：`export class Revision { public static readonly SNAPSHOT_SCHEMA: number = 1; ... public static readonly FONT_BACKEND_PROTOCOL_REVISION: number = 2; }`——与 30 Ruling 1 表逐行一致；消费侧 Revision.LAYOUT_REVISION 直读（16:53-54）。
- Rust（out/protocol-rust/gen/org/tiqian/protocol/revision.rs）：`#[derive(Clone, Copy)] pub struct Revision;` + `impl Revision { pub const REVISION_SNAPSHOT_SCHEMA: u32 = 1; ... }`——**关联 const 带小写类名前缀 REVISION_（与函数发射 canonical_digest 同一约定）**；Haxe Int 映到 u32、String 映到 &str。消费侧用 Revision::REVISION_LAYOUT_REVISION；crate 名 tiqian-protocol-gen（-D package-name，Cargo.toml 自带 autotests=false 与 lints.clippy as-conversions=deny）。
- Kotlin（out/protocol-kotlin/gen/org/tiqian/protocol/Revision.kt）：`object Revision { const val SNAPSHOT_SCHEMA: Int = 1; ... }`——object + const val，与 30 Ruling 1（:74）一致；消费侧 Revision.LAYOUT_REVISION 直读。
- C 头（out/protocol-c/gen/tiqian_protocol_constants.h，gen protocol-c 后 bun 运行 out/protocol-c/gen/c-header.js 写出）：
```
/* Generated by org.tiqian.protocol.CHeader from the single source
 * org.tiqian.protocol.Revision (boring cutover Stage1-P4). Do not edit.
 */
#ifndef TIQIAN_PROTOCOL_CONSTANTS_H
#define TIQIAN_PROTOCOL_CONSTANTS_H

/* C ABI constants of the revision family. */
#define TIQIAN_FONT_BACKEND_PROTOCOL_REVISION 2u

#endif
```
- haxe 目标写文件的宿主通道取证：haxe 4.3.7 对 js 目标拒绝 sys（"You cannot access the sys package while targeting js"，CHeader.hx:35 编译错）；haxe.io.File 在 js 平台不存在（"Type not found : haxe.io.File"，CHeader.hx:38 编译错）；最终用 @:jsRequire("node:fs") private extern（同文件），先例 engine-haxe/src/org/tiqian/test/trace/TestTracePlatform.hx:7-11。std.Fs 是生成目标的平台模块（stdlib/17），stock Haxe 下是 extern 无实现，haxe 目标不可用。
- 四个目标配置的 gen 命令（工作树根，XDG_CACHE_HOME 指工作区内目录）：
  nix develop --offline -c bash -c 'node /home/losses/Development/tq-workspace/boring/out/bundle/driver.js gen protocol-ts protocol-rust protocol-kotlin protocol-c --project boring.json'
  前一步 rm -rf engine-haxe/out/protocol-{ts,rust,kotlin,c}。protocol-ts / protocol-rust / protocol-kotlin / protocol-c 四个目标配置 DRIVER_RC=0；C 头写出 BUN_RC=0（读数含生成器修订 4f412c6a）。
- gen 树是超集（Intercept.run 覆盖 engine-haxe/src 全体被引用类，含 TracedAssertions 拉入的 clreq/core/layout/linebreak 面）；vendor 只拷消费侧 import 需要的文件（P1 先例：protocol-gen 目录只含 canonical 子集）。
