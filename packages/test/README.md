# packages/test/

Boring 的测试与 CI 工具层。八块的职责边界（一句一块）：

- **bin/** — 测试入口 CLI：驱动一次测试运行（跨目标调度、进程编排），不做断言。
  入口从自身路径解析仓库根，可在 `nix develop` 内独立运行，不依赖仓库根 package.json：
  `nix develop -c bun packages/test/bin/driver-probe-runner.ts`
- **harness/** — 共享运行时库：记录并校验运行的客观事实（runner-record、stage-check），
  不判定通过与否。
- **fixtures/** — 确定性被测环境：提供 fixture 目录与 stub 工具链（假 haxe/tsc/bun/postgen），
  不含执行逻辑。
- **assertions/** — 断言/对比入口：把 harness 记录与期望对比产出 verdict
  （consistency/ 下是 Compare 的 CLI 壳；Compare 实现留在 packages/driver）。
- **probes/** — 行为探针工程：单点行为观测、产出 sidecar 证据（本地诊断工具归此）。
- **ci/** — CI 调用面：CI 与本地共用的唯一入口层（package.json 的 check:invariants /
  report:coverage / gen:vector 指到这里）。
- **build-stubs/** — 编译机制 stub：为测试编译提供 entry/宏辅助（GenerateMain.hx），
  与行为测试分离。

## 迁移映射

| 旧路径 | 新路径 |
| --- | --- |
| tests/driver/cross-target.ts（执行部分） | packages/test/bin/driver-probe-runner.ts |
| tests/driver/cli-cross-target.ts（fixture+stub 部分） | packages/test/fixtures/cli-driver-fixture.ts |
| tests/driver/cli-cross-target.ts（命令执行部分） | packages/test/bin/cli-command.ts |
| tests/support/stage-check.sh | packages/test/harness/stage-check.sh |
| tools/runner-record/runner-record.sh | packages/test/harness/runner-record.sh |
| tests/haxe/GenerateMain.hx | packages/test/build-stubs/GenerateMain.hx |
| tools/test-consistency/* | packages/test/assertions/consistency/* |
| tests/degradation-probe/ | packages/test/probes/degradation-probe/ |
| tools/trace-emit-origin.mjs | packages/test/probes/trace-emit-origin.mjs |
| tools/emit-invariant-check.ts | packages/test/ci/emit-invariant-check.ts |
| tools/gen-vector.ts | packages/test/ci/gen-vector.ts |
| tools/unit-coverage-report.ts | packages/test/ci/unit-coverage-report.ts |

## 路径稳定性链接（path-stable links）

harness/ 两个共享库在旧路径保留**相对 symlink**：

- `tests/support/stage-check.sh` → `../../packages/test/harness/stage-check.sh`
- `tools/runner-record/runner-record.sh` → `../../packages/test/harness/runner-record.sh`

原因：十余个探针 runner（alias-transfer-boundary、charcodeat、comparison-plan、
source-container-policy、enum-comparison、view-lifetime、flow/replay 等）按**字面路径**
source / [ -f ] / sha256sum / 归档这两个文件，部分把路径写进 identity 清单与
stages.json 身份声明。symlink 对 source、存在性检查、sha256（读目标内容）、cp
（跟随）全部透明，证据链不受影响； `packages/test/harness/` 是唯一编辑点。

注意：`find -type f` 不匹配 symlink——view-lifetime 的 input_manifest 已改为
`find -L` 以便共享库仍进输入清单。新增按目录扫描 tests/support 或 tools/runner-record
的 \`find -type f\` 时同样需要 \`-L\` 或显式列出链接路径。

## 未迁移（刻意保留）与原因

- **tests/timeout-probe/** — hxml 的 `-cp tests/timeout-probe` 与
  `--macro Intercept.run(['samples', 'tests/timeout-probe'])` 把源码路径编进了宏行为；
  Cargo.toml 注释与 docs/specs/features/19-testing.md 按路径引用。迁移=改宏语义。
- **tests/bundle-child-evidence/** — flow/replay 的 stages.json 身份 glob
  （`tests/bundle-child-evidence/**`）、sha256 清单、comparison-plan 输入清单按字面路径 pin。
- **tests/haxe/ 各探针目录** — 每个 run.sh 是哈希自记录的证据管线；迁移路径即改证据语义。
- **tools/gate-proof/verify-commit.ts** — gate:verify 入口，上一轮刚恢复并自检；
  保持原位，`bun run gate:verify` 不变。

以上三项 probe 目录的最终归属（probes/ 约定位置）由 Design-SharedModuleTraceSpec
依据本骨架定型后统一处理。
