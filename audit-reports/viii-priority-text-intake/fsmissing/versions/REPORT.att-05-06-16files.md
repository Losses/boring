# dc-fs-missing 观察报告：缺失路径的判定与异常身份

任务 `t-mum1y9jv-74zm`（分支 `audit/dc-fs-missing-path`）。
夹具：`tests/haxe/dc-fs-missing/`（fsprobe 探针 + gen 五目标 hxml + native 各目标 harness + oracle）。
证据目录：`dc-warn/out/fsmissing/attempt-01…06/`；本报告以 attempt-01/03/04（前任）+ attempt-05/06（本次复核）为据。
工作树 `dc-warn/worktrees/fsmissing`（HEAD e1c6597514634fd347d392709793cc19bd96c9a2，夹具 untracked）。

**环境警告（写报告时实测）**：dc-warn fuse 挂载在 18:05–18:12 期间出现目录列表与读取的间歇性不一致
（attempt-02/03/04 一度整目录不可读，稍后又部分可见；`fsprobe/ProbePrint.hx` 在 18:10 从工作树消失，
18:08 的 /tmp 抢救副本中仍有，sha256 见 FILES.sha256）。所有证据已抢救至 `/tmp/fsmissing-salvage/`。
读取本目录任何文件前请预期需要重试。

## ① 现有规则与待裁定点（spec 17 / 03）

**spec 17（docs/specs/stdlib/17-platform-modules.md）第 223–233 行原文**：

> 223: ## Failure behavior
> 225: Failures raise the target's `haxe.Exception` mapping (spec 03) with the
> 226: path and the host error text in the message. An unmapped capability on a
> 227: host (for example `std.Fs` in a browser) raises the same mapping with the
> 228: fixed unavailability message above; it never returns a wrong value.

`samples/std/Fs.hx`：`readText` 在第 18 行、`isDirectory` 在第 32 行；两者对"路径不存在"均无单独条款。

待裁定点（逐条）：

- **P1（未裁定）缺失路径下 `isDirectory` 的返回值**。spec 17:225 只规定"Failures raise"，未规定
  `stat` 失败算不算这里的 "Failure"、`isDirectory(missing)` 应返回 `false` 还是抛异常。
  Haxe oracle（TestCollector.hx 的 npm shim 体，oracle-shim.cjs 头注逐字引用）对 `isDirectory`
  是 `try { statSync().isDirectory() } catch (e) { return false }`——**返回 false**；而五目标生成代码
  无人做这个映射。false-vs-raise 属未裁定区间。
- **P2（未裁定）缺失路径下 `readText` 的异常身份是否跨目标统一**。spec 03 只规则 `haxe.Exception`
  的映射机制（03:9–22），features/06 规则 catch 类型可容性；夹具的 `catch (error:FsProbeFault)`
  是具体类。宿主异常以何种身份到达 catch 子句（包装成 haxe.Exception？目标原生异常？）spec 无逐目标
  身份条款，属未裁定区间。
- **P3（已裁定，见⑤）失败必须 "raise the target's haxe.Exception mapping … with the path and the
  host error text in the message"（17:225–226）**。这一条对 `readText` 类失败是**有文字的裁定**。
- **P4（未裁定）Rust 的失败模型**。spec 03 的 propagation 规则以异常为模型；生成 Rust 侧 `read_text`
  返回 `UString`（非 `Result`）、失败走 `panic!`，而生成代码同时为 try/catch 发射了 `Result<(), FsProbeFault>`
  外壳——外壳永远收不到 Err。panic-vs-Result 的取舍 spec 未裁定。

## ② 实测：oracle 与五目标（原始输出见各 stages 目录）

| 目标 | isDirectory(missing) | readText catch 是否执行 | 异常身份（逃逸者） | 退出码 |
| --- | --- | --- | --- | --- |
| Haxe oracle（js，bun + TestCollector 同体 shim） | **false**（`m1\|isDirectory-returned\|false`） | 否，进程在 m3 前中止 | `haxe.Exception`（JS Error 包装，message=`路径: Error: ENOENT …`） | 1（attempt-03/04 一致） |
| TypeScript（bun，/tmp 副本） | **抛出**（`m0` 后无 `m1`；裸 `fs.statSync(p).isDirectory()`，无 try/catch，`ENOENT: statx`） | 未到达（m1 即中止） | node 原生 `Error`（非 haxe.Exception 形状） | 1（attempt-03/04/06 三次一致） |
| Kotlin（java，attempt-01 两遍编译产物 jar 实跑） | **false**（`m1\|isDirectory-returned\|false`） | 否 | JVM 原生 `java.nio.file.NoSuchFileException`（`Files.readString`，FsProbe.kt:32），生成的 `catch (error: FsProbeFault)` 不捕获 | 1 |
| Dart | 未测得（运行被生成树编译错误阻塞：生成的 `lib/fsprobe/probe_print.dart` 只有注释一行，`@:native("print")` extern 未发射任何声明 → `Error: Method not found: 'print'`，退出 254；attempt-01 与本次 06 两次一致） | 未到达 | 静态读码：`FileSystemEntity.isDirectorySync`→false；readText 抛 `PathNotFoundException`，`on FsProbeFault` 不匹配 | 254（编译期） |
| Rust（rustc 1.98 原生二进制，/tmp 实跑） | **false**（`m1\|isDirectory-returned\|false`） | 否，不可达：`Fs::read_text` 返回 `UString`，失败 `panic!` 于 runtime/fs.rs:6 `fail()` | **panic**（`out/…/no-such-file.txt: No such file or directory (os error 2)`），非 `Result` | 101（attempt-05） |
| Swift | 未测得（编译被环境阻塞，见下） | 未到达 | 静态读码：`FileManager.fileExists(atPath:isDirectory:)` 对缺失路径整体返回 false；readText `throw BoringException(message: path + ": read failed")`；生成 `catch let error as FsProbeFault` 不匹配，`catch { throw error }` 原样重抛 | — |

