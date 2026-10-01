# Expected readings — xs-* / xt-* fixture family

Reading convention (same as the PIT-248 / PIT-297 seats): each fixture is
driven by its own `gen/rust.hxml` (`haxe`, cwd = tree root), which generates a
standalone Rust crate; the discriminant is then `cargo build --offline` in the
generated tree with a fresh `CARGO_TARGET_DIR`.
`gen` = haxe exit code, `cargo` = cargo exit code (101 = rustc compilation
failure of the generated tree). "stderr key lines" = the error codes the cargo
stderr must contain in the failing states.

Provenance tags:
- **H248** = historical PIT-248 three-state run (`dc-warn/out/rust-regression-fix/`,
  `stage-summary.tsv`, `xs-twoexc-errors.txt`, `xs-testmod-leak.txt`).
- **H297** = historical PIT-297 run (`dc-warn/out/rust-module-keyed/`,
  `evidence/raw/`; lineage 05e375b2, branch `fix/rust-module-keyed-read-sites`).
- **R285** = re-measured by THIS row (t-munejtq3-mj9x) on 2026-09-30 on a clean
  `e1c65975` checkout with the restored archive fixtures; raw logs in
  `dc-warn/out/xs-archive/evidence/` (this row's measurements are authoritative
  wherever they exist; no expected value below is unobserved).

Compiler states (all four rustcompiler files hash-anchored per state in the
evidence; the board's "corrected" anchor pins only `Compiler.hx = 57ee4997…`):
- **pristine** = `e1c65975` bytes.
- **as-reviewed** = PIT-248 negative-control state = `compiler-states/as-reviewed/`
  (Compiler `24f79c27…`, RustDecl `985b5ad7…`, RustEmissionState `2f2119d8…`,
  RustExpr `cb18968c…`); PRE-PIT-281 (zero `exceptionPayloadEnums` sites).
- **frozen-57ee4997** = `compiler-states/frozen-57ee4997/` — the shared
  coordination tree's working compiler at archive time (Compiler `57ee4997…`,
  RustDecl `985b5ad7…`, RustEmissionState `2f2119d8…`, RustExpr `235d5a36…`);
  the board-anchored corrected state; PRE-PIT-297.
- **frozen-audit** = the exact 4-file state of the rust-payload-key-fix audit
  (`57ee4997…/985b5ad7…/2f2119d8…/cb18968c…`, per
  `dc-warn/out/rust-payload-key-fix/evidence/frozen-hashes.txt`) — reconstructable
  from this archive as frozen-57ee4997 `Compiler.hx` + as-reviewed other three.
  PRE-PIT-297. (Used to re-verify the `xs-crossmod` README matrix row.)

## PIT-248 core (this row's required re-measurement) — ALL RE-MEASURED (R285)

| fixture | state | gen | cargo | stderr key lines (failing states) — OBSERVED R285 | also H248 |
|---|---|---|---|---|---|
| `xs-dead` | pristine | 0 | **0** | — | ✓ (0/0) |
| `xs-dead` | as-reviewed | 0 | **101** | `E0004` — `non-exhaustive patterns: DFault::DExceptionFault(_) not covered` | ✓ (101, same E0004) |
| `xs-dead` | frozen-57ee4997 | 0 | **0** | — | ✓ (H248 measured the `src-fixed` state; generated tree byte-identical to pristine per H248 `tree-compare.tsv`) |
| `xs-deadcoll` | pristine | 0 | **0** | — | ✓ (0/0) |
| `xs-deadcoll` | as-reviewed | 0 | **101** | `E0428` — `the name CExceptionFault is defined multiple times` | ✓ (101, same E0428) |
| `xs-deadcoll` | frozen-57ee4997 | 0 | **0** | — | ✓ (byte-identical to pristine, per H248) |
| `xs-twoexc` | pristine | 0 | **101** | `E0277`×1 + `E0433`×2 — pre-existing probe defect, red in every state | ✓ (same code set) |
| `xs-twoexc` | as-reviewed | 0 | **101** | `E0277`×1 + `E0308`×3 (leak-4 shape) | ✓ (same code set) |
| `xs-twoexc` | frozen-57ee4997 | 0 | **101** | `E0277`×1 + `E0308`×1 + `E0433`×1 | H248's `src-fixed` state: same code set (`E0277`+`E0433`(E1)+`E0308`×1) |
| `xs-testmod` | pristine | 0 | (gen-only) | leak marker `ValueExceptionFault(Box<` in generated `boring/value_exception.rs` = **0** | ✓ (0) |
| `xs-testmod` | as-reviewed | 0 | (gen-only) | same marker = **1** (leak 3) | ✓ (1) |
| `xs-testmod` | frozen-57ee4997 | 0 | (gen-only) | same marker = **0** | ✓ (0) |

All 12 readings matched the H248 expectations; every cargo run showed exactly
one `Compiling generated` line (cache-replay guard, `compiling-count.txt`).

## PIT-248 guard fixtures (gen-only in H248; gen=0 in all three states)

