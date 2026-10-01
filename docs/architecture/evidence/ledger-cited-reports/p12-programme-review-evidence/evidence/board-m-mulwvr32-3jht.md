# Board snapshot — milestone m-mulwvr32-3jht "Boring 架构治理（首批跨目标契约与固定版本回归）"

Source: `wb_board milestone=m-mulwvr32-3jht` snapshot, `updatedAt: 2026-09-30T15:18:41.870Z`,
`openRows: 75` (todo/doing), `branches.mode: noop` (the board's git backend returned
`spawnSync but ENOENT`; branch existence is therefore NOT established by the board).
All base branches: `arch/agent-guided-governance`.

## Done rows (status=done; board sign-off requires a confirm= written by captain or human)

33 done rows, transcribed from the snapshot (handle, branch, title, SOP evidence done, updatedAt):

| handle | branch | title | sop | updatedAt |
|---|---|---|---|---|
| t-munu29i9-70b7 | fix/swift-switch-explicit-return | 修 W1：Swift switchExplicitReturn 吞掉 return（各臂被丢弃、.two 分支返回错值）—— 依 02-translator-implementation-standard.md:78/:80 属验收失败，此前无属主 | 3/3 | 2026-09-30T15:17:26.810Z |
| t-mun8mco9-f8e2 | fix/rust-fault-variant-regression | 修 Rust fault 变体登记的回归（PIT-248） | 3/3 | 2026-09-30T00:57:46.942Z |
| t-mun8wag1-okd2 | prep/coord-state-sync-1433 | 同步协调态执行根漂移并重建清单为 1433 | 3/3 | 2026-09-29T22:41:25.069Z |
| t-mun8exgm-2105 | prep/option-c-identity-derive | 修 option-c.plan identity 段写死代际字面量（P09 第二道门） | 3/3 | 2026-09-29T22:19:06.965Z |
| t-mun7kx9z-hchd | prep/p09-coord-state-inputs | 物化 P09 协调态输入（含三处修复） | 3/3 | 2026-09-29T21:53:22.668Z |
| t-mun6xxdc-87l5 | prep/p09-execution-root-e1c65975 | 为 e1c65975 物化 Option C 执行根与 1398 条 SOURCE_MANIFEST | 3/3 | 2026-09-29T21:38:12.455Z |
| t-mun5d99p-op76 | fix/swift-generated-tree-runtime | 修 Swift 生成树缺 Runtime/BoringException 导致编译失败 | 3/3 | 2026-09-29T21:32:03.773Z |
| t-mun6ebzp-rqb1 | prep/option-c-freeze-apply | 把 Option C 33/33 修复应用到冻结运行器本体 | 3/3 | 2026-09-29T21:24:10.169Z |
| t-mum123nj-ywvc | audit/dc-ts-sourcemap-extend | 扩展 TS 诊断源映射至初始化与返回 | 3/3 | 2026-09-29T21:15:02.028Z |
| t-mun5ls9z-xecd | prep/option-c-selftest-33 | 把 Option C 自测 33/33 修复落成可应用补丁 | 3/3 | 2026-09-29T21:11:10.848Z |
| t-mun3ejy5-16zz | fix/dart-fallthrough-nullguard | 修 Dart fall-through 空值守卫的局部非空提升 | 3/3 | 2026-09-29T20:52:36.567Z |
| t-mun4m6gk-jh6t | prep/p09-driver-from-e1c65975 | 按 B2 方案(a) 从固定快照重建 P09 driver | 3/3 | 2026-09-29T20:46:07.515Z |
| t-mum05sop-cbtu | audit/dc-enum-switch-gen | 观察非局部枚举 switch 主体的五目标生成 | 3/3 | 2026-09-29T20:39:23.941Z |
| t-mum082vs-rj70 | audit/dc-place-ts-swift | 扩展可写位置的 TS 与 Swift 观察 | 3/3 | 2026-09-29T20:36:59.181Z |
| t-mulxx76r-apv6 | audit/dc-parameter-identity | 核查比较分析的泛型参数所属声明身份 | 1/1 | 2026-09-29T20:00:12.097Z |
| t-mum13s6o-mogl | audit/dc-kotlin-manifest-version | 锁定 Kotlin 生成清单与 Maven 依赖版本一致 | 3/3 | 2026-09-29T19:51:37.218Z |
| t-mumxd2fs-7xmt | prep/p09-e1c65975-inputs | 重建 e1c65975 固定回归输入 | 4/4 | 2026-09-29T17:48:13.564Z |
| t-mumw1yoc-bs74 | audit/rust-fix-candidate-integration | 准备 Rust 修复候选独立集成树 | 4/4 | 2026-09-29T16:55:36.599Z |
| t-mulwwerf-dq5b | arch/rust-comparison-review | 复核 Rust 比较消费者候选 | 3/3 | 2026-09-29T16:51:20.643Z |
| t-mulwweou-8zqh | arch/typescript-comparison-review | 复核 TypeScript 比较消费者候选 | 3/3 | 2026-09-29T16:29:52.268Z |
| t-mulwwesk-5iq1 | arch/dart-comparison-recovery | 复核 Dart 比较消费者候选 | 3/3 | 2026-09-29T16:23:34.251Z |
| t-mulwweq3-a5vi | arch/kotlin-comparison-review | 复核 Kotlin 比较消费者候选 | 3/3 | 2026-09-29T16:23:22.650Z |
| t-mumvm2xk-y2vu | audit/worktree-archive-inventory | 审计架构治理工作树归档状态 | 4/4 | 2026-09-29T16:19:05.997Z |
| t-mumvio5p-5tj9 | audit/candidate-freeze-merge-review | 审查首批修复候选冻结与安全合并 | 4/4 | 2026-09-29T16:15:46.849Z |
| t-mulxkazm-qbyg | audit/p09-fixed-matrix-preparation | 固定版本 Boring 与 Tiqian 全矩阵验收 | 4/4 | 2026-09-29T16:11:47.951Z |
| t-mum18o33-i6w7 | audit/signed-int-key-composition | 验证有符号 Int 键的结构与组合排序 | 3/3 | 2026-09-29T16:08:45.611Z |
| t-mumupdbv-j6m0 | fix/rust-readonly-alias-emitter | 修复 Rust 只读视图返回与可变绑定 | 3/3 | 2026-09-29T16:08:13.796Z |
| t-mumupzh0-k12r | fix/rust-typedef-signed-key | 修复 Rust typedef 有符号键比较 | 3/3 | 2026-09-29T16:06:41.988Z |
| t-mulxhgxf-ensj | audit/registry-consumer-negative-control | 统一比较消费者登记与注释负控 | 3/3 | 2026-09-29T15:47:44.828Z |
| t-mum0nx0w-1agt | audit/readonly-alias-evidence | 固定五目标普通只读视图共享别名证据 | 3/3 | 2026-09-29T15:40:22.208Z |
| t-mum2o40j-d097 | audit/kotlin-staticfn-publication-evidence | 修复 Kotlin 静态函数字段的局部事实准备 | 3/3 | 2026-09-29T06:00:18.408Z |
| t-mum85x1t-9wej | arch/ts-nullable-lowering-repair | 修复 TS 可空调用与构造参数规范化 | 3/3 | 2026-09-29T05:56:19.137Z |
| t-mum8255v-pti4 | arch/dart-ordinal-coordination-integration | 修复 Dart payload 枚举比较的表示回归 | 3/3 | 2026-09-29T05:43:20.746Z |

