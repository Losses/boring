# Readonly-alias fixture: ordinary `Array -> ReadOnlyArray` on five targets

This fixture consolidates the historical **S**, **D**, and **X** probes into
one authored Haxe oracle and one five-target evidence run. It verifies the
ordinary shared-container ruling of
[`boring/docs/specs/features/18-immutability.md`](../../../docs/specs/features/18-immutability.md):
an `Array<T> -> ReadOnlyArray<T>` conversion retains the shared container,
later slot writes and length changes remain visible through the view, and
the view outlives the producer frame. The decode-boundary protection of the
same spec is a separate contract and is out of scope here.

## Shapes (five)

| shape | encoding | discriminated reading |
|---|---|---|
| `alias` | S: convert local, write slot 0 to 7, append 9, read `view[0]*100 + view.length` | shared `702` vs snapshot `101` |
| `passed` | D: array crosses a call boundary as a read-only argument; callee returns the parameter view; caller mutates the retained alias before reading | shared `3301` vs argument/return copy `1201` |
| `escaped` | X case 2: conversion at the producer return; the view is the only surviving reference | `56` when the view retains its storage |
| `rebind` | X case 1: source binding reassigned to another container after the conversion | retained storage `123` vs binding-following `987` |
| `boundary` | X case 4: producer returns the view plus a holder keeping a mutable alias to the original; after the return the alias mutates the original | shared `564:1494` vs detached `564:564` |

The authored expected lines (the feature 18 shared-container reading,
written independently of any run) are in `expected.txt`:

```
alias=702
passed=3301
escaped=56
rebind=123
boundary=564:1494
```

X's local-mutation case (42) and combined case (123) are not separate
shapes here: local mutation is covered by `alias`'s slot write and
`boundary`'s holder mutation, and combined (return + rebind) is covered by
`escaped` (view outlives the producer) plus `rebind` (rebind after the
view exists).

## Authored sources

- `roalias/ReadOnlyAliasOracle.hx` — the five shape functions plus the
  `passThrough` / `makeView` / `boundaryProducer` helpers and a `main()`
  that logs the labeled lines on the Haxe JS oracle only (native harnesses
  print the same lines; native generated trees keep an empty `main` so the
  fixture adds no target-specific console dependency).
- `roalias/AliasHolder.hx`, `roalias/BoundaryResult.hx` — holder and result
  records mirroring the accepted pattern of `tests/haxe/view-lifetime`.
- `oracle.hxml` — Haxe JS oracle (Intercept + `-main ReadOnlyAliasOracle`).
- `gen/{ts,kotlin,rust,swift,dart}.hxml` — per-target generation input; the
  runner passes `-D <target>-output` and `-D <target>-test-output`.
- `native/{main.js,Main.kt,harness.rs,native-main.swift,main.dart}` — the
  five native harnesses copied into the generated trees by the runner.

## Provenance and revision identity of the consolidated probes

### S — ordinary alias on the then-known targets

- Report: `/tmp/boring-architecture-round1/reports/s-alias-targets.md`
  (read-only provenance input; the worktree out tree
  `boring-wt-architecture/out/architecture-alias-targets` retains the
  `e3b8-source` compiler archive, the probe records were cleaned).
- Compiler revision: `e3b8bab39ac2da0e17e9d04e031f03bd39290274`
  (archived as `boring-wt-architecture/out/architecture-alias-targets/e3b8-source`).
- Aggregate input hash: `13fe3e590d890cbc808916602f287a17ddadafcb30fafebb033486a4dde7d704`.
- Tool identity: Haxe 4.3.7, Bun 1.3.13, Node 22.23.2, Kotlin 2.4.10,
  Dart 3.13.0, Cargo 1.98.0.
- Observation: the authored Haxe oracle printed `ALIAS=702`; TS, Kotlin and
  Dart observed `702`; Rust observed `101` through the emitted
  `let readonly = (mutable).clone()` local-init clone. **Swift was never
  executed in S**; the shared-view question stayed an unverified checkpoint.
- This fixture re-uses S's exact scalar encoding as `alias` and re-observes
  all five targets at the current compiler revision.

### D — Swift readonly boundary probe

- Reports: `/tmp/boring-architecture-round1/reports/d.md` and
  `/tmp/boring-architecture-round1/reports/d-v2.md` (read-only provenance
  inputs).
- Evidence tree: `boring-wt-architecture/out/architecture-readonly-probe/`
  (recording, logs and Swift generated artifacts still present).
