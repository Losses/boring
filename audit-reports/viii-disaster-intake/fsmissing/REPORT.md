# REPORT — 观察 Fs 缺失路径的判定与异常身份（任务 t-mum1y9jv-74zm）

仓库 `boring` @ **e1c65975**，隔离工作树 `dc-warn/worktrees/fsmissing`（detached，未提交）。
证据目录 `dc-warn/out/fsmissing/attempt-01/`（`status.tsv`、`not-reached.txt`、`hashes.txt`、
`identity.txt`、每阶段 `stages/<name>/{argv,stdout,stderr,status}`）。
夹具 `tests/haxe/dc-fs-missing/`（15 个文件，`FILES.sha256`），补丁 `PATCH.diff`。

产生本报告的一次运行：

```
XDG_CACHE_HOME=/tmp/fsmissing-nix-cache DC_FS_MISSING_ATTEMPT=attempt-01 \
  nix develop --command bash tests/haxe/dc-fs-missing/run.sh
```

---

## ① spec 17 / 03 的现有规则与待裁定点（逐条，带行号与原文）

### 已裁定的规则

| # | 出处 | 原文（节录） | 这条规则**说了什么** |
| --- | --- | --- | --- |
| R1 | `stdlib/17-platform-modules.md:225-228` | “Failures raise the target's `haxe.Exception` mapping (spec 03) with the path and the host error text in the message. An unmapped capability on a host (for example `std.Fs` in a browser) raises the same mapping with the fixed unavailability message above; **it never returns a wrong value**.” | 失败**应当**抛出 `haxe.Exception`，消息含路径与宿主文本；未映射能力抛固定不可用消息；**绝不返回错误的值** |
| R2 | `stdlib/17-platform-modules.md:232-233` | “Compilation always succeeds; host support is a runtime property, decided at the call.” | 编译期恒定成功，宿主支持是**运行时**属性 |
| R3 | `stdlib/17-platform-modules.md:163` | “`isDirectory` is `path.metadata().map(|m| m.is_dir())`” | Rust 的 `isDirectory` 已按“取 metadata，出错给 `false`”的方向写死 |
| R4 | `stdlib/17-platform-modules.md:157-160` | “`std.Fs.readText` reads bytes with `std::fs::read` and converts with `String::from_utf8_lossy` … **the read never fails for encoding reasons**” | Rust `readText` 的**编码**不会失败（不是“读不会失败”） |
| R5 | `stdlib/03-haxe-exception.md:187` | “`haxe.Exception` translates to `Result<T, DomainError>` return types in Rust with explicit enum variants … **The failure identity in every language is the variant**, and the message is derived display text.” | 失败身份是**变体**（variant），消息只是派生的展示文本 |
| R6 | `features/06-errors-and-results.md:399` | “**Rust panic and `Box<dyn Error>` returns are banned** for the reasons in the judgment table.” | Rust 目标上 panic 作为失败通道被明令禁止 |
| R7 | `features/06-errors-and-results.md:331`（`### Catch-site lowering`） | 每条 catch 子句按异常类 `instanceof`/`on`/`Result` 收窄，**不匹配的臂原样重抛** | catch 只捕获**它命名的那一类**；宿主原生异常若不属该类就穿透 |
| R8 | `stdlib/17-platform-modules.md:44,53` | `static function readText(path:String):String;` / `static function isDirectory(path:String):Bool;` | 两个成员都声明为**无异常通道的纯值返回**（`String` / `Bool`，非 `Result`、非 `Null`） |

### 待裁定点（本任务真正要判定的边界）

下面每一条都是 R1–R8 **合起来**仍然推不出的问题；本报告只观察，不替规格裁定。

