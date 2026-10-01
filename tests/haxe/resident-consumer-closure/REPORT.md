# Resident closure with no `runtime.*` root (t-mum0mp8l-m0a6)

## Question

A consumer that reaches `StringTools`, `std.UStringRT`, `std.Graphemes`,
`std.SortedMap`/`std.SortedSet` **only through the std extern face** compiles
per target. Its entry lists no `runtime.*` root. Is the runtime declaration
closure — the resident modules those externs front — still pulled in, or does
the generated tree reference runtime symbols that were never emitted?

Everything below is **measured** in this worktree (commands in
`tests/haxe/resident-consumer-closure/run.sh`, raw logs and rc tables under
`out/resident-consumer-closure/logs/`), except the short code citations in
§4, which are marked `cited`.

## ① Two fixed consumer inputs

Same `Consumer.hx` in both; the only delta is the hxml root list.

- **(a) no `runtime.*` root** — `gen/<target>-a.hxml` roots only `Consumer`.
- **(b) explicit `runtime.*` roots** — `gen/<target>-b.hxml` roots `Consumer`
  plus `runtime.UString`, `runtime.GraphemeWalk`, `runtime.Graphemes`,
  `runtime.SortedTable`, `runtime.TestCore`, the same five the repo's own
  `examples/*.hxml` list.

Fixed inputs and hashes (`logs/input-hashes.txt`):

    67242e8b…  Consumer.hx            (shared by a and b)
    d9801d76…  gen/rust-a.hxml        2122be6a…  gen/rust-b.hxml
    e3256fd3…  gen/swift-a.hxml       5e7decc7…  gen/swift-b.hxml
    5578f183…  gen/kotlin-a.hxml      98b0778c…  gen/kotlin-b.hxml
    ae7094ff…  gen/dart-a.hxml        5ae033fb…  gen/dart-b.hxml
    2968ffa2…  gen/ts-a.hxml          3516fc71…  gen/ts-b.hxml

Combined sha256 over the eleven files:
`acc7eeeafe88439a5093b1f055eadfa7a8ab1e728042b3683ac1a49e8bc8abde`.
Full hex hashes are in `logs/input-hashes.txt`; the runner recomputes them
each run.

## ② Five targets, three stages, direct-read rc

Stage 1 — Haxe generation (`haxe gen/<t>-<v>.hxml > log 2>&1; rc=$?`):

| target | a gen rc | b gen rc |
|--------|---------|---------|
| ts     | 0 | 0 |
| rust   | 0 | 0 |
| swift  | 0 | 0 |
| kotlin | 0 | 0 |
| dart   | 0 | 0 |

Stage 2 — resident runtime file manifest of the generated tree
(`logs/manifests.txt`):

| target | variant a (no runtime root) | variant b |
|--------|------------------------------|-----------|
| ts | `runtime.ts`, byte-identical to b's; contains `StringTools`, `UString`, `GraphemeWalk`, `Graphemes`, `SortedTable`, `SortedMapTable(+Builder)`, `SortedSetTable(+Builder)` | same |
| rust | `runtime/{mod,string_tools,u_string}.rs` — **`graphemes.rs`, `grapheme_walk.rs`, `sorted_table.rs` missing**, while `mod.rs` still declares `pub mod grapheme_walk; pub mod graphemes; pub mod sorted_table;` | full set + `test.rs`, `test_core.rs` |
| swift | `Runtime.swift` (535 lines) = hand-written prelude + `UString` prelude + `StringTools` resident — **no `Graphemes`/`GraphemeWalk`/`SortedTable`/`SortedMapTable`/`SortedSetTable`** | `Runtime.swift` (1809 lines) with all residents + `Test.swift` |
| kotlin | `runtime/{StringTools,UString}.kt` + `runtime/test/{Test,TestCore}.kt` — **`Graphemes.kt`, `GraphemeWalk.kt`, `SortedTable.kt` missing**; `UString.kt` is the hand-written shim, byte-identical to b's | adds the three missing residents |
| dart | `runtime.dart` (226 lines) = `StringTools` + `UString` residents — **no `Graphemes`/`GraphemeWalk`/`SortedTable`** | `runtime.dart` (1493 lines) with all |

Stage 3 — native compile of the whole generated tree (repo-convention
commands; rc direct-read, `logs/native-rc.tsv`):

| target | command | a rc | b rc |
|--------|---------|------|------|
| ts | `tsc --noEmit -p tsconfig-<v>.json` | **0** | 0 |
| rust | `cargo check` in the tree | **101** | 0 |
| swift | `swiftc <tree>/*.swift native-main.swift -o bin` | **1** | 0 |
| kotlin | `kotlinc <tree>/*.kt -d jar` | **1** | **1** (b fails too — see §4) |
| kotlin isolation | same, minus `runtime/test/*` | **1** | **0** |
| dart | `dart analyze --no-fatal-warnings <tree>` | **3** | 0 |