Cancelled rows: 1 — t-mumy6q78-vikf "区分阶段存在与生产者成功" (no branch; cancelled 2026-09-29T17:26:03.240Z).

## Open rows that name a gate or a next mechanism (from the same snapshot)

- t-munq08t2-rgxp | gate/p08-swift-readonly-boundary | "P08：接受一个冻结的 Swift 只读数组边界实现候选（含 11 家族矩阵与两份独立评审）" | todo, 0/3 evidence, unclaimed. Created 2026-09-30T06:24:43.670Z. Its description (document claim by the row author, quoting the `arc-landing-list` seat): "板上原有 73 个未完成 row 无一条对应 P08/P09/P10/P12，全部是子任务 —— 故没有任何派单会推进闸门，这是'闸门一直不关'的机制性根因."
- t-muo92xms-s28t | gate/build-phase-diagnostic-standard | "裁定 build 期诊断（swiftc -o 的 will-never-be-executed）是否属验收口径 —— 02-translator-implementation-standard:78/:80 只点名类型检查器" | todo, 0/3 evidence, unclaimed. Created 2026-09-30T15:18:41.870Z (immediately after the W1 row was confirmed done at 15:16-15:17).
- P09-named sub-work rows (none owns the P09 gate itself): t-mun89ugb-0dhf (prep/option-c-plan-cwd-fix, doing, 3/3, ready for sign-off), t-mun7x2g3-m4zs (prep/p09-gen-smoke, doing, 0/3), t-mun75tk1-h36w (prep/p09-fixture-parity, doing, 3/3), t-mun79z8m-n18z (prep/p09-loader-identity-assert, doing, 3/3), t-mun5c5o4-5ei6 (docs/p09-runbook-residual-fix, doing, 3/3), t-mun0d1bn-klvo (audit/e1c65975-driver-provenance, P09 B2, doing, 0/4), t-mun0d7xm-mfwb (audit/swift-systempackage-provenance, P09 B3, doing, 0/4), t-mumy6e28-80nx (audit/e1c65975-driver-config-compat, doing, 0/3).
- No row is titled or described as owning P10 or P12.

