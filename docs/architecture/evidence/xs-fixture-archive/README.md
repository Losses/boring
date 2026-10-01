# REPORT — archive of the xs-* / xt-* regression fixture family (PIT-285)

Row: `t-munejtq3-mj9x` · branch `chore/archive-xs-fixture-family` (worktree
`boring-wt-xsarchive`, base `arch/agent-guided-governance` @ `5a8f19e6`)
Date: 2026-09-30 · Seat: PIT-285 archive row (coordinator-delegated)

**Archive location:** `/home/losses/Development/tq-workspace/dc-warn/out/xs-fixture-archive/`
**Raw evidence for this row:** `/home/losses/Development/tq-workspace/dc-warn/out/xs-archive/evidence/`
**Committed evidence package (repo):** `docs/architecture/evidence/xs-fixture-archive/` on
`chore/archive-xs-fixture-family` (report + manifests + expected readings +
compiler-state byte snapshots; evidence-only, following the `1704c3db` pattern).

Status: **doing** — all three SOP criteria are evidenced; sign-off is the
coordinator's (the row stops at 已开始 per the row's 验证 clause).

---

## 1. What the family is

13 Haxe→Rust regression fixtures (37 files) under `tests/haxe/`, driving the
rustcompiler fixes PIT-248 (fault-variant registration regression), PIT-281
(class-keyed payload map) and PIT-297 (module-keyed payload read sites).
Each fixture is a small probe crate: `<pkg>/<Probe>.hx` sources plus a
`gen/rust.hxml` driver that compiles them with `-lib boring -lib reflaxe` and
emits a standalone Rust crate; the discriminant is `cargo build --offline` of
that crate (rc 0 = generated code compiles, rc 101 = rustc rejects the
generated code — i.e. the compiler defect the fixture exists to catch is
present).

| fixture | judges | shape |
|---|---|---|
| `xs-dead` | PIT-248 negative control | rethrow inside pruned (unreferenced private static) code |
| `xs-deadcoll` | PIT-248 negative control | dead code + variant-name collision (`CExceptionFault`) |
| `xs-twoexc` | PIT-248 leak-4 + residual | two payload exception classes in one module; **pre-existing defect: 101 in every state** (never compiled) |
| `xs-testmod` | PIT-248 leak-3 | `ValueExceptionFault(Box<…>)` must not leak into production `boring/value_exception.rs` |
| `xs-generic`, `xs-growth`, `xs-samples`, `xs-scope`, `xs-xmod` | PIT-248 guards | generic / growth / samples / scope / second-module shapes (gen-only, expected 0) |
| `xs-crossmod` | **PIT-297 — the sole discriminator** | E1/E2 exception classes in ONE Haxe module, payload enums `F1Fault`/`F2Fault` in TWO modules; module-keyed read sites resolve last-scanned-wins → only the class-first read-site fix (PIT-297) makes it compile |
| `xt-twoexc-emit`, `xt-twoexc-emit-rev` | PIT-281 discriminators (guards under PIT-297) | emit-scope pairs |
| `xs-twoexc-faultnames`, `xs-twoexc-swapped` | PIT-297 guards | variant-name / declaration-order axes of `xs-twoexc` |
| `xt-classemit` | PIT-297 guard | class-emission shape |
| `xt-oneexc-nofault` | PIT-297 negative control | no `Fault`-suffixed payload enum → stays 101 by design |

Full file inventory: `xs-fixture-archive/README.md` (§ Fixture inventory) and
`RESTORE.sha256` (37 sha256-pinned entries).

## 2. Where the bytes came from (provenance, cited)