Swift not-reached 说明：nix 环境内 `swiftc` 被 bwrap 包裹，本机报 `bwrap: setting up uid map: Permission denied`
（attempt-03 identity.txt 记录）。改用 swift-rt 已验证的 raw store swiftc 6.2.4 + FHS rootfs 配方
（`/nix/store/j1bfa7mw…-swift-toolchain-6.2.4-al2`，参照 `dc-warn/out/swift-rt/REPORT.md`），首次编译到
module cache 权限（HOME 迁移后）→ `missing required module 'SwiftGlibc'` → 补 `-fmodule-map-file` 后
`could not build C module 'SwiftGlibc'`（`textual header "assert.h" not found`，-I rootfs include、
解引用 include 树、-nostdsysteminc、独立 modules-cache-path 均复现）。swift-rt 配方此前只编译过**不含
`import Glibc`** 的树；本夹具 FsProbe.swift 内联 lowering 带 `#if canImport(Glibc) import Glibc`，
SwiftGlibc C module 在本环境不可构建。argv/stderr 全程存 `attempt-06/stages/swift-compile/`。
**运行阶段记 not-reached，原因：宿主工具链无法构建 SwiftGlibc C module（环境限制，非沙箱拒绝）。**

probe 局限如实记录：TS 在 m1 即中止，因此 **TS 的 readText 行为本夹具未测得**（m2–m7 空）；
Kotlin/Rust/oracle 到 readText 为止；无人测到 m6/m7 逃逸区之外的输出。

## ③ 输入前后哈希

- attempt-06：`input-hashes-before.txt` 与 `input-hashes-after.txt` **逐字节一致**（23 个受控输入，cmp 通过）；
  唯 `fsprobe/ProbePrint.hx` 在工作树已不可读（见环境警告），before/after 均以 18:08 抢救副本内容为准列入
  `FILES.sha256`。attempt-01/03/04 的 before/after 一致性由其各自 `input-hashes-{before,after}.txt` 与
  status.tsv `input-hashes identical` 行记录。
- 生成物/构件哈希：`attempt-06/artifact-hashes.txt`（swift-gen 六文件、dart probe_print.dart、kotlin 两 jar、
  ts-gen FsProbe.ts、rust lib.rs）；运行副本摘要记录在各 stage 的 `hashes.txt`/argv 旁。

## ④ 结论：**存在目标分歧**

- **D1 isDirectory(missing) 返回值分歧**：oracle=Kotlin=Rust=**false**，TS=**抛出**，Dart/Swift 静态=false。
  其中"false 还是抛"本身属 **P1 未裁定区间**——分歧事实成立，但哪侧违规无可裁定。
- **D2 readText 异常身份分歧**：haxe.Exception 包装（oracle）vs node `Error`（TS，未测到 readText，
  仅以 isDirectory 同类裸抛为旁证）vs `NoSuchFileException`（Kotlin）vs panic（Rust）vs `BoringException`
  （Swift 静态）。身份统一要求属 **P2 未裁定区间**。
- **D3 Rust panic 与生成的 Result 外壳失配**：panic 在 Err 进入 `match __outcome` 之前发生，
  生成的 catch 机制结构性不可达。按任务边界**不定性为可修 bug**；作为 **P4 尚未裁定的失败模型**记录。
- **D4 Dart 生成树编译失败**（probe_print.dart 空文件）：生成器对外 extern 的发射缺失，属实测事实记录。

## ⑤ 尚未裁定的失败模型 vs 已裁定却未实现

**尚未裁定（只记录，不判违规）**：
- P1 缺失路径 `isDirectory` 的 false-vs-raise（D1 的两侧都在未裁定区间内）；
- P2 readText 宿主异常的跨目标身份统一（D2）；
- P4 Rust panic-vs-Result 失败模型（D3）。

**已裁定、实测未实现（spec 17:225–226 有明文）**：
- "Failures raise the target's `haxe.Exception` mapping … with the path and the host error text in the
  message"：oracle 满足（message 含路径+宿主 ENOENT 全文）；**Kotlin 实测逃逸的是裸
  `java.nio.file.NoSuchFileException`，message 无路径前缀拼接**；**Swift 静态读码丢宿主错误文本**
  （仅 `"path: read failed"`）。二者与 17:225–226 的文字不符。是否属应修缺陷、以及 TS/Dart 因运行受阻
  无法实测的部分，留待裁定，本报告不下结论。

—— 报告完。逐 stage 原始证据：各 attempt 目录 `stages/<stage>/{argv,cwd,stdout,stderr,status}`。