| # | 待裁定点 | 为什么现有规则答不了 |
| --- | --- | --- |
| O1 | **缺失路径上 `isDirectory` 的返回值**：`false`，还是抛异常？ | R8 只声明返回 `Bool`。R1 说“绝不返回错误的值”——缺失路径上 `false` 恰好是**语义上正确**的（路径确实不是目录），所以 R1 推不出“必须抛”。R3 给 Rust 写的是给 `false`，但它是一条 target ruling，不是通例。**尚无规则说四/五目标必须一致。** |
| O2 | **`readText` 抛出的异常身份**：是否必须是该 domain 的变体（R5），还是允许裸的宿主原生异常？ | R5 对**已建模的失败**（decode 之类）裁定得很清楚；`std.Fs` 没有声明任何 error domain，"path missing" 不是一个 Haxe enum 变体。R1 只说“抛 `haxe.Exception` 映射”，没说身份是变体还是消息文本。**这正是本任务题面所说的“缺失路径与异常身份的待裁定点”。** |
| O3 | **Rust 的失败通道**：`Result` 还是 `panic!`？ | R5 说“translated to `Result<T, DomainError>` return types”，R6 直接禁用 panic；但 `std.Fs.readText` 的 Haxe 签名是 `String`，不是 `Result`，而且 `std.Fs` 模块按 spec 17 “No runtime package implements a platform module”，即它**根本没有可承载 `Result` 的签名位置**。于是产生矛盾：要么 `readText` 在 Rust 上**必须**改签名/改机制，要么 spec 17 的 `std.Fs` 是 R5/R6 的一个**豁免区**。**规格没有裁。** |
| O4 | **Rust panic 的“异常身份”**：它要不要能落到 `catch` 里？ | 若 O3 裁定 panic 可用，则 `panic!` 在 Rust 中默认中止进程、**不经过任何 `Result` 臂**，于是 Haxe 的 `catch` 区域在 Rust 上对缺失路径**永远不执行**。这与 R7 “catch 按类收窄”不冲突，却与 Haxe 语义（同一段源码在五个目标上行为一致）冲突。**规格没有说 Rust 的 catch 是否必须能捕获 std.Fs 的宿主失败。** |
| O5 | **“未映射能力”与“已实现但宿主失败”的边界** | R2 的下半句把 “unmapped” 定义为“宿主完全没有该能力”（browser 的 `std.Fs`）。缺失路径**不是** unmapped（能力在，是可用的文件系统），所以不适用那条固定消息；但它到底算 R1 的哪一类失败，规格没有第三类。 |
| O6 | **`isDirectory` 是否允许“吞掉异常”** | R1 的 “it never returns a wrong value” 若被读成“绝不吞异常”，则 TS 与 Rust 在该点都偏离；若读成“返回的值绝不语义错误”，则 `false` 合法。**两种读法都通，规格未裁。** |

---

## ② Haxe oracle 与五目标的实测

### 观察设计

夹具 `fsprobe.FsProbe` 只有一段代码，五个 reflaxe 目标与 Haxe oracle 跑**同一段**：

```haxe
final missing = missingRoot() + "/no-such-file.txt";   // out/fs-missing/probe/definitely-missing/…
say("m0", "probe-start");
final dir = Fs.isDirectory(missing);            say("m1", "isDirectory-returned|" + Std.string(dir));
try   { final text = Fs.readText(missing); say("m2", "readText-returned|" + text); }
catch (error:FsProbeFault) { caught = true; … }  say("m3", "readText-catch-ran|" + Std.string(caught));
                                                 say("m5", "caught-message|" + message);
say("m6", "uncaught-region-start");
final escaped = Fs.readText(missing);            say("m7", "uncaught-region-returned|" + escaped);
```

- `FsProbeFault` 是**仅消息异常**（`extends haxe.Exception`，单 `String` 构造）：这是 `Intercept.hx:765-786`
  （V20）唯一接受的 catch 类型形状，裸 `haxe.Exception` 会被拒绝（“try region catch type carries no payload enum”）。
- 因此 `catch (error:FsProbeFault)` 是一个**具体类**的判断——与生产代码写法一致（R7 的收窄臂）。
- 只测**自己工作树内**的、确定不存在的路径；不读不写工作区外任何位置。
- `m1` 行只有在 `isDirectory` **真的返回**时才打印；抛异常则整条臂中止、状态码即为证据。

### 实测表

