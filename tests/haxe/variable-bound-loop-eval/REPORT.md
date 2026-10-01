# Variable-bound counted-while audit

## Scope and source admission

The two measured inputs are hand-written `while` loops, not typer-promoted
`range-for`: `localBound` reads a local bound expression on every condition
check and performs a local reassignment; `growingLength` reads `values.length`
and grows the array once during the loop. `doubleControl` has two source
bound reads and is the instrument sensitivity control.

Source admission for the five cross targets: the committed `vble/Probe.hx`
is compiled unmodified for every target (byte-identical to the oracle
input; each run digests the full input tree before and after and records
`input-unchanged.txt`). Its `main()` calls `trace(...)`, and on the cross
targets the store `haxe.Log` does not typecheck against the compiler's
per-target std-shadow: expanding the trace call types `PosInfos` in
`haxe.macro.Expr`, which drags the `haxe.macro.Context` class into the typed
set; that class references the eval-target `Sys`/`FileSystem` chain, which
typechecks the store `haxe.io.Input`/`haxe.io.Output` against the shadowed
`haxe.io.Bytes` and fails on all five targets with
`haxe.io.Bytes has no field getData`. This was isolated by bisection: an
empty `main` body generates (rc=0) and `trace(1)` inside `main` generates
(rc=1) under the same hxml; the full `examples/*.hxml` trees only parse —
never typecheck — the store `haxe.io.Input`, which is why they do not hit it.

The fixture therefore carries a fixture-local shadow, `shadow/haxe/Log.hx`
(a no-op `trace`), which each `gen/<t>.hxml` puts on the generation
classpath. The shadow changes no counted expression — `trace` occurs only in
`main()`, while the counters increment only inside `readLocal`/`readLength` —
and the per-target native driver is the only printer of the observation line,
which carries the same payload the oracle `trace` prints.

## Oracle (measured)

Command (cwd: repository root; exit status read directly):

```
/nix/store/98pb92k7pi6g5cifmg872jn18kghaxw5-haxe-4.3.7/bin/haxe \
  tests/haxe/variable-bound-loop-eval/oracle.hxml > /tmp/vble-audit/gen.out 2>&1; rc=$?; echo "haxe rc=$rc"
/nix/store/vd788darzi6n1k2zrj5x3kqgg03kbz93-nodejs-official-22.23.3/bin/node \
  /tmp/vble-oracle.js > /tmp/vble-audit/oracle.out 2>&1; rc=$?; echo "node rc=$rc"
```

Raw output:

```
haxe rc=0
node rc=0
tests/haxe/variable-bound-loop-eval/vble/Probe.hx:53: local=4 length=3 control=4
```