| byte set | source (cited) |
|---|---|
| `xs-dead`, `xs-deadcoll`, `xs-generic`, `xs-testmod`, `xs-xmod` | untracked copies in `dc-warn/worktrees/rust-fixed-xcheck/tests/haxe/` (identical copies in `rust-fixed-xcheck-pre`, `rust-regression-fix`, `rust-trytail-xcheck`); per-file mapping in `xs-fixture-archive/evidence/fixture-provenance.tsv`; sha256 cross-verified 2026-09-30 |
| `xs-growth`, `xs-samples`, `xs-scope` | untracked copies in `dc-warn/worktrees/rust-regression-fix/tests/haxe/` (identical in `rust-trytail-xcheck`); same TSV |
| `xs-twoexc`, `xs-twoexc-faultnames`, `xs-twoexc-swapped` | untracked copies in `dc-warn/worktrees/rust-payload-key/tests/haxe/` (identical in `rust-thrown-gap`); **byte-identical to the `b18b99df` copies** (verified 2026-09-30) |
| `xs-crossmod` (5 files) + `xt-classemit`, `xt-oneexc-nofault`, `xt-twoexc-emit`, `xt-twoexc-emit-rev` (8 files) | commit **`b18b99df9869e7e44e9234324dd33282e730af9a`** on branch `fix/rust-module-keyed-read-sites` (repo `boring-wt-architecture`), extracted byte-exact via `git show b18b99df:tests/haxe/…`. That commit's message records `xs-crossmod` as "archived verbatim from the reviewer probe (`dc-warn/out/rust-modkey-fix/fixtures`)". `b18b99df` is NOT an ancestor of the base branch — the family is not on the base line |
| `compiler-states/as-reviewed/` (4 files) | `dc-warn/out/rust-regression-fix/src-postfix/` (read-only copy of the coordination tree's uncommitted as-reviewed compiler, hash-anchored by that dir's `FILES.sha256`: `24f79c27…`/`985b5ad7…`/`cb18968c…`/`2f2119d8…`) |
| `compiler-states/frozen-57ee4997/` (4 files) | working state of the shared coordination tree `boring-wt-architecture` at archive time (`Compiler.hx = 57ee4997…`, `RustExpr.hx = 235d5a36…`, `RustDecl.hx = 985b5ad7…`, `RustEmissionState.hx = 2f2119d8…`); identical Compiler bytes at `dc-warn/out/rust-payload-key-fix/evidence/compiler-frozen/Compiler.hx` and `dc-warn/out/rust-thrown-class-gap/evidence/05-compiler-source/Compiler.hx` |

Why it was not reproducible before: `git ls-files 'tests/haxe/xs-*'` returns
**0 files** at `e1c65975`, at the base tip `5a8f19e6`, and on
`arch/agent-guided-governance`; only `b18b99df`'s side branch tracks 19 of the
37 files (the `xs-crossmod` + `xt-*` + `xs-twoexc*` set). The PIT-248 core
fixtures (`xs-dead`, `xs-deadcoll`, …) existed solely as untracked files in a
few seat worktrees — a fresh clone, or even a fresh checkout of the same
branch, had none of them, so every signed reading (PIT-248
`dc-warn/out/rust-regression-fix/`, PIT-297 `dc-warn/out/rust-module-keyed/`)
was reproducible only from one seat's live worktree.

## 3. Drivers and expected readings

Drivers archived in `xs-fixture-archive/drivers/`:
- `run-matrix.sh` — the PIT-297 seat's driver, **verbatim** (per-fixture
  `haxe …/gen/rust.hxml` gen rc + fresh-`CARGO_TARGET_DIR` `cargo build
  --offline` rc + `Compiling generated` count; `WT`/`OUT` constants point at
  that seat's tree — retarget to reuse).
- `run-three-state.sh` — this row's generalized driver: pristine /
  as-reviewed / frozen-57ee4997 states × fixtures, hash-anchored state swaps,
  leak-3 grep for `xs-testmod`, runner-collection probes, leaves the tree
  clean. The actual run used it; raw logs in `xs-archive/evidence/`
  (`env.txt`, `00-restore.log`, `01-restore-check.log`, `results.tsv`,
  `compiler-state.{pristine,as-reviewed,frozen}.txt`, one dir per
  state×fixture with `gen.stdout/stderr/status`, `cargo.stdout/stderr/status`,
  `compiling-count.txt`, `gen-tree.sha256`; `10-*`/`11-*` runner probes;
  `12-final-git-status.txt`).

Expected readings and per-value provenance (historical H248/H297 vs re-measured
R285): **`xs-fixture-archive/EXPECTED-READINGS.md`** — all values observed.

**This row's re-measurement (R285) — clean `e1c65975` worktree
(`xs-run-e1c65975`), haxe 4.3.7 / cargo 1.98.0 / rustc 1.98.0 / bun 1.3.13,
fixtures restored by `RESTORE.sh` (rc=0, 37/37 sha256-verified both sides):**