| 目标 | `isDirectory` 返回值 | `readText` catch 是否执行 | 异常身份（原始诊断） | 退出码 | 原始输出/诊断片段 |
| --- | --- | --- | --- | --- | --- |
| **Haxe oracle** | **`false`** | **否**（m3 未打印） | `haxe.Exception`（oracle shim 抛出） | 1 | `m0\|probe-start` `m1\|isDirectory-returned\|false`，随后 `haxe.Exception: out/fs-missing/…: Error: ENOENT: no such file or directory, open '…'` |
| **TypeScript** | **抛异常**（m1 未打印） | 否（m0 后即死） | Node `Error`，`code=ENOENT` | 1 | `m0\|probe-start`，随后 `ENOENT: no such file or directory, statx '…'`（调用栈落在 `fsIsDirectory` → `fs.statSync(p).isDirectory()`） |
| **Kotlin** | **`false`** | **否**（m3 未打印） | `java.nio.file.NoSuchFileException` | 1 | `m0…` `m1\|isDirectory-returned\|false`，随后 `Exception in thread "main" java.nio.file.NoSuchFileException: out/fs-missing/…`（`Files.readString`） |
| **Dart** | **`false`** | **否**（m3 未打印） | `PathNotFoundException` | 255 | `m0…` `m1\|isDirectory-returned\|false`，随后 `Unhandled exception: PathNotFoundException: Cannot open file, path = '…' (OS Error: No such file or directory, errno = 2)` |
| **Rust** | **`false`** | **否**（m3 未打印；进程 panic 中止） | **`panic!`**（`runtime/fs.rs:6` 的 `fail()`），不是 `Result` | **101** | `m0…` `m1\|isDirectory-returned\|false`，随后 `thread 'main' panicked at …/rust-gen/runtime/fs.rs:6:5: out/fs-missing/…: No such file or directory (os error 2)` |
| **Swift** | *not-reached*（生成成功，未编译/运行） | *not-reached* | *not-reached* | — | 见下方 not-reached 说明 |

**五目标 `readText` 的 `catch` 全部不执行**：四次是把宿主原生异常抛出、一次（Rust）是 `panic!` 直接终止。
生成的 catch 臂在 TS 是 `if (error instanceof FsProbeFault) … else { throw error; }`、在 Kotlin 是
`catch (error: FsProbeFault)`、在 Dart 是 `on FsProbeFault catch (error)`、在 Swift 是
`catch let error as FsProbeFault` + `catch { throw error }`、在 Rust 是 `match __outcome { Ok(_) => …, Err(error) => … }`；
五者都只匹配 `FsProbeFault` 这一具体类，而宿主给的是各自的原生异常（或 panic），所以都不匹配。

### 生成代码层面的对照（读生成树，不是读预期）

- **TS**：`const fsIsDirectory = (p: string): boolean => { … return fs.statSync(p).isDirectory(); }` —— **裸 `statSync`，
  无 try/catch**；`return fs.readFileSync(p, "utf8") as string` 同样裸传。
- **Kotlin**：`Files.isDirectory(Paths.get(p))`（缺失→`false`）；`Files.readString(Paths.get(p))`（抛 `NoSuchFileException`）。
- **Dart**：`FileSystemEntity.isDirectorySync(p)`（缺失→`false`）；`File(p).readAsStringSync()`（抛 `PathNotFoundException`）。
- **Rust**：`Fs::is_directory` → `match std::fs::metadata(..) { Ok(m) => m.is_dir(), Err(_) => false }`；
  `Fs::read_text` → `std::fs::read(..).unwrap_or_else(|e| fail(path, e))`，而 `fn fail(..) -> ! { panic!(..) }`。
- **Swift**（只生成，未编译）：`boringFsIsDirectory` → `FileManager.default.fileExists(atPath:isDirectory:)`（缺失→`false`）；
  `boringFsReadText` → `guard let data = FileManager.default.contents(atPath: path) else { throw BoringException(message: path + ": read failed") }`。

### Haxe oracle 的身份说明（重要）

Haxe 目标上的 `std.Fs` 是 **JS 平台模块**：编译产物直接读 `globalThis.std.Fs`，没有任何 null 守卫，而该对象由
源码内测试运行器安装（`packages/compiler/TestCollector.hx:375-401` 的 `fsOracle`）。因此 oracle 必须带上这个 shim 才能运行
（`native/oracle-shim.cjs`，逐字复制 `TestCollector.hx` 的 `readText`/`isDirectory` 体）。这意味着：