Raw first diagnostics of the failing (a) compiles:

- rust-a: `error[E0583]: file not found for module `grapheme_walk`` (then
  `graphemes`, `sorted_table`; 4 `^error` lines total).
- swift-a: `Consumer.swift:15:16: error: cannot find 'Graphemes' in scope`
  (14 errors: 6× `Graphemes`, 2× each `SortedMapTable`, `SortedMapTableBuilder`,
  `SortedSetTable`, `SortedSetTableBuilder`).
- kotlin-a: `Consumer.kt:1:23: error: unresolved reference 'Graphemes'.`
  (12 errors: the Graphemes/SortedTable closure errors plus 2 `FPHelper`
  errors from `runtime/test/Test.kt`, see §4).
- dart-a: `lib/consumer.dart:14:18 - The name 'Graphemes' is being referenced
  through the prefix 'runtime', but it isn't defined in any of the libraries
  imported using that prefix. - undefined_prefixed_name` (7 errors, 8 issues).

No stage was skipped on any target: all five targets reached native
compilation in both variants. The one command-shape note: the Dart gate is
`dart analyze --no-fatal-warnings`, the repo's own `test:dart` convention;
with it dart-b is rc=0 (one tolerated warning) and dart-a is rc=3 on errors.

**Verdict of the closure under test:** holds on **ts**; breaks on
**rust, swift, kotlin, dart** — the generated consumer references resident
symbols whose backing modules were never typed, so the files/declarations
are absent.

## ③ Mutation negative control

One resident file deleted from a copy of the generated tree, then the same
native command re-run (`logs/mut-rc.tsv`). Every row fails, so the compile
stage is not vacuously green:

| row | deleted file | rc | first diagnostic |
|-----|--------------|----|------------------|
| ts-a-mut | `runtime.ts` | 2 | `error TS2307: Cannot find module './runtime.ts'` |
| rust-a-mut | `runtime/u_string.rs` | 101 | E0583 `u_string` (5 error lines; a already failed, degenerate) |
| rust-b-mut | `runtime/graphemes.rs` | 101 | `error[E0583]: file not found for module `graphemes`` |
| swift-a-mut | `Runtime.swift` | 1 | (a already failed, degenerate) |
| swift-b-mut | `Runtime.swift` | 1 | `Test.swift:176:30: error: cannot find type 'BoringException' in scope` (16 errors) |
| kotlin-a-mut | `runtime/UString.kt` | 1 | unresolved `UString` import (a already failed, degenerate) |
| kotlin-b-notest-mut | `runtime/Graphemes.kt` | 1 | `error: unresolved reference 'Graphemes'.` |
| dart-a-mut | `runtime.dart` | 3 | (a already failed, degenerate) |
| dart-b-mut | `runtime.dart` | 3 | `Target of URI doesn't exist: '../runtime.dart'. - uri_does_not_exist` |

The informative rows (a passing tree made to fail by one deleted resident
file) are ts-a-mut, rust-b-mut, swift-b-mut, kotlin-b-notest-mut, dart-b-mut.
The literal (a)-tree mutations are recorded too; on rust/swift/kotlin/dart
they are degenerate because (a) already fails, which is itself the finding.

## ④ Three failure classes, separated

**Forced-typing gap — the cause on rust, swift, kotlin, dart.** Measured:
the only input difference between a and b is the root list, and the file
delta is exactly the residents no target force-types. On rust the emission
side demonstrably wanted the files — `runtime/mod.rs` in (a) declares
`pub mod graphemes;` etc. (mod entries are pushed on extern usage,
`rustcompiler/Compiler.hx:416-428`, cited) while the `.rs` files do not
exist: the gate passed, typing never reached the module. Roots are the only
thing that types an un-forced resident (the externs are pure declarations;
typing `std.Graphemes` types no `runtime.*` module). Cited, per target
`use()`: ts force-types **all** residents (`tscompiler/Compiler.hx:276-281`,
comment states this exact scenario); rust only `runtime.StringTools` +
`runtime.UString` (`:99-102`); swift only `runtime.StringTools` (`:76-78`);
kotlin only `runtime.TestCore` + `runtime.StringTools` (`:61-68`); dart
`runtime.StringTools` + `runtime.UString` + `runtime.TestCore` (`:103-107`).
That predicts exactly the measured (a) manifests: rust-a keeps precisely the
two forced files; swift-a keeps StringTools and covers the UString face with
the hand-written `SwiftRuntime.USTRING_PRELUDE` (`swiftcompiler/Compiler.hx:351-356`,
cited) — not the resident; kotlin-a's `UString.kt` is the hand-written
`KotlinRuntime.USTRING_SOURCE` shim (`kotlincompiler/Compiler.hx:293`, cited),
byte-identical in a and b; dart-a keeps the two forced residents.

