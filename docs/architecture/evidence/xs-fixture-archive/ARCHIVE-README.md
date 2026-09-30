# xs-* / xt-* regression fixture archive (PIT-285)

Verbatim archive of the Haxe→Rust regression fixture family used to judge the
rustcompiler fixes PIT-248 (fault-variant registration regression), PIT-281
(class-keyed payload map) and PIT-297 (module-keyed payload read sites).

## Why this archive exists

At the base revision `e1c6597514634fd347d392709793cc19bd96c9a2` the family is
**not tracked by git** (`git ls-files 'tests/haxe/xs-*'` → 0 files). The
fixtures existed only as untracked copies in a handful of seat worktrees
(`dc-warn/worktrees/*/tests/haxe/xs-*`, and, for the PIT-297 sub-family, on
branch `fix/rust-module-keyed-read-sites` as commit `b18b99df…`). Any signed
reading that depends on this family was therefore reproducible only from one
seat's worktree. This archive closes that: every byte of every fixture is
pinned by sha256, and `RESTORE.sh` puts them back onto a clean `e1c65975`
checkout with byte-level verification.

## Contents

| path | what |
|---|---|
| `xs-*/`, `xt-*/` | the fixture sources, verbatim: `<pkg>/<Probe>.hx` + driver `gen/rust.hxml` (+ `xs-scope/expected.txt`, `xs-crossmod/README.md`, `xs-xmod/otherpkg/*`) |
| `RESTORE.sha256` | 37-entry sha256 manifest, **relative paths from this directory** — verify with `sha256sum -c RESTORE.sha256` run **from this directory** |
| `FILES.sha256` | sha256 manifest of **every file in this archive** (manifest itself excluded), **absolute paths** — `sha256sum -c FILES.sha256` passes from **any cwd** |
| `RESTORE.sh` | restores the 37 fixture files into `TARGET/tests/haxe/…`, byte-verifies both sides; `--check` verifies without writing; `--any-rev` lifts the `e1c65975` HEAD guard. Safe to re-run; fails loudly (non-zero, file named) on any mismatch |
| `compiler-states/as-reviewed/` | the 4 rustcompiler `.hx` files of the PIT-248 "as-reviewed" (regressed) state, verbatim from `dc-warn/out/rust-regression-fix/src-postfix/` (hash-anchored there by its `FILES.sha256`) |
| `compiler-states/frozen-57ee4997/` | the 4 rustcompiler `.hx` files of the board-anchored "corrected/frozen" state (`Compiler.hx = 57ee4997…`), read-only copies of the shared coordination tree's working state at archive time |
| `drivers/run-matrix.sh` | the PIT-297 seat's driver, verbatim (per-fixture gen rc + cargo rc, fresh `CARGO_TARGET_DIR`, `Compiling generated` count); its `WT`/`OUT` constants point at that seat's tree — retarget for reuse |
| `drivers/run-three-state.sh` | generalized driver actually used for this row's re-measurement: pristine / as-reviewed / frozen states × fixtures, hash-anchored state swaps, plus the runner-collection probes |
| `EXPECTED-READINGS.md` | the three-state expected readings and expected stderr key lines per fixture, with provenance per value (historical vs re-measured) |
| `evidence/` | prior-attempt restore logs and `fixture-provenance.tsv` |
| `REPORT.md` | the row report (also at `dc-warn/out/xs-archive/REPORT.md`); raw re-measurement logs in `dc-warn/out/xs-archive/evidence/` |

## Fixture inventory (37 files, 13 fixtures)

