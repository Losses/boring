# P09 fixed-matrix preparation runbook

Preparation-only record for the fixed-revision full-matrix acceptance (task
`固定版本 Boring 与 Tiqian 全矩阵验收`). Written 2026-09-29 by the third
parallel slot (research/preparation; no heavy matrix launched, no production
code changed). This runbook is cold-start executable: an operator who has
never seen this workspace can run every command below from the stated working
directories. Nothing here supersedes the fixed inputs; anything found to
disagree with them must stop the run, not be papered over.

## Fixed revision pair and input hashes

| Input | Identity | Verified by |
| --- | --- | --- |
| Boring fixed revision | `2159c657dcca870950b7bd43aa6e09a21d7cee30` (commit "refactor(compiler): migrate target comparison policy consumers", 2026-09-29) | `git rev-parse 2159c657^{tree}` in `boring-wt-architecture` = `9b2f77dadd4120a71865711acc423b63142f0997`, equal to the tree recorded in `publication-staging/published-tree-equivalence.json` |
| Compiler snapshot | `publication-staging/fixed-compiler-2159c657/` (gitless copy; 1366 entries) | `publication-staging/published-tree-equivalence.json` (equivalent: true, no missing/extra/mismatch) and per-file inventory `publication-staging/option-c-source-before.json` (1366 path/sha256/mode entries) + `architecture-workspaces/tiqian-validation-round2/out/tiqian-prep/artifacts/snapshot-fixed-compiler-2159c657-inventory.sha256` (1366 lines) |
| Tiqian fixed revision | `8504d230228e8206689a2049bbb84b671c1f079a` | detached HEAD of `architecture-workspaces/tiqian-validation-round2`; `git status` clean for tracked files; 6 untracked config files are hash-pinned below |
| Derived preparation | `architecture-workspaces/tiqian-validation-round2/out/tiqian-fixed-2159c657-prep/` (manifest.json, hxml/ x12, haxelib/, library-resolution/, attempt-ts-001/run.py) | all 30 manifest hashes (15 originals + 15 derived) independently recomputed 2026-09-29: all match. `status: preparation-only-not-executed`, `generationStarted: false` |
| Driver wrapper (historical pin; not the matrix driver) | `/nix/store/9jh8smxb2p24lralfj7gnnj806xcx788-boring-driver-0.0.1/bin/boring`, sha256 `af6aeef816ea615239e1d2cf17471aa3969d965a36993491e8446b166970289d`; `share/boring/driver.js` sha256 `a8f5ef0e3c49198a542190d505a0ad50add6af29afa48ff6ed5875971bb8de57` | manifest fields `driverWrapperSha256` / `driverJsSha256`; re-asserted inside every attempt runner (`attempt-ts-001/run.py` L20-21). Pinned `304ed70c` artifact, retained as provenance |
| Matrix driver (rebuilt from the snapshot; see B2) | `out/bundle/driver.js` sha256 `bf2450d35639c01d36ecfe93b8ddb6c4b3f542e980da0731fad8861cbcea1e53` (52,779 bytes), built with haxe 4.3.7, argv `haxe tools/bundle/driver.hxml` | `dc-warn/out/driver-rebuild/` (`driver-identity.json`, `driver-js.sha256`, `haxe-version.txt`) |
| Coordinator worktree state | HEAD `c9e2cff97b18ce8387708d33667b56687ab7ea1b` on `arch/agent-guided-governance` | the two commits after `2159c657` (`f2aa3633`, `c9e2cff9`) touch only `docs/` (verified with `git diff --stat 2159c657..HEAD`), so the fixed revision remains the newest compiler state |

The 15 hash-pinned originals are the twelve HXMLs and three project files
under `out/architecture-candidate-inputs/` plus
`boring-architecture-{candidate,engine-candidate,protocol-candidate}.json`
(consumer root). The 15 derived files are the twelve HXMLs under
`out/tiqian-fixed-2159c657-prep/hxml/` plus
`boring-fixed-2159c657-{all,engine,protocol}.json` (consumer root). The
`protocol-c.hxml` derived file is byte-identical to its original (it is
excluded from the path-resolution pass; see blocker B4).