## Open rows — full transcription

Re-queried with `wb_board milestone=m-mulwvr32-3jht status=todo` and `status=doing` at
2026-09-30 11:3x ET; the returned snapshot `updatedAt` is identical (2026-09-30T15:18:41.870Z),
i.e. the board state has not moved. Note: the `openRows: 75` field is the board-wide open-row
count across all seven milestones; within this milestone the open rows are 21 todo + 26 doing
= 47 (plus the 33 done and 1 cancelled rows above).

### todo (21)

| handle | branch | title | sop | updatedAt |
|---|---|---|---|---|
| t-muo92xms-s28t | gate/build-phase-diagnostic-standard | 裁定 build 期诊断（swiftc -o 的 will-never-be-executed）是否属验收口径 —— 02-translator-implementation-standard:78/:80 只点名类型检查器 | 0/3 | 2026-09-30T15:18:41.870Z |
| t-munq08t2-rgxp | gate/p08-swift-readonly-boundary | P08：接受一个冻结的 Swift 只读数组边界实现候选（含 11 家族矩阵与两份独立评审） | 0/3 | 2026-09-30T06:24:43.682Z |
| t-munibdo3-jwqi | fix/rust-module-keyed-read-sites | 系统性清理模块键读点（PIT-297）：xs-crossmod 反例未修，33 读点仅覆盖 3 | 0/3 | 2026-09-30T03:22:33.619Z |
| t-munjfayf-iyh2 | fix/rust-string-expectation-family | 统一修正 host-String 陈旧期望家族（PIT-304：10 文件/约 57 行/9 兄弟仍破） | 0/3 | 2026-09-30T03:20:28.995Z |
| t-mun9hxa8-fsmg | fix/integrity-checker-byte-offset | 修密封校验的字节级盲区（PIT-251） | 3/3 | 2026-09-30T02:58:47.776Z |
| t-munie9lo-izy8 | fix/roots-guard-defeat-classes | 修 roots-guard 硬化版残留的 6 类新击败（PIT-296：理由仅形状校验、行格式、--macro 未解析等） | 0/3 | 2026-09-30T02:51:40.970Z |
| t-mune0a1j-vmt1 | fix/rust-payload-enum-key-collision | 修 Rust payloadEnumNames 同模块多异常类的键冲突（PIT-281） | 0/3 | 2026-09-30T02:49:32.185Z |
| t-munhr03l-o0hb | chore/dedupe-hxml-roots | 清理 6 个受护 hxml 中 45 条重复根（仓库卫生，TCN-124） | 0/3 | 2026-09-30T02:33:35.565Z |
| t-munga5l9-alq1 | fix/test-timeout-budget | 修正需 spawn 编译器的测试用例的 5s 超时预算（Stage 4 的 24 条 timeout 类） | 0/3 | 2026-09-30T02:28:28.439Z |
| t-mungw3ci-0i43 | audit/fallibility-downgrade-from-pit248 | 判定 PIT-248 引入的可失败性降级（Result+? → UString+unwrap()）是局部现象还是普遍回归 | 0/3 | 2026-09-30T02:10:52.611Z |
| t-munejtq3-mj9x | chore/archive-xs-fixture-family | 归档 xs-* 回归夹具族使其可从仓库复现（PIT-285） | 0/3 | 2026-09-30T01:04:01.865Z |
| t-munebyud-bxbr | fix/rust-growth-variant-lookup-parity | 对齐 Rust growth 变体的登记与查找身份（登记用类 payload 枚举、查找用函数 Result 枚举） | 0/3 | 2026-09-30T00:57:55.250Z |
| t-mun75az7-fpq4 | chore/option-c-attempt-prune | 清理冻结运行器累积的 attempt/external 运行产物 | 0/3 | 2026-09-29T21:36:47.069Z |
| t-mum0frlg-8ls1 | (none) | 观察 Swift 默认参数的字符串长度单位 | 0/3 | 2026-09-29T03:06:58.996Z |
| t-mum0wts5-jh3m | (none) | 观察默认参数中可抛调用的函数失败域 | 0/3 | 2026-09-29T03:05:06.453Z |
| t-mum0usfn-wwg8 | (none) | 验证可变界限计数循环的求值次数 | 0/3 | 2026-09-29T03:04:48.906Z |
| t-mum29cli-9c9w | (none) | 验证五目标零警告门禁的真实覆盖 | 0/3 | 2026-09-29T02:32:11.526Z |
| t-mum17vl5-9rty | (none) | 观察容器别名跨可空字段与调用边界 | 0/3 | 2026-09-29T02:03:03.209Z |
| t-mum0xvuq-q7tw | (none) | 绑定证据运行与实际装载的编译器字节 | 0/3 | 2026-09-29T01:55:16.994Z |
| t-mum0mp8l-m0a6 | (none) | 验证消费者入口缺 resident 根时的五目标闭包 | 0/3 | 2026-09-29T01:46:35.205Z |
| t-mum04le8-6gsm | (none) | 验证 Swift 生成包清单的宿主依赖 | 0/3 | 2026-09-29T01:32:30.416Z |