- **oracle 的 `isDirectory` → `false` 是 `TestCollector.hx` 的 shim 决定的，不是 Haxe 语言语义决定的**；
- oracle 的 `readText` 抛出 `haxe.Exception` 也是同一个 shim 决定的。

这不是缺陷，但必须写明：**oracle 侧测的是“源码内测试运行器所装的 std.Fs”，不是“五目标生成代码的 std.Fs”**。
两者在这两个点上确实不同（shim 给 `false`；TS 生成代码抛 `ENOENT`）。

### not-reached 阶段与阻塞原因（逐条，非留空）

| 阶段 | 阻塞原因（实测） |
| --- | --- |
| `swiftc-lib` / `swiftc-bin` / `run-swift` | **`swiftc` 包装器无法启动**。flake 的 `swiftc` 是把工具链放进 FHS **bwrap** 沙箱执行的包装脚本，而本会话中 bwrap 建不出 uid map：`bwrap: setting up uid map: Permission denied`。根因经实测确认**不是挂载问题**而是**宿主拒绝创建 user namespace**：`unshare --user --map-root-user` 同样以 `cannot open /proc/self/uid_map: Permission denied` 失败，且本进程 `CapEff=0000000000000000`。绕开包装器直接调用工具链二进制可以启动（`swiftc --version` 通过），但它接着因缺少 FHS sysroot 而建不出 `Glibc` overlay 需要的 `SwiftGlibc` C module（`glibc.modulemap:42: textual header "assert.h" not found`）。这两条都记在 `attempt-01/swift-env.txt`。**未用第二条工具链路线强跑**：那会变成另一种观察，不是同一目标的实测。 |

其余进程级环境限制（已处理，不算 not-reached）：dc-warn 是 fuse.rclone 挂载，node/bun/dart 无法从该挂载执行模块，
且该挂载不发布可执行位；因此 TS/Dart 产物与 Rust/Swift 可执行文件在 `/tmp/fsmissing-exec/<attempt>/` 下运行，
拷贝件摘要一并落在 `hashes.txt`。

---

## ③ 输入前后哈希

`attempt-01/input-hashes-before.txt` 与 `input-hashes-after.txt` **逐字节相同**（`status.tsv` 行 `input-hashes identical 0`）。
覆盖 22 个 authored 输入：五目标的 lowering 源（`TsExpr.hx`、`KotlinExpr.hx`、`DartExpr.hx`、`RustRuntime.hx`、`SwiftHostEdges.hx`）、
`TestCollector.hx`、`Intercept.hx`、`samples/std/Fs.hx`、夹具本体（`FsProbe.hx`、`ProbeMain.hx`、`run.sh`、
五个 `gen/*.hxml`、五个 native harness、`oracle.hxml`）。

产出与中间件的摘要见 `hashes.txt`（27 行，含每个阶段 `input`/`output` 角色），例如：

| 角色 | 路径 | sha256（前 16 位） |
| --- | --- | --- |
| oracle 构建输出 | `attempt-01/oracle.js` | `7e6017d87fd85fcb` |
| TS 生成输出 | `attempt-01/ts-gen/fsprobe/FsProbe.ts` | `d3c7386b72d37412` |
| Kotlin 生成输出 | `attempt-01/kotlin-gen/fsprobe/FsProbe.kt` | `2dc1f4f7c1326e69` |
| Kotlin 库 jar | `attempt-01/kotlin-build/library.jar` | `482ab829ccfe7c19` |
| Dart 生成输出 | `attempt-01/dart-gen/lib/fsprobe/fs_probe.dart` | `5095c02bcfc47c1b` |
| Rust 生成输出 | `attempt-01/rust-gen/fsprobe/fs_probe.rs` | `8cccfba19cbc0183` |
| Swift 生成输出 | `attempt-01/swift-gen/fsprobe/FsProbe.swift` | 见 `hashes.txt` |

夹具全部文件摘要另见 `FILES.sha256`（15 行，覆盖 `tests/haxe/dc-fs-missing/` 全部文件）。

---

## ④ 结论

### **存在目标分歧。**

在缺失路径上，五个目标对同一段 Haxe 源码给出**互不相同**的可观察行为：