## Pre-blockers (none may be treated as passed by default; B2 closed, B3 and B4 still open)

### B1 Rust fix candidates are frozen out of the fixed revision

`2159c657` predates the two in-flight Rust fixes
(`fix/rust-typedef-signed-key`, `fix/rust-readonly-alias-emitter`, both
status doing on the board). The staging snapshot must not be rebuilt from the
coordinator worktree: that worktree carries four uncommitted modifications
(`docs/investigations/architecture-round-1/d-observation.md`,
`tests/haxe/kotlin-staticfn-prepared-init/run-focused.sh`,
`tests/haxe/ts-template-newline-escape/run-datatable.sh`,
`tests/haxe/ts-template-newline-escape/run-focused.sh`) that are not part of
the fixed tree. If either Rust fix lands and must be covered by this
acceptance, the fixed revision is re-selected and static preparation is
re-run from the start; the existing preparation does not carry those changes.

### B2 Driver provenance: closed by snapshot rebuild (option a; was `driverSourceRevisionVerified: false`)

Status: **closed (option a)**. The isolated tree
`dc-warn/worktrees/driver-rebuild` (detached at `e1c65975`) compiled the
snapshot's own `tools/bundle/driver.hxml` under `nix develop -c` with
haxe 4.3.7: argv `haxe tools/bundle/driver.hxml`, cwd = tree root, exit 0.
Product `out/bundle/driver.js` sha256
`bf2450d35639c01d36ecfe93b8ddb6c4b3f542e980da0731fad8861cbcea1e53`
(52,779 bytes). The three compile inputs (driver.hxml
`8432f79927b2ad65e9d7b795df3f06ac513cb5082aff4fbafc586b7146bc1d87`,
Driver.hx
`749a778241d9ad2c3d9e1ca921a1975003f5260422cbfdf7edf08c91788d82a7`,
ChildEvidence.hx
`bc5f44040497f8075a64692de0b52f4a1f3923ba832778aa8e2f2ccccfc9dd3b`) hashed
identically before and after the build; the snapshot was not written.
Minimal usability was probed read-only with bun: no-arg invocation prints the
`gen|test|pack|compare|verify` usage line and exits 2; `--help` is rejected
with exit 1; `--project` with a missing file enters loadProject and exits 1.
Evidence directory: `dc-warn/out/driver-rebuild/` (REPORT.md,
driver-identity.json, driver-js.sha256, haxe-version.txt,
inputs-before.sha256, inputs-after.sha256, run-*.log).

Equivalence ruling: the sequence below executes only the `gen`, `test`, and
`compare --project` actions (steps 1-4). Independent greps over the frozen
plan and the prep directory for `roots`, `--output`, and `--with-pack` find
hits only inside hxml comments, with no invocation. For the commands this
plan executes, the snapshot-rebuilt driver is therefore drop-in
equivalent, and `driverSourceRevisionVerified` may be recorded as true with
`driverJsSha256` =
`bf2450d35639c01d36ecfe93b8ddb6c4b3f542e980da0731fad8861cbcea1e53`,
`haxeVersion` = `4.3.7`, and the build argv above.

Residual (unreachable under this plan): relative to the pinned `304ed70c`
driver, the rebuilt driver **lacks** the `roots` action, the `--output`
option, and the darwin-only DYLD branch; those three are capabilities of the
pinned `304ed70c` driver only (`dc-warn/out/driver-rebuild/REPORT.md` §④).
Neither driver reads `BORING_SWIFT_LIBDISPATCH` or
`BORING_SWIFT_DYNAMIC_LINKER`; both read `BORING_SWIFT_SYSTEM_PACKAGE`. This
plan executes only the `gen`, `test`, and `compare --project` actions, so all
three are unreachable under it; if a future plan introduces the `roots`
action or the `--output` option, this closure no longer applies and the
equivalence ruling must be re-made before running.

