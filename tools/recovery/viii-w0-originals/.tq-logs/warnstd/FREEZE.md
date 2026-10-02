# 全平台 Warning 清零 · 冻结记录（W0）

时间：2026-09-27 01:5x（本机时区 -04:00）
工具：`tq-warnings.sh`（直方图 + 基线差集）、`scripts/warn-tree.sh`（开一条流的检出对）

## 一、冻结的修订

| 角色 | 修订 | 说明 |
|---|---|---|
| boring（修改基线） | `f740451e` master | 板上「非 Rust 目标警告清零」各条的 baseBranch；CI 那条线 |
| tiqian（被验证侧） | `fabb08a9` main | 六个束的源码 |
| 生成器 | 每条流自持的 boring 检出 | 各 tiqian 检出的 `.haxelib/boring/git` 指向该流自己的 boring 工作树 |

**本轮不推进 vendored pin。** 任务书 W0 原文写「把 .haxelib/boring/git 从 7cb13cf9 推进到冻结修订」，
现场事实与之不符，处置如下：割接 A 阶段已把 pin 冻结在 `be1d8e45` 并声明禁止改动（PIT-63）；
`be1d8e45` 与 master `f740451e` 自 9-21 起分叉、互不包含（PIT-111 的同型）。
所以本轮改为「每条流各持一棵生成器检出」，pin 保持不动；读数一律写明生成器修订。

## 二、基线读数（生成器 f740451e，tiqian fabb08a9）

文件：`.tq-logs/warnstd/warn-base-master.tsv`（列：surface / target / family / count）

| 面 | 目标 | 条数 | 最大族 |
|---|---|---|---|
| tiqian | kotlin-f32 | 778 | `!!` 501、`?.` 89、elvis 87、冗余转换 80、除零 17、未用表达式 4 |
| tiqian | kotlin-f64 | 778 | 同上 |
| tiqian | dart | 914 | `!` 612、dead_null_aware 130、dead_code 104、null 比较 40、pattern 16、未用局部 12 |
| tiqian | ts | 744 | TS18047 324、TS2345 197、TS2322 92、TS2531 85、TS18048 22、TS2532 20、TS2367 3、TS2339 1 |
| tiqian | swift-f32 | 992 (lib) + 480 (tests) | lib：never-mutated 844、will-never-be-executed 144；tests：never-mutated 226、will-never-be-executed 176、immutable-never-used 64、下溢 10、上溢 4 |
| tiqian | swift-f64 | 992 (lib) + 466 (tests) | 同上 |
| boring | kotlin / kotlin-f32 | 42 / 41 | 冗余转换 20、`!!` 13、elvis 6、恒假条件 2、`?.` 1 |
| boring | dart | 59 | `!` 56、dead_code 1、dead_null_aware 1、未用局部 1 |
| boring | ts | 30 | TS18047 13、TS2322 10、TS2345 3、TS2532 2、TS18048 2 |
| boring | swift / swift-f32 | 200 / 198 | never-mutated 166、nil 合并 14、will-never-be-executed 12、未用初始化 4、无抛出 2 |

合计约 6700 条（旧口径）。

**权威基线更新（2026-09-27 05:3x）**：用一对**从未改动**的检出（boring-wt-warn-e1 @ f740451e + tiqian-wt-warn-e1 @ fabb08a9）与修好后的量具重新冻结，
文件 `.tq-logs/warnstd/warn-base-e1.tsv`；与旧基线只差 4 个族行，且**全部在 boring-swift 的 tests 步**——
旧基线那一步因 `missing required module 'SystemPackage'` 链接失败被掩盖成 0 警告（PIT-125 的同型），修好 include 后如实计入：

| 面/目标 | 旧基线 | 权威基线 |
|---|---|---|
| kotlin（四面合计） | 1639 | 1639 |
| ts（两面） | 774 | 774 |
| dart（两面） | 973 | 973 |
| swift（四面合计） | 3328 | **3340** |

另一条口径要点：swift 的模块名必须与树一致（boring 用 Codec / CodecF32，tiqian 用 TiqianEngine），
且库产物文件名必须是 `lib<模块名>.so`，否则测试步链接不上（会把 255 条警告读成 0）。

**Swift 的读数口径**：tiqian 侧必须两步编译——先 `gen` 编成模块 `TiqianEngine`，再把 `gen-tests` 编到它上面。
只编测试树会停在 `no such module 'TiqianEngine'`，一次早停的编译报 1 个 error 0 个 warning，读起来像干净树（PIT-125/PIT-144）。
boring 侧对应模块名是 `Codec` / `CodecF32`。swiftc 走 `/tmp/swift-shim/swiftc-shim.sh`，路径必须全绝对（PIT-53），
并导出 `BORING_SWIFT_SYSTEM_PACKAGE=/tmp/swift-shim/system-package`、`SDKROOT=/tmp/composed-sdk`。

