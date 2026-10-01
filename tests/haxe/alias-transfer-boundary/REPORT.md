# REPORT — alias-transfer-boundary（容器别名跨可空字段与调用边界）

任务：`t-mum17vl5-9rty`（分支 `audit/container-alias-nullable`）。
本报告区分**我实测的**（本轮亲跑的 run `out/alias-transfer-boundary/runs/atb-Wn4rY37a`）与**我引用的**（前次 run `out/alias-transfer-boundary/runs/atb-whb18ccE`，仅用于交叉复核；本轮实测与其逐阶段读数一致）。

## 1. 两组输入与 Haxe oracle 的固定

夹具共 15 件，两组 authored 形状（`atb/ContainerAliasOracle.hx`）：

- **形状 (a) 可空字段 unwrap**：`NullableHolder.values : Null<Array<Int>>`；字段读回、unwrap 成只读 view，保留的可变别名在 view 建立后改写原容器。三个读数：`field`（共享读 = 702，脱共享拷贝 = 101）、`fieldNull`（null 对照 = 0）、`fieldRebind`（view 建立后字段重绑到新容器；保留原存储 = 123，view 跟随绑定 = 987）。
- **形状 (b) 调用 relay**：`relayThrough(Array→ReadOnlyArray 参数, 返回 ReadOnlyArray)`；调用方保留可变别名并在调用后改写。两个读数：`relay`（实参/返回共享 = 3301，任一位置拷贝 = 1201）、`relayFresh`（fresh 对照 = 0）。

authored 期望行（`expected.txt`，固定）：`field=702 / fieldNull=0 / fieldRebind=123 / relay=3301 / relayFresh=0`。

源码哈希（sha256，我实测，本轮与身份阶段 `identity/authored-source-hashes` 记录一致）：

```
64fde642d4b4e5a7182720f42ad7498f7bb8f232ee1c014f86fe4406d704c200  atb/ContainerAliasOracle.hx
c008bc24f1e0c7ebdcd35fcdc2f39cde19abed11618ead0c9f65e585ad61f9eb  atb/NullableHolder.hx
e7369e7fd99f6b22c495d6be6fc2d5023c4ad9d2184ea55abe765960e9a93d3c  expected.txt
9f451c44e6e8931f7c48b78df47431e3f79ef978f4722701137f4ff908b52c7e  run.sh
```

运行前/后输入清单（`input-hashes-before.txt` / `input-hashes-after.txt`）逐字节一致（`input-hashes-after observed=0`），夹具在单次 run 内未被改动。

## 2. 完整 run 与逐阶段状态（我实测）

执行：`bash tests/haxe/alias-transfer-boundary/run.sh`（脚本自分配 run 目录，不覆盖既有 run），证据目录 **`out/alias-transfer-boundary/runs/atb-Wn4rY37a`**。

**直读 rc = 0**（`RUN_SH_RC=0`），summary 判词 `verdict failed`（differences 0，not-reached 5，target-failures 2）。

工具链（本轮身份阶段直读）：haxe 4.3.7、rustc/cargo 1.98.0、Dart 3.13.3、kotlinc-jvm 2.4.10（JRE 21.0.12）、Swift 6.2.4（p09 swiftc shim，wrapper 模式）、OpenJDK 21/25。

五目标逐阶段（各格为**直读 rc**；来源 `stages/<stage>/status`）：

| 阶段 | ts | kotlin | rust | swift | dart |
|---|---|---|---|---|---|
| gen | 0 | 0 | 0 | **1** | 0 |
| compile | 0 | 0 | **101** | **not-reached**（gen=1） | 0 |
| run | 0 | 0 | **not-reached**（compile=101） | **not-reached**（gen=1） | 0 |
| compare | identical(0) | identical(0) | **not-reached**（compile=101） | **not-reached**（gen=1） | identical(0) |

- oracle：`haxe-oracle-compile`=0，`haxe-oracle-run`=0（5 条形状行），`haxe-oracle-expect` identical(0)。
- 未到达阶段如实标注：rust 的 run/compare 因 `compile-rust=101` 未到达；swift 的 compile/run/compare 因 `gen-swift=1` 未到达。脚本以 `not_reached` 显式记录，不冒充语义差异。
- `membership`（stage-check）=0，所有声明阶段均有记录。

## 3. 三件事分开写

### 3.1 可空 unwrap 的观察（形状 a，`field`）