Historical pin, retained (not the matrix driver): the flake store path
`/nix/store/9jh8smxb2p24lralfj7gnnj806xcx788-boring-driver-0.0.1` with
wrapper sha256
`af6aeef816ea615239e1d2cf17471aa3969d965a36993491e8446b166970289d` and
`share/boring/driver.js` sha256
`a8f5ef0e3c49198a542190d505a0ad50add6af29afa48ff6ed5875971bb8de57` records
where the pinned `304ed70c` artifact came from; the matrix runs the snapshot
rebuild above and never the pinned artifact.

### B3 Swift toolchain: flake wrapper broken in this environment; fallback recipe verified; SystemPackage shared library not built

The flake-provided `swiftc` wrapper
(`/nix/store/f0pa9lppswnls248abfl142s77a99yw4-swift-6.2.4-wrapped/bin/swiftc`)
fails here: `bwrap: setting up uid map: Permission denied` (process runs with
empty capability set; the `buildFHSEnv` bwrap path cannot create its uid
map). Verified fallback (all probes executed 2026-09-29, rc values recorded):

```shell
SWIFT_DIST=/nix/store/j1bfa7mw323wmp6pfrn1qkchxv61wk2n-swift-toolchain-6.2.4-al2
SWIFT_FHS=/nix/store/xq9k8vi7gqw0wn592p95wzvzf3wzn4kh-swift-6.2.4-fhs-fhsenv-rootfs
# SDK symlink tree (one-time, inside the attempt dir):
mkdir -p sdk/usr
ln -sfn $SWIFT_FHS/usr/include sdk/usr/include
ln -sfn $SWIFT_FHS/usr/lib64 sdk/usr/lib64
ln -sfn $SWIFT_FHS/usr/lib   sdk/usr/lib
ln -sfn $SWIFT_FHS/usr/share sdk/usr/share
export LD_LIBRARY_PATH="$SWIFT_FHS/usr/lib64:$SWIFT_FHS/usr/lib:$SWIFT_DIST/usr/lib/swift/linux"
# probe results: swiftc --version rc=0 (Swift 6.2.4); import Glibc -typecheck rc=0
$SWIFT_DIST/usr/bin/swiftc --version
$SWIFT_DIST/usr/bin/swiftc -typecheck -sdk $PWD/sdk b.swift
```

Requirements: `XDG_CACHE_HOME` and `TMPDIR` must point into writable, existing
per-attempt directories (the default `~/.cache/clang` module cache is
permission-denied in the sandboxed shell; the probe without it failed with
"Permission denied" on the clang ModuleCache). `XDG_CACHE_HOME` must be
verified writable with `touch $XDG_CACHE_HOME/.probe && rm $XDG_CACHE_HOME/.probe`
before any stage. The driver invokes bare `swiftc` on PATH for both Swift
build steps, so a wrapper script named `swiftc` (injecting `-sdk <attempt>/sdk`
plus the `LD_LIBRARY_PATH` above) must be prepended to `PATH` for the Swift
stages. Runtime environment for the linked test binaries (values from the
coordinator flake `flake.nix` L153-168, store paths re-verified):
`BORING_SWIFT_LIBDISPATCH="$SWIFT_DIST/usr/lib/swift/linux:<gcc lib dir>"`
and `BORING_SWIFT_DYNAMIC_LINKER="$SWIFT_FHS/usr/lib64/ld-linux-x86-64.so.2"`
(both store paths exist; the loader path was verified).

Open build step: the generated Swift trees import `SystemPackage`
unconditionally (snapshot reference
`out/.../gen/boring/PlatformOps.swift` line 18 in prior outputs). The driver
fails the Swift test step without a `BORING_SWIFT_SYSTEM_PACKAGE` directory
holding `SystemPackage.swiftmodule` and a `libSystemPackage` shared library
(`driver.js` L1463-1484, L1882-1887). Attribution is verified: both
`boring/Package.resolved` and the fixed snapshot's `Package.resolved` pin
swift-system 1.6.6 at revision `0b30161977799fd949f7f6848586b82ff6764f73`, and
`boring/.build/checkouts/swift-system` is checked out at exactly that revision.
`boring/.build/x86_64-unknown-linux-gnu/debug/Modules/SystemPackage.swiftmodule`
exists (built 2026-09-26 from that checkout), but no `libSystemPackage.so` was
ever produced in `.build` (verified absent). Building the shared library from
the pinned sources with the fallback toolchain is a mandatory pre-matrix step;
until it exists, the two Swift test obligations are blocked, and the
regression conclusion must say so.