## 三、行为基线（对照物）

六个束的逐条 verdict 落在 `dc-warn/warn/warnstd/verdict-baseline/<id>.jsonl`（远端盘），全部 100% 通过：

| 束 | 条数 | 分布 | md5 |
|---|---|---|---|
| kotlin-f32 | 1342 | 1342 pass | be417708 |
| kotlin-f64 | 1342 | 1342 pass | be417708 |
| ts | 1342 | 1342 pass | e5ba4501 |
| dart | 1342 | 1342 pass | f7803a38 |
| swift-f32 | 1342 | 1322 pass + 20 not_applicable | 99be84f5 |
| swift-f64 | 1342 | 1322 pass + 20 not_applicable | 99be84f5 |

**跑 swift 束必须给预算**：`LD_LIBRARY_PATH=<build> BORING_TEST_RESULTS=<新文件> BORING_TEST_TIMEOUT_MS=600000 <runner>`。
漏掉 BORING_TEST_TIMEOUT_MS 时运行器用 5 秒默认，`PreparedParagraphJfTest.ecmaJsonNumberEdgeCases`（单跑 86 秒）与
`WidthIndependentAnnotationCacheTest.cachedAndUncachedEnginesProduceIdenticalLayoutResultsAcrossWidths` 会被记成
"timed out after 5000ms"，读成 2–3 条真实失败（PIT-71 的 swift 同型）。
swift 的可执行文件必须建在 /tmp：rclone 挂载点上 `chmod +x` 不生效，写上去的 test-runner 一律 EACCES。
任何「不破坏现有测试」的判据都拿它逐条比，不比条数。

## 四、盘

- 生成树与编译产物：`dc-warn/warn/<流>/tiqian-out`（各 tiqian 检出的 `engine-haxe/out` 是软链）；
  远端 865 GB 可用，由 systemd 用户服务 `rclone-warn` 保活（`Restart=always`，实测 kill -9 后 10 秒内自愈）。
- rclone 的本地 VFS 缓存在 `/tmp/rclone-warn-cache`（上限 12 GB、30 分钟过期），不占 /home。
- /home 只剩约 56 GB 且全仓库共用：大文件一律不放 /home。

## 五、复跑方法

```bash
bash tq-warnings.sh measure <label>                      # 重生成 + 直方图
bash tq-warnings.sh diff .tq-logs/warnstd/warn-base-master.tsv .tq-logs/warnstd/<label>.tsv
```

## 六、口径更正与读数三戒（2026-09-27 17:xx，队长）

**dart 的 tests 面此前未被计入（口径漏洞，不是设计选择）**：`count_dart` 只收一个目录，measure 里传的是 `out/dart/gen`，于是「973 → 672」这条口径**只覆盖生成树**；而同一判据下 kotlin 传的是 gen+gen-tests、ts 经 tsconfig 覆盖两面、swift 有独立 tests 步。实测 tiqian dart 的 gen-tests 面另有 **514** 条（`!` 230 / dead_code 98 / null 比较 96 / 未用局部 86 / unused_import 2 / dead_null_aware 2）——**dart 距离「0 诊断」是 672 + 514，不是 672**。

处置：
- `count_dart` 签名改为 `<label> <gen dir> [<tests dir>]`，两套行分别是 `<label>` 与 `<label>-tests`；
- 冻结基线文件（warn-base-e1.tsv）**只有 gen 面**，所以 914/973 那套数字仍与 `tiqian-dart` 行可比；**tests 面没有冻结基线**，从 514 起向下跟踪到 0；
- 以后账本报 dart 余量必须同时写「gen / tests」两个数，不得只报一个。

**读数三戒**（来自 dart2 席本轮三条实测，已入 Wiki PIT-176 / PIT-177 / PIT-178）：

1. **跨修订对照必须换被编译的源码**——`gen` 时的 haxe 编译走的是各 tiqian 检出 `.haxelib/boring/git` 指向的活树；只换 `out/bundle/driver.js` 二进制不构成对照，读数记录里要写 `readlink .haxelib/boring/git` 与 `git -C <pin> log --oneline -1`。
2. **rc 不许取管道尾 `$?`**——那是 `tail` 的退出码；构建/生成/分析一律重定向到日志再单独读码。
3. **远端挂载上的编译/分析读数先 cp 到本地盘**——dart analyze 曾在同一棵树上先后读出 672 与 725；`count_dart` 已强制镜像到 `/tmp/warnstd/analyze-<label>`。