### doing (26)

| handle | branch | title | sop | updatedAt |
|---|---|---|---|---|
| t-mung7xtk-36rt | fix/value-type-test-expectation | 判定并修 value-type 测试期望与生成器输出的不一致（pub String vs pub UString） | 3/3 | 2026-09-30T03:08:20.870Z |
| t-munecdiz-qd7n | fix/roots-guard-hardening | 收紧 roots-guard：三处可执行击败（一词 reason 豁免真实回归、单向比较、陈旧豁免） | 3/3 | 2026-09-30T02:46:11.491Z |
| t-munbb7z3-39ck | fix/f32-hxml-roots-sync | 同步 f32 组 hxml 测试根并加清单一致性护栏 | 3/3 | 2026-09-30T00:31:36.619Z |
| t-mun9rz8k-rkir | swift-arrfix | 修 Swift 生成器把 TiqianArray 再包一层（PIT-255） | 3/3 | 2026-09-30T00:15:56.730Z |
| t-munauh55-9tue | investigate/f32-cross-target-divergence | 调查 f32 目标组的跨目标一致性 divergence | 3/3 | 2026-09-29T23:32:46.861Z |
| t-mum1y9jv-74zm | audit/dc-fs-missing-path | 观察 Fs 缺失路径的判定与异常身份 | 0/3 | 2026-09-29T22:23:01.836Z |
| t-mun89ugb-0dhf | prep/option-c-plan-cwd-fix | 修 option-c.plan 的 cd "$1" 接线缺陷（P09 第一道门） | 3/3 | 2026-09-29T22:16:14.339Z |
| t-mun75tk1-h36w | prep/p09-fixture-parity | 补齐 P09 敏感夹具并修正夹具路径假设 | 3/3 | 2026-09-29T22:15:06.654Z |
| t-mun7x2g3-m4zs | prep/p09-gen-smoke | P09 链 A driver 冒烟（协调态输入） | 0/3 | 2026-09-29T21:58:33.582Z |
| t-mun5c5o4-5ei6 | docs/p09-runbook-residual-fix | 修 p09 runbook Residual 段的 roots/--output 方向反置 | 3/3 | 2026-09-29T21:57:25.207Z |
| t-mun79z8m-n18z | prep/p09-loader-identity-assert | 为 P09 建立装载身份断言（.dev 盲区） | 3/3 | 2026-09-29T21:48:04.893Z |
| t-mum1qvjl-3bss | audit/dc-char-code-at | 观察字符串边界与非空 charCodeAt 的源域 | 3/3 | 2026-09-29T21:30:05.183Z |
| t-mun6nc2b-i7y2 | audit/dc-promoted-eval-runtime | promoted 语句位置 switch 的运行期单次求值证据 | 3/3 | 2026-09-29T21:23:02.477Z |
| t-mun5d97u-c4md | fix/rust-try-tail-exception-variant | 修 Rust 目标 TryTailExceptionFault 变体未发射导致 E0599 | 2/3 | 2026-09-29T21:13:27.464Z |
| t-mun3p3km-rbvc | fix/comparison-same-type-parameter-key | 修 Builder.sameTypeParameter 的 Ref 指针比较导致重复嵌套节点 | 1/3 | 2026-09-29T20:18:03.756Z |
| t-mum2ad8j-wgf4 | audit/dc-try-unreachable-tail | 验证 try 分支必抛前缀的不可达尾部 | 0/3 | 2026-09-29T20:07:22.767Z |
| t-mulzvzaf-azip | audit/dc-null-guard-fallthrough | 观察 Dart 空值守卫落空后的局部事实 | 0/3 | 2026-09-29T19:19:37.386Z |
| t-mum02duf-fpj2 | fix/stage-producer-success | 区分阶段存在与生产者成功 | 0/3 | 2026-09-29T18:55:13.593Z |
| t-mun0d7xm-mfwb | audit/swift-systempackage-provenance | 确定 Swift libSystemPackage 固定产物与工具链身份（P09 B3） | 0/4 | 2026-09-29T18:30:03.611Z |
| t-mun0d1bn-klvo | audit/e1c65975-driver-provenance | 绑定 e1c65975 driver provenance（P09 B2） | 0/4 | 2026-09-29T18:30:03.583Z |
| t-mun0colg-y4qu | fix/runner-identity-and-provenance | 整合 runner 身份与编译器 provenance 为单一补丁 | 0/5 | 2026-09-29T18:29:25.844Z |
| t-mulyrvsc-96b1 | fix/rust-generic-dataclass-evidence | 修复 Rust 泛型 dataClass 构造渲染 | 4/5 | 2026-09-29T18:29:25.824Z |
| t-mumx4s8p-7y5n | fix/a3-swift-probe-evidence | 修复 A3 Swift 泛型探针证据 | 0/5 | 2026-09-29T18:27:19.375Z |
| t-mumx5bo4-na2g | fix/tsc-runner-identity | 绑定 tsc runner 可执行身份 | 2/3 | 2026-09-29T17:51:41.816Z |
| t-mumy6e28-80nx | audit/e1c65975-driver-config-compat | 验证 e1c65975 driver 对固定项目配置的兼容性 | 0/3 | 2026-09-29T17:26:01.622Z |
| t-mumx5iil-guqs | fix/runner-compiler-provenance | 绑定 runner 实际编译器字节 | 0/3 | 2026-09-29T16:57:32.695Z |

Note: the cancelled row t-mumy6q78-vikf carries the same title as the doing row
t-mum02duf-fpj2 (fix/stage-producer-success) — the original row was cancelled 2026-09-29
and the work re-opened as the fix row.