`NullableHolder` 以原容器构造，`holder.values`（可空字段槽）读回为 `ReadOnlyArray<Int>` view；随后可变别名 `original` 改写 `[0]=7` 并 push。ts/kotlin/dart 三目标实测均打印 `field=702`（7×100 + len 2）：**可空字段槽共享原存储，unwrap 读到调用后的改写**；未观察到脱共享拷贝（那会得 101）。null 对照 `fieldNull=0` 实测通过（unwrap 探针可读出空槽，不是常数）。此为对 ts/kotlin/dart 的实测结论；rust/swift 因各自生成/编译缺陷（§2，修复另立行 `t-muovfs5q-5ht7` 与 Swift storage decision 行）**无目标运行读数**，不外推。

### 3.2 字段重绑定的观察（形状 a，`fieldRebind`）

view 建立后 `holder.values = [9,8,7]` 重绑字段。ts/kotlin/dart 实测均打印 `fieldRebind=123`：**已建立的 view 保留原存储（1,2,3），不跟随字段的重绑定**（若跟随会得 987）。即字段槽的重绑定不影响已 unwrap 的旧 view 的身份。

### 3.3 调用后是否保留可变别名的观察（形状 b，`relay`）

`relayThrough(source)` 把容器作为只读实参传入并原样返回；调用方保留的可变别名在调用后改写 `source[0]=33`。ts/kotlin/dart 实测均打印 `relay=3301`（33×100 + len 1）：**实参位置与返回位置都共享原容器，调用不切断可变别名到 relayed view 的通路**（任一位置拷贝会得 1201）。fresh 对照 `relayFresh=0` 实测通过（relay 探针能区分共享与非共享）。

## 4. 探针判别力：该夹具能否失败

- **语义探针有判别力**：每个形状都带判别读数——共享读与拷贝读（702/101、3301/1201）、view 保留 vs 跟随重绑（123/987）取值不同；且 `fieldNull`、`relayFresh`、`fieldRebind` 三个对照证明各探针不是钉在常数上。若某个目标把共享读 lowering 成拷贝（或 view 跟随重绑），对应 `compare-<target>` 的 diff 会非零、`compare-notes.txt` 记录差异、summary 判词变为 `observed-differences`。
- **但 run.sh 本身是观察夹具，不是门禁**：脚本末条语句是 `cat "$RUN/summary.txt"`，其后无 `exit` 语句，且未设 `set -e`；文件头声称 "Only failed and harness-defect exit nonzero"，但 stage 级失败只落到 `VERDICT=failed` 字符串——**实测本轮判词 failed 而直读 rc 仍为 0**。脚本仅有的非零退出路径是开头的 setup/夹具缺失（`exit 1`）与 `.haxelib` dev 指针缺失（`exit 2`）。因此把 rc 当门禁会恒绿；门禁消费方必须读 `summary.txt` 的 `verdict` 字段。

## 5. rust / swift 读数（本轮实测，与引用 run 一致）

本轮亲跑复得（我实测，来源 `atb-Wn4rY37a`）：

- **rust `compile-rust` = 101**：`error[E0308]: mismatched types`，位置 `atb/container_alias_oracle.rs:14:122`（expected u32, found usize；`v.len()` 与 `map_or` 默认值 `0` 被推断为 u32 混用）；诊断形状计数 `grep -cE '^error(\[E[0-9]+\])?:'` = 2（1 个 E0308 + 1 条 "could not compile" 汇总行）。**修复另立行 `t-muovfs5q-5ht7`，不在本任务范围。**
- **swift `gen-swift` = 1**：`atb/ContainerAliasOracle.hx:44: characters 41-54 : swift target: array boundary has no prepared storage decision`（诊断形状计数 = 1）。发射器响亮拒绝，未产出可编译树。**修复另立行，不在本任务范围。**

引用交叉核对：前次 run `atb-whb18ccE`（`out/alias-transfer-boundary/runs/atb-whb18ccE`）在相同夹具哈希下给出完全一致的逐阶段读数（ts/kotlin/dart matched、rust 101、swift gen 1、verdict failed）——本报告不重复引用其产物作为证据，仅作一致性佐证。

## 6. 复算方式

```
PATH=<haxe>/bin:<rust>/bin:<dart>/bin:<p09-swift-shim>:<kotlin>/bin:<jdk>/bin:<node>/bin:~/.bun/bin:$PATH \
HAXELIB_PATH=$PWD/.haxelib \
  bash tests/haxe/alias-transfer-boundary/run.sh
# 产物在自动分配的 out/alias-transfer-boundary/runs/atb-XXXXXXXX/（summary.txt、status.tsv、stages/*/status）
```

本轮工具链与哈希记录在 run 目录 `identity/` 与 `hashes.txt`；输入清单 before/after 一致可复算夹具未被中途改动。