| fixture | pristine | as-reviewed | frozen-57ee4997 |
|---|---|---|---|
| `xs-dead` | 0/0 ✓ | 0/**101** (`E0004` `DFault::DExceptionFault(_)` not covered) ✓ | 0/0 ✓ |
| `xs-deadcoll` | 0/0 ✓ | 0/**101** (`E0428` duplicate `CExceptionFault`) ✓ | 0/0 ✓ |
| `xs-twoexc` | 0/101 (`E0277`+`E0433`×2) | 0/101 (`E0277`+`E0308`×3) | 0/101 (`E0277`+`E0308`+`E0433`) — pre-existing, documented |
| `xs-crossmod` | (not run in pristine) | 0/**101** (`E0277`,`E0609`) | 0/**101** (`E0277`,`E0599`,`E0609`) — pre-PIT-297 |
| `xs-testmod` leak | gen 0, leak **0** | gen 0, leak **1** | gen 0, leak **0** |

Every SOP-required reading reproduced: `xs-dead`/`xs-deadcoll` pristine **0**,
regressed **101** with the exact expected error codes, corrected **0** on a
tree containing `Compiler.hx = 57ee4997…` (hash-anchored,
`compiler-state.frozen.txt`). `xs-twoexc`'s 101-in-every-state is the
documented pre-existing probe defect, not a run failure.
**L5 satisfied:** the check is shown failing on the unfixed trees —
as-reviewed 101 for the PIT-248 pair, and frozen-57ee4997 (the board-anchored
"corrected" tree) 101 for `xs-crossmod` because that tree is pre-PIT-297
(zero class-first read sites in its `RustExpr`/`Compiler`).

**Deviation found (documented, not papered over):** the `xs-crossmod` README
row "frozen (pre earlier fix): 0/101 {E0277, E0433×2, E0599×2, E0609}" is not
reproducible from its stated 4-file compiler state
(`57ee4997…/985b5ad7…/2f2119d8…/cb18968c…`, per
`dc-warn/out/rust-payload-key-fix/evidence/frozen-hashes.txt`): on that exact
state with the identical toolchain (every seat uses the same nix-store
reflaxe 3.0.0) the observed set is {E0277, E0599, E0609} — the 101 + E0609
discriminator reproduce; the claimed E0433×2 + second E0599 do not. The
README's own audit raw logs for xs-crossmod are absent from
`rust-payload-key-fix/evidence/`, so the row's original input bytes/state are
not archivable. Invariant preserved and re-proven: xs-crossmod is 101/E0609 on
every pre-PIT-297 state (three re-measured here) and 0/0 only with the
class-first fix (H297 post, `993d7d10`). The README is archived verbatim; the
deviation is recorded in `EXPECTED-READINGS.md` § "Deviation found".

## 4. Does the repository's test runner collect the family? — NO (finding, not a change)

Empirical (R285, on the fixture-restored `e1c65975` tree):
- `haxe tests/haxe/compile.hxml` (the `test:haxe` build) → **rc=0, zero
  xs-/xt- mentions** in its output (`10-compile-hxml.log`): the build
  compiles `Main` + reachable classes only; the probes are referenced by
  nothing in `Main.hx`.
- `bun test tests/haxe/` → **rc=1 "Tests need .test/_test_/.spec"** (`11-bun-…`):
  bun's discovery finds no test files — the family has no `.ts`/`.js` files.

Static:
- `package.json`: `test` = `bun test tests/ packages/registry/tests/`
  (filename-based discovery); `test:haxe` = `haxe tests/haxe/compile.hxml &&
  bun out/haxe/tests.js`; `test:rust` = `cargo test` (root workspace only; the
  fixtures' generated crates are standalone `generated` packages, not
  workspace members). None references the family.
- Frozen chain-A runner (`out/integration-a3-evidence/exclusive-runner/run-exclusive.sh`
  + `p09-chainA-work/plan/option-c.plan`): plan-driven stages invoking exactly
  the `test*` scripts above; **0 xs-/xt- and 0 tests/haxe references** in the
  plan.
- CI (`.github/workflows/ci.yml`): runs the same `test*` scripts; no xs-/xt-
  references.

**What wiring would require (exactly, unimplemented by this row per the
board's 不自行实施 clause):** the discriminant plane is cargo-compile of the
generated trees, so the JS suite is the wrong host (importing the probes into
`Main.hx` would add no discriminating power). The minimal wiring is a
dedicated driver script (the archived `drivers/run-three-state.sh` is the
reference implementation) that: (a) ensures the fixtures are present
(`RESTORE.sh` or, if tracked, a bare checkout); (b) for each fixture runs
`haxe tests/haxe/<f>/gen/rust.hxml -D rust-output=<fresh dir>` +
`cargo build --offline` with fresh `CARGO_TARGET_DIR`; (c) asserts the
per-state expected (gen, cargo) rc matrix from `EXPECTED-READINGS.md`.
Exposure is then either (i) a new `package.json` script + a new stage line in
the option-C plan / `ci.yml`, or (ii) a standalone gate script. Note the
matrix is state-dependent (readings differ per compiler state), so the wiring
must pin the compiler state it asserts against (the hash anchors in this
archive exist for exactly that).

## 5. The three distinctions (parent's ask)

1. **Files in the repo** — NO at the base line (0 tracked at `e1c65975` /
   `5a8f19e6` / `arch/agent-guided-governance`); YES on `b18b99df`'s side
   branch (19/37). After this row: YES on `chore/archive-xs-fixture-family` —
   all 37 fixture files are tracked at the canonical `tests/haxe/` paths
   (the §9 commit); still NO on the base line until the row merges (the
   merge is the coordinator's call).
2. **Runner collects** — NO (no script, plan stage, or CI step; empirical
   probes above).
3. **Family discriminates** — YES: `xs-crossmod` is the sole fixture whose
   green/red flips exactly with the PIT-297 class-first fix (pre 101/E0609 —
   re-measured by this row on three pre-PIT-297 states — vs post 0/0, H297);
   `xs-dead`/`xs-deadcoll` discriminate the PIT-248 registration fix
   (re-measured 0→101→0).

## 6. VCS-inclusion judgment (judgment + impact, NOT implemented)

**Judgment: YES — the 37 fixture files should be version-controlled in the
repository (`tests/haxe/xs-*`, `tests/haxe/xt-*`), as a separate, explicitly
reviewed change.**

Rationale:
- **Reproducibility of signed evidence is a standing board requirement.**
  Three signed fixes (PIT-248, PIT-281, PIT-297) and their counters
  (`xs-twoexc` pre-existing defect, `xt-oneexc-nofault` negative control)
  rest on this family. Its bytes currently live in untracked worktree copies
  plus one side branch; any clone/checkout of the base line loses them, and
  the signed readings become unverifiable in principle (this row's
  `RESTORE.sh` + `compiler-states/` snapshots are the workaround — and the
  workaround itself had to be archived, which is the symptom).
- **The archive is not a substitute.** `dc-warn/out/` is an rclone-mounted
  evidence area, not a build input: no runner or CI can depend on it without
  an out-of-repo fetch step. The fixtures are small (37 files, ~40 KB of
  sources) and carry no secrets or build coupling — `git show`
  reproducibility is exactly what the family is for.
- **Precedent in-repo:** the PIT-297 seat already tracks 19 of the 37 files on
  `b18b99df`; the entry-gate evidence commits (`1704c3db`) established the
  evidence-package pattern. Tracking the family completes what that branch
  started, on the base line.
- **Impact of inclusion:** `bun test tests/` and `cargo test` still would not
  collect the family (filename discovery / workspace membership — §4), so
  inclusion alone changes no test outcome; it makes the bytes addressable by
  sha/commit, which the wiring in §4 then consumes. It also means
  `git ls-files 'tests/haxe/xs-*'` becomes non-empty, which `RESTORE.sh`'s
  doc comment currently cites — a trivial comment update, part of the same
  future change.
- **Executed, per coordinator directive (2026-09-30):** the row's SOP title
  demands reproducibility *from the repo*, and this project has paid twice
  for git-ignored evidence (PIT-251 → backfill `fafa27d6`; PIT-297's
  `xs-crossmod` living in one seat's worktree → PIT-329). The coordinator
  therefore directed that the family itself be version-controlled, which
  supersedes the row's 不自行实施 clause on this point. Done: see §9.

## 7. Verification performed for the SOP criteria

**① Fixtures archived verbatim with drivers and expected readings;
`FILES.sha256` passes from any cwd.**
37 fixture files + 2 drivers + 8 compiler-state snapshots + manifests + docs
archived under `xs-fixture-archive/`. `FILES.sha256` = absolute-path sha256
manifest of every file in the archive (itself excluded). `sha256sum -c
FILES.sha256` verified with exit 0 from ≥3 distinct cwds (workspace root,
`/tmp`, archive root) — see `xs-archive/evidence/13-files-sha256-*.log`.
(`RESTORE.sha256` is the relative-path fixture manifest for `sha256sum -c`
from the archive root / `RESTORE.sh`.)

**② `RESTORE.sh` restores onto a clean `e1c65975` checkout with byte-level
sha256 (measured rc); three-state re-run readings match the archive.**
`RESTORE.sh` on the clean detached `e1c65975` worktree: **rc=0,
wrote=37, verified=37** (`00-restore.log`); `--check` re-run rc=0
(`01-restore-check.log`); idempotent (second restore run `already-correct=37`).
Three-state re-run: all SOP readings reproduced (table in §3), compiler states
hash-anchored per transition, `Compiling generated` count = 1 per cargo run,
tree left clean (`12-final-git-status.txt`: only the untracked restored
fixtures). The corrected-0 state contained `Compiler.hx = 57ee4997…`
(`compiler-state.frozen.txt`).

**③ Per-fixture tracked status + why-not-reproducible + VCS judgment.**
§2 (provenance), §5 (the three distinctions), §6 (judgment + impact, not
implemented). Tracked status measured: 0 files at `e1c65975` / `5a8f19e6` /
`arch/agent-guided-governance`; 19 at `b18b99df`.

## 8. Out-of-scope / untouched (per the row's 不改 clause)

No compiler source changes (the run worktree's compiler files were swapped
from archived snapshots and restored to pristine `e1c65975` bytes at the end —
`12-final-git-status.txt` shows zero modified tracked files); no changes to
other fixtures, the frozen runner, `publication-staging/**`, or other
seats' worktrees. The xcheck scratch dirs at the workspace root
(`xs-xcheck-scratch-repo/` etc.) were left untouched. No test was weakened or
skipped; no expected reading was committed without observation. The only
deliberate in-tree addition is the fixture family itself at its canonical
`tests/haxe/` paths (and the archive tooling under
`docs/architecture/evidence/`), per the §9 directive — no test outcome
changes, because no runner collects the family (§4).

## 9. VCS inclusion — executed (coordinator directive, 2026-09-30)

**What is now tracked on `chore/archive-xs-fixture-family`:**
- `tests/haxe/{xs-dead,xs-deadcoll,xs-generic,xs-growth,xs-samples,xs-scope,
  xs-testmod,xs-twoexc,xs-twoexc-faultnames,xs-twoexc-swapped,xs-xmod,
  xs-crossmod,xt-classemit,xt-oneexc-nofault,xt-twoexc-emit,
  xt-twoexc-emit-rev}/` — the 37 fixture files, **byte-identical to the
  `dc-warn/out/xs-fixture-archive/` archive** (hash-verified against
  `RESTORE.sha256` after copy).
- `docs/architecture/evidence/xs-fixture-archive/` — the report (this file),
  `FILES.sha256`, `EXPECTED-READINGS.md`, `ARCHIVE-README.md` (the archive
  overview), `RESTORE.sh`, `RESTORE.sha256`, `drivers/{run-matrix.sh,
  run-three-state.sh}`, `compiler-states/` (8 .hx snapshots) and the full
  raw evidence logs (`evidence-raw/`, 136 files / ~115 KB).

**Location rationale (the choice the directive left to this row):** the
fixtures go at their **canonical `tests/haxe/<fixture>/` paths** rather than
under `docs/architecture/evidence/` because (a) every driver `rust.hxml`
addresses the fixtures by tree-relative path (`-cp tests/haxe/<fixture>`,
`Intercept.run([... 'tests/haxe/<fixture>']`), so the drivers run
verbatim from a repo checkout without any retargeting; (b) the PIT-297 seat
already tracks 19 of the 37 files at exactly these paths on `b18b99df` —
this continues that precedent instead of forking a second location; (c) the
§4 finding stands: placement under `tests/` changes no test outcome (bun's
filename discovery finds no `.test` files there, `compile.hxml` is
Main-reachable-only, `cargo test` is root-workspace-only, the frozen plan
references none of it) — so the canonical location costs nothing at runtime
and makes the bytes addressable by path and commit. `RESTORE.sh` remains
committed and useful: it installs/verifies the independent out-of-tree
archive copy (`dc-warn/out/xs-fixture-archive/`) into a tree.

**Members deliberately NOT committed, with reasons:**
- `dc-warn/out/xs-archive/scratch/` (~47 MB: generated crates + cargo
  `target/` dirs) — disposable build outputs, fully re-derivable by running
  `drivers/run-three-state.sh`; committing cargo target trees would bloat the
  repo with non-source bytes.
- The measurement worktrees (`xs-run-e1c65975` and the prior xcheck scratch
  repos at the workspace root) — live git worktrees, not content.
- The `dc-warn/out/xs-fixture-archive/` directory itself — it lives on the
  rclone mount and is git-ignored by design; its *content* is what is now
  tracked (fixtures at canonical paths, tooling under docs/evidence), so
  "reproducible from the repo" no longer depends on that mount.

**Verification of the tracked bytes:** after copying, `sha256sum -c
RESTORE.sha256` (run in the worktree against `tests/haxe/`) passes 37/37 —
i.e. the tracked fixtures are byte-identical to the archived copies, which
are themselves byte-identical to the cited sources (§2).