| 分歧 | 内容 | 属「未裁定区间」还是「已裁定未实现」 |
| --- | --- | --- |
| **D1** | `isDirectory` 返回值：TS **抛 `ENOENT`**；Kotlin / Dart / Rust（生成代码）与 Haxe oracle 均返回 **`false`** | **未裁定（O1）**。R8 只声明 `Bool` 返回，R3 只给 Rust 写了 `false`；规格没有写 `isDirectory` 面对缺失路径该抛还是该给 `false`。**不能据此判 TS 为 bug。** |
| **D2** | `readText` 的异常身份：TS=Node `Error`/`ENOENT`；Kotlin=`java.nio.file.NoSuchFileException`；Dart=`PathNotFoundException`；Swift（生成代码，未运行）=`BoringException`；Haxe oracle=`haxe.Exception` | **未裁定（O2）**。R1 要求“抛 `haxe.Exception` 映射”，但 `std.Fs` 未声明任何 error domain，R5 的“身份即变体”在此**无变体可指**。规格没说身份应当是宿主原生类、`haxe.Exception` 基类，还是某个新变体。 |
| **D3** | Rust 的失败通道是 **`panic!`** 而非 `Result`；由此 `catch` 区在 Rust 上对缺失路径**永不执行**，进程以 **101** 中止（其余四目标都以异常逃逸，非 panic 式中止） | **未裁定（O3 + O4）**，且**不得**在此判为可修 bug——原因见 ⑤。 |
| **D4** | 五目标的 `catch (error:FsProbeFault)` **全部不执行**（四次异常逃逸 + 一次 panic 中止），即 spec 17 的“失败建模”在**任何**目标上都到不了 Haxe 的 catch 臂 | **未裁定（O2/O4）**。R7 只规定 catch 按类收窄，没规定 `std.Fs` 的宿主失败必须能落进 catch。 |
| **D5** | 失败文本：oracle/Kotlin/Dart/Rust/Swift **含路径 + 宿主文本**；TS 的 `statSync` 抛出的 `ENOENT` 消息含路径与 `statx` 文本（`statSync` 甚至连 `isDirectory` 的返回类型都到不了） | R1 的这一半（“消息含路径与宿主文本”）在测到的四个目标上**成立**；TS 因走的是抛异常而非返回，无可比消息。**不构成独立分歧**，故单列说明而非计入。 |

**未观察到分歧的点**：`readText` 在四个测到的目标上**都失败**（没有“静默返回错值”的情形），符合 R1 的后半句；R2（编译恒定成功）在五目标上**全部成立**（五次 `gen-*` 均为 0）。

### 证据不足的部分（明确列出）

- **Swift 缺运行观察**（D1/D2/D4 在 Swift 列只有生成代码旁证，无运行证据）；阻塞原因是宿主 user namespace 限制，非本任务可绕过。
- **`m6`/`m7`（无 catch 区域）没有任何目标到达**：所有目标都在 `m6` 之前就中止或抛出了。因此“无 catch 时宿主失败是否穿透到进程边界”这一点，本尝试**没有直接测到**，只是从 `m5` 之前中止这一事实推断出来的。
- **浏览器/无 loader 分支未测**（spec 17:140 的固定不可用消息）：本夹具只覆盖“宿主有文件系统但路径缺失”。

---

## ⑤ 「尚未裁定的失败模型」与「已裁定却未实现」的区分

这两类在证据里的**处理方式必须相反**：前者是**等人裁**，后者才是**待修**。本报告据以分类的判据如下。

### 判据

一条分歧属 **「尚未裁定的失败模型」**，当且仅当存在**互相矛盾**的两条已裁定规则、或该情形**落在任何已裁定规则的适用范围之外**；
此时规格给出的是**开放区间**，测到的任一行为都**不能**据此判为缺陷。

一条分歧属 **「已裁定却未实现」**，当且仅当规格**已经明确写死**某个行为，而某目标的生成代码与该条明确文字**直接冲突**。

### 归类

**（甲）属「尚未裁定的失败模型」——D1、D2、D3、D4。**