### B4 protocol-C execution authorization

`protocol-c` keeps `test: false` and an `afterGen` step
(`bun engine-haxe/out/protocol-c/gen/c-header.js`). The manifest's
`protocolCException.status` is `requires-execution-authorization` and
`genStartAbsenceRecorded` is false. The physical absence of the pre-gen state
was re-verified 2026-09-29: `out/tiqian-fixed-2159c657-prep/outputs/` and
`.../results/` do not exist. The executor must re-record the output-absence
provenance at gen start (the `gen-start.json` pattern in
`attempt-ts-001/run.py` L26) and must not run the `afterGen` bun command
without explicit authorization.

## Execution environment (verified 2026-09-29)

Pinned store paths, all present:

| Tool | Store path | Verified |
| --- | --- | --- |
| driver 0.0.1 | `/nix/store/9jh8smxb2p24lralfj7gnnj806xcx788-boring-driver-0.0.1` | exists; wrapper + driver.js hashes asserted per attempt |
| haxe 4.3.7 (haxe + haxelib) | `/nix/store/98pb92k7pi6g5cifmg872jn18kghaxw5-haxe-4.3.7` | exists; `bin/` carries both |
| bun 1.3.13 | `/nix/store/q89kjapqlqwlvlvwaicq6djbqp2dadgm-bun-1.3.13` | exists |
| reflaxe | `/nix/store/ch901mw058pjvr3nyxgwxps31vc46wmm-source` | exists; referenced by the HXMLs and the prep haxelib |
| kotlin 2.4.10 (kotlinc) | `/nix/store/rqx09a40a82di944xi6ydjyzx632av28-kotlin-2.4.10` | exists |
| cargo/rustc 1.97.1 | `/nix/store/09f71fs41vbs1k1y1l78ka6cy7w1hnsh-rust-default-1.97.1` | exists |
| openjdk 25.0.4+7 (java) | `/nix/store/0a9l8lf8394msppsna27y58f8ljqyifn-openjdk-25.0.4+7` | exists |
| swift 6.2.4 raw dist | `/nix/store/j1bfa7mw323wmp6pfrn1qkchxv61wk2n-swift-toolchain-6.2.4-al2` | exists (see B3) |
| swift FHS rootfs | `/nix/store/xq9k8vi7gqw0wn592p95wzvzf3wzn4kh-swift-6.2.4-fhs-fhsenv-rootfs` | exists (see B3) |

Not materialized: the dart SDK store path (consumer flake `pkgs.dart`,
nixpkgs pin `8be7bd0c83f12e2e3bbba07c9044d6fed9e66f7f`); `nix develop` in the
consumer checkout must materialize it before the `dart` test stage. If any
pinned path is missing at run time, stop: a missing store path means the
flake lock or the store changed, and the preparation identities no longer
apply.

Shell discipline (from the preparation review, still binding): the consumer
`flake.nix` shellHook resets `HAXELIB_PATH` to `$PWD/.haxelib` (pinned
`304ed70c` boring mapping) and re-runs `haxelib dev boring`. Set the candidate
mapping **after** the hook, in the **same** shell that runs generation:
`export HAXELIB_PATH=/home/losses/Development/tq-workspace/architecture-workspaces/tiqian-validation-round2/out/tiqian-fixed-2159c657-prep/haxelib`
(verified resolution: `haxelib path boring --global` exits 0 and resolves
`boring` to the staging snapshot's `packages/compiler/` with the
`registerDefinesDescriptionFile` macro; `haxelib path reflaxe --global` exits
0 to the reflaxe store path). Opening a second `nix develop` between the
override and the generation run can restore the pinned mapping.