| fixture | role | files |
|---|---|---|
| `xs-dead` | PIT-248 negative control: rethrow inside pruned (unreferenced private static) code | `xcheckscope/DeadProbe.hx`, `gen/rust.hxml` |
| `xs-deadcoll` | PIT-248 negative control: dead code + variant-name collision (`CExceptionFault`) | `xcheckscope/DeadCollProbe.hx`, `gen/rust.hxml` |
| `xs-twoexc` | two payload exception classes in one module; pre-existing defect: 101 in **all** three states (E0277 family) | `xcheckscope/TwoProbe.hx`, `gen/rust.hxml` |
| `xs-testmod` | PIT-248 leak-3 check: `ValueExceptionFault(Box<…>)` must not leak into production `boring/value_exception.rs` | `xcheckscope/ProdRethrowTests.hx`, `gen/rust.hxml` |
| `xs-generic` | guard (generic shape) | `xcheckscope/GenProbe.hx`, `gen/rust.hxml` |
| `xs-growth` | guard (payload-enum growth) | `xcheckscope/GrowthProbe.hx`, `gen/rust.hxml` |
| `xs-samples` | guard (samples-side) | `gen/rust.hxml` (drives the `samples/` tree) |
| `xs-scope` | guard (scope shape) + `expected.txt` pin (`detect=0`) | `xcheckscope/ScopeProbe.hx`, `gen/rust.hxml`, `expected.txt` |
| `xs-xmod` | guard (exception class in a second module) | `xcheckscope/XModProbe.hx`, `otherpkg/{ModEx,ModOps}.hx`, `gen/rust.hxml` |
| `xs-crossmod` | **PIT-297 discriminator**: two payload exception classes in ONE Haxe module, payload enums in TWO modules; the only fixture that fails (101, E0609) without the class-first read-site fix | `xsxm/{CrossProbe,Faults1,Faults2}.hx`, `gen/rust.hxml`, `README.md` |
| `xt-classemit` | PIT-297 guard: class-emission shape | `classemit/ClassEmitProbe.hx`, `gen/rust.hxml` |
| `xt-oneexc-nofault` | PIT-297 negative control (no `Fault` suffix → stays 101 by design) | `onefaultscope/OneFaultProbe.hx`, `gen/rust.hxml` |
| `xt-twoexc-emit` / `xt-twoexc-emit-rev` | PIT-297 guards (PIT-281's discriminator family; byte-identical trees pre/post PIT-297) | `twoemitscope/TwoEmitProbe.hx`, `twoemitrevscope/TwoEmitProbeRev.hx`, `gen/rust.hxml` ×2 |
| `xs-twoexc-faultnames` / `xs-twoexc-swapped` | PIT-297 guards (variant-name / declaration-order axis of `xs-twoexc`) | `xcheckscope/TwoProbe.hx` each, `gen/rust.hxml` each |

The `xs-twoexc*` files were archived from `dc-warn/worktrees/rust-payload-key/`
(identical copies in `rust-thrown-gap`) and are **byte-identical** to the
`b18b99df` copies (verified 2026-09-30, see REPORT.md).

## Provenance of the bytes

| byte set | source |
|---|---|
| `xs-dead`, `xs-deadcoll`, `xs-generic`, `xs-testmod`, `xs-xmod`, `xs-twoexc*` | `dc-warn/worktrees/rust-fixed-xcheck` (+ identical copies in `rust-fixed-xcheck-pre`, `rust-regression-fix`, `rust-trytail-xcheck`; `xs-twoexc*` also in `rust-payload-key`, `rust-thrown-gap`) — per `evidence/fixture-provenance.tsv` |
| `xs-growth`, `xs-samples`, `xs-scope` | `dc-warn/worktrees/rust-regression-fix` (identical in `rust-trytail-xcheck`) — per the same TSV |
| `xs-crossmod`, `xt-*` (13 files) | commit `b18b99df9869e7e44e9234324dd33282e730af9a` on branch `fix/rust-module-keyed-read-sites` (repo `boring-wt-architecture`), extracted byte-exact via `git show b18b99df:tests/haxe/…`. That commit's own message records the `xs-crossmod` bytes as "archived verbatim from the reviewer probe (`dc-warn/out/rust-modkey-fix/fixtures`)" |
| `compiler-states/as-reviewed/` | `dc-warn/out/rust-regression-fix/src-postfix/` (itself a read-only copy of the coordination tree's uncommitted as-reviewed state, hash-anchored by that dir's `FILES.sha256`) |
| `compiler-states/frozen-57ee4997/` | working state of the shared coordination tree `boring-wt-architecture` (branch `ci/collected-suite-failure-attribution` @ `5a8f19e6`, 4 uncommitted files) at archive time; identical bytes at `dc-warn/out/rust-payload-key-fix/evidence/compiler-frozen/Compiler.hx` and `dc-warn/out/rust-thrown-class-gap/evidence/05-compiler-source/Compiler.hx` |

As of the row's §9 commit (coordinator directive 2026-09-30) the 37 fixture
files are also tracked at their canonical `tests/haxe/<fixture>/` paths on
branch `chore/archive-xs-fixture-family` — a checkout of that branch *is* a
restore; `RESTORE.sh` still serves the independent out-of-tree archive copy.
The archive's `compiler-states/` snapshots and drivers remain the pinned
inputs for any state-anchored re-measurement.

## How to reproduce a reading (worked example: PIT-248 core)

```bash
# 1. a clean tree at the pinned revision
git -C <repo> worktree add --detach /tmp/xs-run e1c65975
# 2. haxelib context (boring lib = the tree itself, reflaxe = the nix-store
#    framework source; copy the layout from any worktree that has one)
mkdir -p /tmp/xs-run/.haxelib/{boring,reflaxe}
echo /tmp/xs-run > /tmp/xs-run/.haxelib/boring/.dev
echo /nix/store/ch901mw058pjvr3nyxgwxps31vc46wmm-source > /tmp/xs-run/.haxelib/reflaxe/.dev
# 3. restore the fixtures (byte-verified both sides)
bash <this-archive>/RESTORE.sh /tmp/xs-run
# 4. measure (one state; the driver automates all three + hash anchors)
bash <this-archive>/drivers/run-three-state.sh /tmp/xs-run <evidence-dir>
```

Readings to expect: see `EXPECTED-READINGS.md`.