- D3/D4（Rust panic）**特别说明**：它看起来最像缺陷，因为 R6（`features/06-errors-and-results.md:399`）明写 “Rust panic … are banned”。
  但它**同时**满足裁定冲突的三个特征，故**不予判负**：
  1. R5 说 `haxe.Exception` 译为 `Result<T, DomainError>`，而 `std.Fs.readText` 的 Haxe 签名是 `String`（R8），**没有 `Result` 位置**；
  2. spec 17 明写 `std.Fs` **没有运行时承载**（“No runtime package implements a platform module”），因此也没有“domain error 枚举”可声明；
  3. R1 又说失败**应当抛出**——在 Rust 上“抛出”只有 panic 一条路。
  即：R6 的禁令与 spec 17 的 `std.Fs` 机制**在缺失路径这一情形上互相矛盾**，规格未裁谁让谁。
  **因此本报告不把 `panic!` 定性为可修 bug**（这正是任务书的非目标），只记录为“待裁定的 Rust 失败模型”，并点明它必须由规格裁定后才能变成工单。
- D1/D2 同理：R1 的 “never returns a wrong value” 有两种都通的读法（见 O6），规格未裁。

**（乙）属「已裁定却未实现」——本尝试中 **0 条**。**

逐条核对已裁定文字，未发现任何目标**直接违反**规格明文：
- R1“抛 `haxe.Exception` 映射”：五目标**都抛/都中止**（TS/Kotlin/Dart/Swift 抛原生异常，Rust panic），
  但“映射到什么身份”未裁（O2），故不构成“直接冲突”。
- R1“never returns a wrong value”：测到的四个目标都没有返回语义错误的值（`false` 在缺失路径上语义正确），**满足**该规则。
- R2“compilation always succeeds”：五次生成**全部 0**，**满足**。
- R3（Rust `isDirectory` = `metadata().map(is_dir)`）：生成代码**逐字符合**，**满足**。
- R6（禁 panic）：与 R5/R8 冲突（见上），归入待裁定，**不判为已裁定未实现**。

### 反向提示（避免把“未裁定”当“缺陷”）

- TS 的 `isDirectory` 抛 `ENOENT` **不是**已证实的 bug：它是 O1 未裁定的另一种合法读法；
  但**可以**指出它使 `isDirectory` 的 `Bool` 返回类型（R8）在缺失路径上**不可达**，这是一个**规则层面的问题**，需规格裁定。
- Rust 的 `fail()` 是 `panic!` **不是**已证实的 bug：它是 O3 未裁定的产物，且与 R6 有明文冲突，
  需规格先决定 `std.Fs` 的失败通道（`Result` 化 / 例外豁免 / 新增变体），才能产出工单。
- Haxe oracle 的 `false` **不是**“Haxe 语言实测”：它是 `TestCollector.hx` 的 shim 选择（见 ② 末尾），把它当作“Haxe 目标应然行为”会重复题面警告的错误。

### 需要规格回答的一个最小问题集（供裁定）

1. `isDirectory` 面对缺失路径：返回 `false`，还是抛出？（O1）
2. `readText` 抛出的身份：宿主原生类、`haxe.Exception` 基类，还是 `std.Fs` 新声明的变体？（O2）
3. Rust 上 `std.Fs` 是否享有 R6 的豁免；若不豁免，`readText` 的签名/机制如何改？（O3）
4. 若 3 保留 panic：Haxe 的 catch 区在 Rust 上是否**必须**捕获 `std.Fs` 的宿主失败？（O4）

---

## 附：本尝试的可复算清单

- 入口：`XDG_CACHE_HOME=/tmp/fsmissing-nix-cache DC_FS_MISSING_ATTEMPT=<id> nix develop --command bash tests/haxe/dc-fs-missing/run.sh`
- 状态表：`attempt-01/status.tsv`（15 个记录阶段 + `input-hashes`；3 个显式 not-reached）
- 未到达说明：`attempt-01/not-reached.txt`
- 每阶段：`attempt-01/stages/<stage>/{argv,stdout,stderr,status}`
- 身份：`attempt-01/identity.txt`（工作树、HEAD=`e1c6597514634fd347d392709793cc19bd96c9a2`、工具链版本）
- 夹具补丁：`PATCH.diff`（15 个新增文件；**无** mode 伪差异——补丁全部是 `new file mode 100644`，
  导出时用 `git -c core.fileMode=false`，fuse 挂载丢执行位不产生任何 hunk）
- 夹具摘要：`FILES.sha256`（15 行）
