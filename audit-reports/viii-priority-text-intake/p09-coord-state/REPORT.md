# P09 协调态执行根物化 — REPORT

日期：2026-09-29。任务：t-mun7kx9z-hchd（分支 prep/p09-coord-state-inputs）。未 commit / 未启动 verify。

## ① 资产来源表

| 资产 | 来源 | 落位 | 磁盘占用 |
|---|---|---|---|
| 执行根基底 | `rsync -a --exclude node_modules execution-option-c-e1c65975/ → execution-option-c-coord/` | `publication-staging/execution-option-c-coord/` | 17M（本体） |
| `node_modules` | **symlink** → `../execution-option-c-e1c65975/node_modules`（只读复用，未复制） | 新根内 symlink | 0（复用旧根 55M） |
| `.haxelib` | rsync 实体复制（3.2M，非 symlink——PIT-237/239：haxelib 会就地重写 `.dev`） | 新根 `.haxelib/` | 3.2M |
| 6 个生产 `.hx` | **覆盖**为协调树 `boring-wt-architecture/` 当前字节（cp 后逐文件 cmp） | 新根 `packages/compiler/reflaxe/{dart,rust,swift}/…` | — |
| 新增夹具 5 目录 | cp 自协调树未跟踪目录（33 个文件含 stage-check-control.sh） | 新根 `tests/haxe/{dc-null-guard-fallthrough,try-tail,try-tail-min,swift-rt-probe,swift-rt-plain}` + `tests/support/stage-check-control.sh` | — |

总增量磁盘 ≈ 17M（新根本体），未复制 node_modules。

## ② 判据 1：三方一致 + 全量重算

命令：`bash dc-warn/out/p09-coord-state/verify-manifest.sh`

- 新根源码文件数 = **1431**（os.walk 排除 node_modules symlink 与 `.haxelib`，无 extra、无 missing）
- 新清单 `publication-staging/p09-coord-state/option-c-source-before.json` 条目数 = **1431**
- 期望集合条目数 = 1398（`git ls-tree -r e1c65975`）+ 33（新增夹具路径）= **1431**
- **全量重算** sha256+mode：1431 全中，0 缺 0 多 0 不符 → VERDICT: PASS（RC=0）
- mode 口径：e1c65975 内文件沿用 git mode；新增夹具按文件系统 X_OK 推导（run.sh/run-stages.sh/stage-check-control.sh = 100755，其余 100644）。已对 3 个 run 脚本显式 chmod 755（PIT：fuse 链路丢执行位）。
- 清单生成命令：`bash dc-warn/out/p09-coord-state/gen-manifest.sh /home/losses/Development/tq-workspace`
- 运行期资产另立：`publication-staging/p09-coord-state/runtime-assets.json`（8 条，runtime-assets-v1，同旧结构），生成：`bash dc-warn/out/p09-coord-state/gen-runtime-assets-coord.sh <repo-root>`。

## ③ 判据 2：6 文件逐字节一致（cmp，全部 CMP-OK）

| 文件 | 新根 = 协调树 sha256 |
|---|---|
| dart/dartcompiler/DartExpr.hx | `fee42ecb85e85ca3…` |
| rust/rustcompiler/Compiler.hx | `24f79c275c0c493d…` |
| rust/rustcompiler/RustDecl.hx | `985b5ad79373473c…` |
| rust/rustcompiler/RustEmissionState.hx | `2f2119d85b2ab769…` |
| rust/rustcompiler/RustExpr.hx | `cb18968c53b51f66…` |
| swift/swiftcompiler/SwiftDecl.hx | `0210d20703769a4e…` |

（协调者中途核对时看到的"仍是提交态字节"是在 cp 覆盖落盘之前；本报告出具时 6 文件 `cmp` 全部通过。）

## ④ 新增夹具完整性

5 个夹具目录逐文件 `cmp` vs 协调树全 MATCH，文件数一致：dc-null-guard-fallthrough 6、try-tail 14、try-tail-min 4、swift-rt-probe 4、swift-rt-plain 4，另 `tests/support/stage-check-control.sh` 1（=33）。

## ⑤ Loader identity 正控

`.haxelib/boring/.dev` 已改写并 `cat` 确认为
`/home/losses/Development/tq-workspace/publication-staging/execution-option-c-coord`（指向新根本身；`.haxelib` 为实体目录非 symlink）。
`reflaxe/.dev` = `/nix/store/ch901mw058pjvr3nyxgwxps31vc46wmm-source`（未动）。

```
$ bash dc-warn/out/loader-identity/assert-loader-identity.sh …/execution-option-c-coord
OK: boring/.dev points at this execution root
OK: reflaxe/.dev points at pinned nix store source
OK: format/.current pinned = 3.8.0
OK: formatter/.current pinned = 1.18.0
ASSERTION RESULT: PASS — loader identity holds …
RC=0
```

该脚本新增了相对路径归一化（不改断言语义，负控仍失败）。

## ⑥ 旧提交态根/旧清单未动证据（`old-root-untouched.txt`）

- `execution-option-c-e1c65975/.haxelib/boring/.dev`：mtime 1790718402、内容 sha `9433f243…`（与任务开始前基线完全一致）。
- 旧根抽查 DartExpr.hx `a123fe59…`、SwiftDecl.hx `ac657b29…`（= 提交态字节，未动）；旧根 loader 断言重跑 RC=0。
- 旧清单 `p09-e1c65975/option-c-source-before.json`：mtime/size 未变（1790717550 / 236237）。
- **如实披露**：执行中途误触原版 `gen-runtime-assets.sh`（默认输出）使 `p09-e1c65975/runtime-assets.json` mtime 刷新为 1790718702。该脚本确定性只读旧根（旧根未动），重生成内容与原文件逐字段一致（`.dev` sha `9433f243…`、reflaxe `acad6025…`、format `da2b77ad…`、formatter `bdad97e2…` 均与任务开始时读取值相同），无实质变更；如需 mtime 严格不变可从快照恢复。

## ⑦ 还差什么才能启动 verify

1. 上位确认本报告三处判据后，由有权限会话发起 P09 全量 verify（本任务未启动）。
2. verify 驱动需把 SOURCE_MANIFEST 指到 `publication-staging/p09-coord-state/option-c-source-before.json`、runtime-assets 指到同目录 `runtime-assets.json`、根指到 `execution-option-c-coord`（驱动若有路径硬编码需同步改）。
3. Swift 侧 swiftc 编译段此前在本机沙箱 bwrap 被拒（见 integration-apply REPORT ⑤），需完整环境重跑 probe/plain 夹具编译段。
4. `try-tail`（12 形状）夹具本次已随协调树补入新根，其负控/复验证据仍待正式重跑。
5. node_modules 为 symlink：若 verify 会在根内写 node_modules 或要求真实目录，需改为实体复制（+55M）。