`xs-generic`, `xs-growth`, `xs-samples`, `xs-scope`, `xs-xmod` — gen=0 in
pristine/as-reviewed/fixed per H248 `stage-summary.tsv`. Not re-run in this row
(the row's 验证 clause requires the `xs-dead`/`xs-deadcoll` core only); their
drivers are archived so the readings remain re-derivable.
`xs-scope/expected.txt` pins the run-comparison expectation `detect=0`.

## PIT-297 sub-family (discriminates the module-keyed read-site fix)

H297 states: **pre** = `b18b99df` state on the 05e375b2 lineage (Compiler
`46d8fff4…`, PIT-281 applied, pre-PIT-297); **post** = pre + `993d7d10`
(class-first read sites).

| fixture | H297 pre | H297 post | stderr key lines (failing) — H297 raw | R285 re-measurement |
|---|---|---|---|---|
| `xs-crossmod` | 0 / **101** | 0 / **0** | pre: `E0609` — no field `fault` on type `F1Fault` (the sole discriminator) | **pre side re-verified on the e1c65975 lineage, 3 states (all pre-PIT-297):** as-reviewed 0/101 {E0277, E0609}; frozen-57ee4997 0/101 {E0277, E0599, E0609}; frozen-audit 0/101 {E0277, E0599, E0609} — discriminator E0609 present in all three; the enum named in E0609 is `F2Fault` on the e1c65975 lineage (last-scanned-wins resolves E1's read sites against the second module's enum) vs `F1Fault` on the 05e375b2 lineage |
| `xt-twoexc-emit-rev` | 0 / 0 | 0 / 0 | — (guard) | not re-run |
| `xs-twoexc-faultnames` | 0 / 0 | 0 / 0 | — (guard) | not re-run |
| `xt-classemit` | 0 / 0 | 0 / 0 | — (guard) | not re-run |
| `xt-twoexc-emit` | 0 / 0 | 0 / 0 | — (guard; generated tree byte-identical pre/post) | not re-run |
| `xs-twoexc-swapped` | 0 / **101** | 0 / **101** | `E0308`×2 — converges with `xs-twoexc`'s residual; the fix deliberately does not touch the separate `endsWith(…,"Fault")` gate | not re-run |
| `xs-twoexc` | 0 / **101** | 0 / **101** | `E0308`×2 (05e375b2-lineage reading; the e1c65975-lineage reading of the same fixture is the `E0277`-family one in the table above) | re-run all three states: see PIT-248 core table |
| `xt-oneexc-nofault` | 0 / **101** | 0 / **101** | negative control: no `Fault`-suffixed payload enum → stays red by design (same `endsWith` root cause) | not re-run |

### Deviation found and documented (R285)

The `xs-crossmod/README.md` matrix row "frozen (pre earlier fix): 0/101
{E0277, E0433×2, E0599×2, E0609}" is **not reproducible** from its stated
compiler state: the R285 re-measurement on the exact audit 4-file state
(frozen-audit, hash-anchored, identical haxe 4.3.7 / cargo 1.98.0 /
reflaxe 3.0.0 — every seat used the same nix-store reflaxe) yields
**{E0277, E0599×1, E0609}**: 101 and the E0609 discriminator reproduce; the
claimed E0433×2 + second E0599 do not. Both RustExpr variants
(`cb18968c…`, `235d5a36…`) were tested — same 3-error set. The deviation
therefore sits in the un-archived byte/state combination used when that row was
written (the README's own audit raw logs for xs-crossmod are absent from
`dc-warn/out/rust-payload-key-fix/evidence/`). Invariant preserved and
re-proven: **xs-crossmod fails (101, E0609) on every pre-PIT-297 state and the
sole fix that turns it green is the class-first read-site change (H297 post
= 0/0).** The README is archived verbatim (fixture artifact); the deviation is
recorded here and in REPORT.md, not "fixed" in the fixture bytes.

## What "reproducible from this archive" means, precisely

1. **Files in the repo** — NO at the base line (0 tracked at `e1c65975`, at
   the base tip `5a8f19e6`, and on `arch/agent-guided-governance`; only
   `b18b99df`'s branch carries 19 of the 37). After this row's §9 commit
   (coordinator directive 2026-09-30): all 37 files are tracked at the
   canonical `tests/haxe/` paths on `chore/archive-xs-fixture-family`;
   `sha256sum -c RESTORE.sha256` against `tests/haxe/` passes 37/37 there.
2. **Runner collects them** — NO (no `test*` script, frozen chain-A plan stage,
   or CI step references the family; empirical probes
   `dc-warn/out/xs-archive/evidence/10-*`, `11-*`: `haxe tests/haxe/compile.hxml`
   rc=0 with 0 xs-/xt- mentions; `bun test tests/haxe/` rc=1 "no tests found").
   What wiring requires is spelled out in REPORT.md.
3. **Family discriminates the PIT-297 fix** — YES for `xs-crossmod`: re-verified
   by this row on three pre-PIT-297 compiler states (all 101, E0609 present)
   against H297's post 0/0.