Thus the Haxe 4.3.7 oracle empirically establishes **逐迭代求值** for both
conditions: the local-bound expression is read 4 times (three true checks and
the terminating false check), while the growing-length expression is read 3
times (the growth changes the second check's bound). The authored source hash
for this run is `508851eb833b88441fe9cdbc2e78ef85c4352a8903859c090dcc0769cdc06843`.

## Five-target reachability and measured readings

> **Superseded.** The measured table in this section records the pre-fix run
> `20261001T022115Z`, in which `rust-lib` and `swift-lib` reached their
> producer stages but not their run stages. Those two blocks were resolved by
> commit `1e0d8169` ("fix(rust,swift): unblock variable-bound-loop-eval native
> compile"); the post-fix run `20261001T211624Z`, recorded in the next
> section, reaches rc=0 on all five targets with `local=4 length=3 control=4`.
> This section is retained as the honest record of the pre-fix attempt; it is
> not the run the sign-off rests on.

`haxelib` is not missing from the environment: `haxelib` 4.1.1 sits in the
same store bin directory already used for `haxe`
(`/nix/store/98pb92k7pi6g5cifmg872jn18kghaxw5-haxe-4.3.7/bin/haxelib`), so the
earlier `haxelib not found` not-reached row was falsified. The committed
`run.sh` records toolchain identity, haxelib resolution, input digests, the
oracle re-run, and the per-target stage chain with raw argv, cwd, stdout,
stderr, and exit code for every stage. The recorded run is
`out/variable-bound-loop-eval/runs/20261001T022115Z/` (evidence root inside
the worktree; `out/` is gitignored).

Environment facts recorded by the run's identity stages: haxe 4.3.7 and
haxelib 4.1.1 (`.../haxe-4.3.7/bin/`), rustc 1.98.0 (`.../rust-default-1.98.0/bin/`),
node 22.23.3 (`.../nodejs-official-22.23.3/bin/`), dart 3.13.3
(`.../dart-3.13.3/bin/`), kotlinc 2.4.10 on JRE 21.0.12
(`.../kotlin-2.4.10/bin/`, `/run/current-system/sw/bin/java`), tsc 5.9.3
(`tq-workspace/boring/node_modules/.bin/tsc`, sha256
`8d5fa5bd883fec0979fc2004f1fe1d99aef40570155d550eadc0b03b55513bf0`), swiftc
6.2.4 via the pinned wrapper
`p09-chainA-work/swift-shim-bin/swiftc` (the store holds a single Swift
toolchain, `swift-toolchain-6.2.4-al2`, verified by `ls -d /nix/store/*swift*`).
`haxelib path` resolves `-lib reflaxe` to
`/nix/store/ch901mw058pjvr3nyxgwxps31vc46wmm-source/src/` (dev marker
`.haxelib/reflaxe/.dev`) and `-lib boring` to
`/home/losses/Development/tq-workspace/boring-wt-growthkeyfix/packages/compiler/`
(dev marker `.haxelib/boring/.dev`), plus the `format` package from the shared
`.haxelib`; all input roots are digested before and after the run and were
unchanged.

Measured readings (all raw stdout of the run stages; the oracle payload is
`local=4 length=3 control=4`):

```
target  gen  native compile        run        reading
ts      0    tsc --noEmit 0;       node 0     local=4 length=3 control=4  (matches oracle)
        -    tsc emit 0
kotlin  0    kotlinc 0 (jar)       java 0     local=4 length=3 control=4  (matches oracle)
dart    0    dart run compiles     dart run   local=4 length=3 control=4  (matches oracle)
        -    in-process            0
rust    0    rustc lib 1 (5       not-reached (producer=rust-lib)
        -    errors, see below)
swift   0    swiftc lib 1 (1      not-reached (producer=swift-lib)
        -    error, see below)
```

Three of the five targets — ts, kotlin, dart — completed generation, native
compilation, and execution, and each measured `local=4 length=3 control=4`,
the same per-iteration triple the oracle establishes. The generated code of
all five targets keeps the bound read inside the `while` condition
(`while (i < Probe.readLocal(bound))` in the ts/kotlin/swift trees,
`while (i < _readLocal(bound))` in the dart tree, the equivalent
`i32::from_ne_bytes(... < ... probe_read_local(bound) ...)` condition in the
rust tree), i.e. no target emits a hoisted once-read bound; this static shape
is consistent with, but not a substitute for, the runtime readings above.

The two blocked targets fail at native compilation with verified producer
errors (toolchains are present and working; these are lowering findings,
not missing-environment rows):

- **rust** (`rust-lib`, rc=1, rustc 1.98.0): the frozen source's
  `localReads++`/`lengthReads++` post-increments on the static counters are
  emitted as `{ let __guard = PROBE_LOCAL_READS.lock()...; __guard.clone() } += 1;`
  — a block expression on the left of a compound assignment, which Rust does
  not accept. Raw errors: `error: expected expression, found `+=`` (twice),
  `error[E0067]: invalid left-hand side of assignment` (twice). Separately,
  `runtime/mod.rs` declares `pub mod sorted_table;` while `sorted_table.rs`
  is not emitted (`error[E0583]: file not found for module `sorted_table``):
  the emitter auto-generates a `compare_pos` function for the shadow's `Pos`
  struct that references `SortedTable::sorted_table_compare_strings`, so the
  module is declared but its file is never written. The sibling
  dc-promoted-eval fixture compiles its rust counter because it writes the
  assignment form `callCount = callCount + 1`; the frozen source's `++` form
  has never been exercised by a committed fixture.
- **swift** (`swift-lib`, rc=1, swiftc 6.2.4 via the pinned wrapper): the
  typer folds the frozen source's `bound = bound + 0;` to `bound = bound`,
  and the toolchain rejects self-assignment as a hard error. Raw error:
  `swift-gen/vble/Probe.swift:24:19: error: assigning a variable to itself`.
  The store holds only one Swift toolchain (`swift-toolchain-6.2.4-al2`), so
  no alternate compiler version is available to soften the diagnostic.

`run.sh` exits 0 for this run: target-level generation, compilation, and run
failures are recorded observations with their failed producer, and the
runner fails only on harness defects (oracle mismatch, input drift, missing
stage, or a run with no parseable observation).

## Post-fix run (20261001T211624Z): all five targets reach the run stage

A second run, `20261001T211624Z`, was produced after commit `1e0d8169`
("fix(rust,swift): unblock variable-bound-loop-eval native compile") landed.
Its evidence root is `out/variable-bound-loop-eval/runs/20261001T211624Z/`
(gitignored, like the pre-fix root). The runner records 23 stages and every
one exits 0 (`stages.tsv`): the identity and input-hash stages bookend the
oracle generation/run and, for each of ts/kotlin/rust/swift/dart, the
generation, native compile/build, and run stages.
`input-unchanged.txt` is present ("the authored input trees are unchanged by
the run"), and the oracle stage re-confirms
`tests/haxe/variable-bound-loop-eval/vble/Probe.hx:53: local=4 length=3 control=4`.

Measured readings, read from the run's `stages.tsv` and `observations.tsv`
(the oracle payload is `local=4 length=3 control=4`):

```
target  gen  native compile        run         reading
ts      0    tsc --noEmit 0;       node 0      local=4 length=3 control=4  (matches oracle)
        -    tsc emit 0
kotlin  0    kotlinc 0 (jar)       java 0      local=4 length=3 control=4  (matches oracle)
dart    0    dart run compiles     dart run 0  local=4 length=3 control=4  (matches oracle)
        -    in-process
rust    0    rustc lib 0;          harness-    local=4 length=3 control=4  (matches oracle)
        -    harness 0             bin 0
swift   0    swiftc lib 0;         runner 0    local=4 length=3 control=4  (matches oracle)
        -    harness 0
```

All five targets now reach their run stage with rc=0 and each prints the
observation `local=4 length=3 control=4`, matching the oracle. The two stages
that were `not-reached` in the pre-fix run are genuine compilations now:
`rust-lib` runs `rustc --edition=2024 --crate-type lib --crate-name vble`
(5 warnings, no errors) and `swift-lib` runs the pinned wrapper
`swiftc -emit-library -emit-module ... -o libVbleProbe.so` (one
"variable 'bound' was never mutated; consider 'let'" warning, no error).

The two not-reached rows were resolved by `1e0d8169`, which changed the
emitters (and the runner's pinned paths), not the frozen source:

- **rust** (`RustExpr.hx`): the `++`/`--` post-increments on the guard-static
  counters were emitted with `expr(subj)` on the left of the compound
  assignment, producing a block expression on the LHS that rustc rejects
  (`expected expression` / `E0067`). The fix renders the assignment target
  with `assignTarget(subj)` in both the statement and expression paths
  (`expr(subj)` still supplies the read value), so guard statics now emit
  `*STATIC.lock()... += 1`.
- **swift** (`SwiftExpr.hx`): the typer folds the frozen source's
  `bound = bound + 0;` to a plain-local self-assignment `bound = bound`,
  which swiftc rejects as a hard error ("assigning a variable to itself").
  The fix skips a `TBinop(OpAssign)` whose left and right are the same plain
  `TLocal` id as a no-op.
- **run.sh**: the pinned `TQ_ROOT` depth was adapted to the current worktree
  layout and the removed `boring-wt-growthkeyfix` input roots were dropped.

Independent re-execution: the report author re-executed the ts, kotlin, rust,
and swift run-stage products from these artifacts directly:
`node ts-js/driver.js`, `java -cp kotlin-build/probe.jar MainKt`,
`rust-gen/harness-bin`, and `swift-build/runner` (with
`LD_LIBRARY_PATH` set to the build directory) each print
`local=4 length=3 control=4` and exit 0. The dart target was not
independently re-executed — no `dart` toolchain is present in the author's
environment (`which dart` exits 1) — so the dart reading rests on the
recorded `dart-run` stage alone (status 0, stdout
`local=4 length=3 control=4`).

## Probe discrimination

The triple `(local, length, control) = (4, 3, 4)` is jointly discriminating:

- If the local bound were hoisted above the loop (evaluated once), `local`
  would read 1 instead of 4, and `control` would read 2 instead of 4 (one
  read per loop). No single lowering change keeps the measured triple.
- If the array growth were lost while the length stayed per-iteration,
  `length` would read 2 (checks see 1, then 1); if the length were hoisted,
  it would read 1. Either change is falsified by the measured 3.
- If the counter undercounted (for example a constant-one instrument),
  `control` — which contains two counted bound expressions — would read 2,
  not 4: the oracle's `control=4` is an independent positive count above 1
  and falsifies a constant-one counter without relying on the other two
  shapes.
- A cross-wired counter (local/length swapped) would print `(3, 4, 4)`; the
  control value would be unchanged, so the first two coordinates carry that
  failure mode.
- The oracle itself demonstrates sensitivity: the same source and the same
  counters produce 4 and 3 for the two different shapes, so the instrument
  resolves per-shape read counts.

The runner is an observation fixture, not a gate. The last statement of the
current `run.sh` is `printf 'evidence root %s\n' "$RUN"` followed by
`exit 0`; the only non-zero exit path is the `exit 1` reserved for harness
defects (oracle re-run mismatch, input-tree drift, a declared stage with no
row, or a run stage that exits 0 without a parseable bound-read triple).
Target-level failures never trip that path — this run demonstrates exactly
that (`rust-lib` and `swift-lib` both rc=1, runner rc=0). The pre-rework
`run.sh` ended in `printf 'evidence=%s\n' "$OUT"` with no explicit exit, i.e.
always 0. No variant of the runner therefore fails a build on a bad
reading; the readings' evidence is the run directory.

## Committed support

`vble/Probe.hx` and `oracle.hxml` (frozen), `gen/{ts,kotlin,rust,swift,dart}.hxml`,
`shadow/haxe/Log.hx`, `native/{driver.ts,Main.kt,harness.rs,main.swift,driver.dart}`,
`run.sh`, `README.md`, and this report are the reproducibility-bearing
fixture/driver and are committed with this audit. Generated trees and the
`out/` run evidence are not committed. No compiler code was changed.