## Stage commands (per attempt)

Working directory for every stage:
`/home/losses/Development/tq-workspace/architecture-workspaces/tiqian-validation-round2`.
One attempt directory per stage, mirroring `out/tiqian-fixed-2159c657-prep/attempt-ts-001/`
layout: `before.json` / `after.json` (input snapshots: 1366-entry compiler
inventory, consumer `git ls-files` digests, 30 manifest configs), `argv.json`,
`env.json` (PATH, HAXE_STD_PATH, HAXELIB_PATH, XDG_CACHE_HOME, TMPDIR),
byte-streamed `stdout` / `stderr`, numeric `status`, `parsed-modules.json`,
`outputs.json`, `integrity.json` (`unchanged` + `returncode`). `XDG_CACHE_HOME`
and `TMPDIR` point inside the attempt dir and are writability-probed first.

Driver CLI (from the pinned driver's usage line):
`boring <gen|test|pack|compare|verify|roots> [<id>...] [--project <file>] [--with-pack] [--output <file>]`.
This plan invokes only `gen`, `test`, and `compare --project`; the `roots`
action and the `--output`/`--with-pack` options are not used (see B2 for the
equivalence scope and the residual).

Sequence (engine and protocol groups run sequentially, per the preparation
review):

1. `boring gen` for all 12 generation targets, in three project groups so each
   bundle runs with its own baseline file:
   `boring gen <8 engine ids...> --project boring-fixed-2159c657-engine.json`
   then `boring gen <4 protocol ids...> --project boring-fixed-2159c657-protocol.json`.
   (The `boring-fixed-2159c657-all.json` file is the 12-bundle union but keeps
   the engine baseline `kotlin-f32`; use the two group files, not `all`, so
   protocol bundles compare against `protocol-ts`.)
2. `boring test <8 engine ids...> --project boring-fixed-2159c657-engine.json`
   (per-bundle driver steps: ts `bun test gen-tests`; dart
   `dart gen-tests/main.dart`; kotlin `kotlinc -include-runtime` -> jar then
   `java -cp ... TestMainKt`; rust `cargo test --no-run` then `cargo test`
   with cwd = gen dir; swift `swiftc -emit-library` + `swiftc` test-runner +
   run test-runner with `-I/-L/-lSystemPackage` per B3).
3. `boring test <protocol-ts,protocol-rust,protocol-kotlin> --project boring-fixed-2159c657-protocol.json`
   (`protocol-c` is `test: false` and is not testable; its `afterGen` bun step
   awaits B4 authorization).
4. `boring compare --project boring-fixed-2159c657-engine.json` (baseline
   `kotlin-f32`) and `boring compare --project boring-fixed-2159c657-protocol.json`
   (baseline `protocol-ts`; the comparable ids are the three protocol test
   bundles — the three-protocol-root union).

Per stage the attempt dir must retain: command, stdout, stderr, numeric exit
code, warnings (native compiler warnings stay in the captured streams, no
filtering), and the test-ID set (the `<resultsDir>/<bundle-id>.jsonl` files
under `out/tiqian-fixed-2159c657-prep/results/`; missing test IDs are resolved
through source coverage, not by dropping absent observations).

## Invariant re-verification after the run

After the matrix completes (or aborts), re-run and record: the 30-manifest
hash recomputation; the 1366-entry compiler inventory digest;
`git status --short` in the consumer checkout (tracked tree must still be
clean); `git rev-parse HEAD` in both checkouts; the driver hash asserts (the
rebuilt `driver.js` sha256 `bf2450d35639c01d36ecfe93b8ddb6c4b3f542e980da0731fad8861cbcea1e53`
per B2; the store-path wrapper pin stays recorded as historical provenance).
Any drift voids the attempt and requires a new attempt dir; the
drifted attempt is retained as historical evidence, never deleted or
rewritten.

## Stale inputs — do not reuse as live inputs

| Input | Status |
| --- | --- |
| `boring-architecture-{candidate,engine-candidate,protocol-candidate}.json` (consumer root) | preparation outputs for the pre-fix architecture candidate; superseded by the three `boring-fixed-2159c657-*.json` files. Retained hash-pinned as manifest originals only |
| `out/architecture-t2/attempt-01-20260928T093930Z-1613971` (+ `identity-check-01`) | the first static preparation against coordinator revision `8a5aa83a`; its 12+3 outputs do not identify the current candidate inputs (the later `039e1a43` checkpoint includes compiler and fixture files). Historical evidence only, per the preparation review |
| `out/architecture-candidate-inputs/` (12 HXML + 3 JSON + `mapping-manifest.json` + `diffs/`) | the originals of the fixed preparation; retained for provenance, never a live input |
| consumer `.haxelib/` (pinned `304ed70c` mapping created by the flake shellHook) | must be shadowed by the prep haxelib dir for the whole run; any haxelib lookup through it would load the pinned compiler, not the fixed one |
| `out/tiqian-prep/artifacts/*` manifests | previous-round static artifacts; the `verify-prep.py` tool (v1.4.0) is reusable for manifest/path/loaded-path static checks, its artifacts are not inputs to this run |
| `out/tiqian-fixed-2159c657-prep/attempt-ts-001/` | dry recipe (never executed; `outputs/ts` absent); its `run.py` is the template for new attempt runners, not evidence of a completed stage |

## Review scope (lead review + independent review)

The regression conclusion may only cite: the fixed revision pair
(`2159c657dcca870950b7bd43aa6e09a21d7cee30` x
`8504d230228e8206689a2049bbb84b671c1f079a`), the per-bundle test-ID sets from
the results JSONL, and the invariant re-verification above. The uncovered
scope must be listed explicitly in the conclusion: (1) `protocol-c`
`afterGen` (B4, unauthorized at preparation time); (2) the driver residual
(B2): provenance itself is closed by the snapshot rebuild, but the `roots`
action and the `--output` option remain unreachable under this plan and any
future plan that uses them voids the closure; (3) Swift obligations
blocked on the `libSystemPackage` shared library and the fallback toolchain
recipe (B3); (4) the two in-flight Rust fixes, frozen out by B1; (5) anything
whose stage aborted, with its numeric exit code and captured streams retained.
The independent review re-runs, from this document alone: the 30-hash
recomputation, the protocol-root union check (twelve HXMLs; the three protocol
HXMLs each retain the eight common test roots
`CanonicalTest, NamedErrorTest, ParagraphRequestTest, PlanJsonTest,
PlanPackedTest, PlanSchemaTest, RevisionTest, SnapshotTableBinaryTest`; union
of test roots = 8; nothing lost against the tracked `8504d230` sources, with
rust and kotlin each carrying two appended roots), and the driver hash asserts.

## Preparation-time findings recorded for the conclusion

- 12 generated HXML files match the 12 bundles of `boring.json` one-to-one
  (engine 8 + protocol 4); 11 testable targets (engine 8 + protocol 3) because
  `protocol-c` is `test: false`.
- All derived HXMLs carry explicit absolute `-cp` paths to the staging
  snapshot (`packages/compiler/`, `samples/`), the reflaxe store path, the
  prep haxelib `format` copy, verbose `-v`, and output redirection into
  `out/tiqian-fixed-2159c657-prep/outputs/`; `libraryResolution` records
  before/after sha256 for the 11 resolved HXMLs and
  `driverAutomaticLibInjection: false`.
- `publication-staging/fixed-compiler-2159c657/` is not a git repository; its
  identity rests solely on the tree-equivalence record and the 1366-entry
  inventory. The `git rev-parse 2159c657^{tree}` cross-check above is the
  independent anchor.
- The consumer checkout's untracked file count grew from 3 to 6 between the
  old and the fixed preparation (the three `boring-fixed-2159c657-*.json`);
  this matches the manifest originals/derived pairing.