- Compiler revision: `e3b8bab39ac2da0e17e9d04e031f03bd39290274`; worktree
  HEAD at capture `80a94d31`.
- Observation: Haxe plain conversion `702` versus the pre-J Swift lowering
  `101` for the ordinary local case; the guarded-optional and optional-cell
  red items belong to the pre-existing nullable fallback and remain out of
  scope for this fixture (this fixture is ordinary/non-nullable only).
- This fixture supplies the call-boundary position D left open (`passed`)
  and re-observes Swift under the current integrated revision.

### X — view-lifetime exercise

- Design reports: `/tmp/boring-architecture-round1/reports/x-goose-design.md`,
  `x-goose-design-v2.md`, and `x-native-design.md` (read-only provenance
  inputs).
- Implemented fixture: `tests/haxe/view-lifetime/` on
  `arch/agent-guided-governance` (this worktree at `c9e2cff9`):
  `ViewLifetimeOracle.hx`, `native-main.swift`, `oracle.hxml`, `swift.hxml`,
  `run.sh`. Shapes rebind / escaped / local-mutation / combined / boundary
  with expected `123 / 56 / 42 / 123 / 564:1494`.
- Status at consolidation: the design and oracle are authored but the
  lifetime exercise **remains outstanding** (never executed); the governance
  plan names it the outstanding checkpoint. This fixture consolidates X's
  discriminating shapes into the five-shape oracle and executes them on all
  five targets.

## Evidence layout and contract

`run.sh` allocates one fresh `out/readonly-alias/runs/ro-XXXXXXXX` per
invocation and records, per stage, the shell-quoted argv, cwd, separated
stdout/stderr, and numeric exit status. Stages:

- identity: UTC, worktree HEAD, dirty state, tool versions (haxe, bun,
  swiftc, kotlinc, rustc, cargo, dart, java), resolved boring library path,
  authored-source hashes.
- `input-hashes-before` / `input-hashes-after`: sha256 manifest over
  `packages/compiler`, the fixture, and `tests/support`; the two must match.
- `haxe-oracle-compile` / `haxe-oracle-run` / `haxe-oracle-expect`: the
  Haxe JS oracle and its diff against `expected.txt`.
- per target (`ts`, `kotlin`, `rust`, `swift`, `dart`):
  `gen-<t>`, `compile-<t>`, `run-<t>`, `compare-<t>`; the generated tree is
  digested into `<t>-tree.sha256` after a successful generation.
- `membership`: stage-row membership against the declared stage list
  (`tests/support/stage-check.sh`).

A failed generation is an observation: `compile`/`run`/`compare` are
recorded `not-reached(producer=<gen stage>, status=<exit>)`, never as a
semantic difference. A `compare` difference is a recorded observation
(e.g. the Rust clone positions) and not a fixture failure; `compare-notes.txt`
carries the per-shape diffs and the review must attribute each difference to
a generated mechanism (clone position, borrow, value semantics) or to a
target toolchain / runtime limitation.

Verdict vocabulary: `success`, `observed-differences`, `failed`,
`harness-defect`. Only `failed` and `harness-defect` exit nonzero; the
others are retained evidence.

## Run

From the repository root, inside the boring devShell (nix 2.34+,
`XDG_CACHE_HOME` pointing at a writable cache directory):

```
timeout 3600 nix develop -c bash tests/haxe/readonly-alias/run.sh
```

Every long command inside the runner is wrapped in `timeout`.

Swift toolchain note: the devShell `swiftc` wrapper sets up its FHS
environment through bubblewrap, which this container rejects for an
unprivileged user (`bwrap: setting up uid map: Permission denied`). The
runner probes the wrapper first; when it is rejected it resolves the raw
store toolchain plus the FHS rootfs libraries, links from a working
directory holding symlinks for the bare-name CRT objects (ld.gold opens
those inputs relative to the CWD), and records the resolution and the
wrapper stderr in `swift-toolchain.txt`. If neither the wrapper nor the
raw toolchain is usable, the Swift stages are recorded `not-reached` as a
target toolchain limitation, never as a semantic difference.

## Out of scope

- The A3 integrated-tree production emitter and the decode-boundary
  protection of feature 18 (separate contract; this fixture only exercises
  the ordinary conversion).
- The R1–R6 writable-place fixtures and `tests/swift-readonly-boundary/`.
- Interpreting the Rust clone positions as "all readonly conversions fail";
  this fixture records where each position converts and what the target did.
- Counting the pre-existing Swift nullable-fallback red items as failures of
  this fixture.