**Emission gate — a distinct, measured defect on kotlin (b).** kotlin-b's
full tree fails `kotlinc` rc=1 with only `runtime/test/Test.kt:5:23: error:
unresolved reference 'FPHelper'` — the test host references `FPHelper`
unconditionally, but `FPHelper.kt` emission gates on business float usage
this consumer never triggers. All four closure residents ARE present in
kotlin-b, and removing only `runtime/test/*` from the same tree compiles
rc=0 (`kotlin-b-notest`). So kotlin-b's failure is an emission-gate defect
in the test host, not the closure gap, and not a toolchain failure.

**Platform toolchain — ruled out everywhere.** All five toolchains pass
their own positive controls: ts-b/rust-b/swift-b/dart-b native compiles
rc=0 through the same commands, and kotlin gets a standalone probe
(`kotlinc` on a hello-world, rc=0) plus the kotlin-b-notest rc=0 row. No
failure in this measurement is a toolchain failure.

## ⑤ Provenance

- Measured in this worktree (`audit/consumer-missing-resident`, base
  `1ae6de72`): every rc, manifest, diagnostic, and diff quoted above, via
  `tests/haxe/resident-consumer-closure/run.sh`; artifacts under
  `out/resident-consumer-closure/` (gitignored, regenerated by the runner).
- Cited, not measured: the `use()` force-typing lists, the
  `RuntimeResidents.MODULES`/`externsOf` tables
  (`packages/compiler/RuntimeResidents.hx:22-61`), the mod-entry push site,
  the swift UString prelude, and the kotlin UString shim — file:line above.
- Committed (load-bearing): `Consumer.hx`, `gen/*.hxml` (10), `run.sh`,
  `tsconfig-{a,b}.json`, `native-main.swift`, this report. Generated trees
  and logs stay untracked under `out/` by `.gitignore`.
- `wb_task_update` is not reachable from this worktree's shell
  (`command not found`); the five evidence lines below are ready to submit
  verbatim. Task stays in the started state per instructions.

## Evidence lines (one per criterion, in order)

    wb_task_update id=t-mum0mp8l-m0a6 evidence="① 两组输入固定：Consumer.hx(67242e8b…)+gen/<t>-a/b.hxml 十一份 sha256 汇总 acc7eeea…（logs/input-hashes.txt）；a 仅根 Consumer，b 加 examples 同款五个 runtime.* 根。"

    wb_task_update id=t-mum0mp8l-m0a6 evidence="② 五目标三阶段直读 rc：生成 10/10=0；清单——ts-a runtime.ts 与 b 逐字节相同(全 resident)，rust-a 缺 graphemes/grapheme_walk/sorted_table.rs 而 mod.rs 仍声明它们，swift-a Runtime.swift(535行)无 Graphemes/SortedTable，kotlin-a 缺 Graphemes/GraphemeWalk/SortedTable.kt，dart-a runtime.dart(226行)仅 StringTools+UString；原生编译 ts a=0/b=0，rust 101/0，swift 1/0，kotlin 1/1(隔离 test 后 1/0)，dart 3/0——闭包仅 ts 成立，四目标断。"

    wb_task_update id=t-mum0mp8l-m0a6 evidence="③ 变异负控全失败：ts-a-mut 删 runtime.ts→rc2 TS2307；rust-b-mut 删 graphemes.rs→rc101 E0583；swift-b-mut 删 Runtime.swift→rc1；kotlin-b-notest-mut 删 Graphemes.kt→rc1 unresolved；dart-b-mut 删 runtime.dart→rc3 uri_does_not_exist；(a)树变异另记四行皆失败(退化，a 本已败)。"

    wb_task_update id=t-mum0mp8l-m0a6 evidence="④ 三因独立区分：rust/swift/kotlin/dart 为 forced-typing 缺口(唯一输入差=根表，文件差=未被 use() 强制的 resident；rust-a mod.rs 声明模块而文件缺=门已过、typing 未达)；kotlin-b 全树败于 test host Test.kt 引用 FPHelper 而 FPHelper.kt 门控于业务浮点使用——emission gate 缺陷，非闭包(去 test 后 rc=0)；工具链全排除(ts/rust/swift/dart 的 b 编译 rc=0，kotlinc 探针 rc=0)。"

    wb_task_update id=t-mum0mp8l-m0a6 evidence="⑤ 实测=本 worktree run.sh 全部 rc/清单/诊断(out/resident-consumer-closure/logs/)；引用=各目标 use() 强制表与 RuntimeResidents(已标 cited)；承重件(Consumer.hx、10 hxml、run.sh、tsconfig、native-main.swift、REPORT.md)已提交，git status --porcelain 为空；wb_task_update 本 shell 不可达(command not found)，证据行已备。"
