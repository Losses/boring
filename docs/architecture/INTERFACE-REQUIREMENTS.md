# Architecture Contract

The classification (`PROBLEM-CLASSIFICATION.md`) clarifies "which category of failure belongs to whom"; this file clarifies
**what each end of an interface commits to** — that is, what a site must deliver under what conditions.

## Contract 1: Destination is passed in by composition (category D)

**Rule**: the conversion site must receive the **destination** (target type), and must not infer it from compiler instance state.

**Current facts** (verified; candidate tree `SwiftExpr.hx` line 7041):
- `currentReturnType` is an **instance field** of `SwiftExpr` (`:218`), written only at `:544`
  (`functionBody`, from the member's `TFun` return), cleared at `:563`.
- `functionLiteral` (`:2338-2345`) only saves/restores `currentFuncReturnsOptional`,
  and does **not rebind** `currentReturnType`.
- The correct value inside a lambda is **`f.t`** (`:2349` already uses it to print the closure header).

**Contract form**:
```
conversion-site(value, destination, fallback) -> text
where destination is provided by the composition to which the site belongs:
  - member body                  -> the member's return type
  - lambda body                  -> the lambda's return type (f.t)
  - inline block / anonymous helper -> that block's own result type (not the enclosing lambda's)
  - binding route                -> the type of the bound variable (v.t)
  - parameter route              -> the parameter type declared by the callee
```
**The last line is this session's lesson**: the `blockExpression` block has its own destination;
treating it as the lambda's return contract would **inject an incorrect conversion** (the P4 regression of `lambda-fix-xcheck`,
`mx/MXProbe.swift:19:12`, `cannot convert 'ReadOnlyArray<Int32>' to closure
result type 'TiqianArray<Int32>'`).

## Contract 2: nil-merge's intermediate destination is provided by composition (category C boundary × category D destination)

**Spec original** (`docs/compiler-policy-interfaces.md:171-173`, verbatim):
> "A nil-merge with a required final result passes an **optional intermediate
> destination** to the optional left operand's conversion."

**Landing**: the third input of `prepare(operand, destinationType, override)`
`destinationOptionalOverride` (`SwiftArrayBoundary.hx:173`).
- `override == null` ⇒ the planner rules by the destination's own optionality (the default context of the three REFUSED rows)
- `override == true` ⇒ the composition declares "an optional intermediate result is accepted here" ⇒ that cell becomes a conversion
  (`MapOptionalMutableArrayView` `:200-202` etc.)

**Contract boundary**: `override` is an **obligation of the composition**, not a property of the operand, nor an exemption.
The three REFUSED rows in `RECORD.md` are therefore qualified in the record as **PLANNER-CELL ONLY**
(CORRECTION 13).

## Contract 3: warnings count toward acceptance (category F)

**Binding standard**: `docs/specs/style/02-translator-implementation-standard.md`
- `:78` *"Generated code compiles **without warnings** on every target … A
  translation that produces a warning is an emitter defect **with the same
  severity as a translation that produces wrong output**."*
- `:80` *"…counts the warning lines in the target suite output that name files
  under the generated trees; **the count is zero**."*

**Corollaries (made and written down this session, TCN-156)**:
- warnings **count**; **baseline failures must be recorded, but are not exempt** (`work-plan:417`).
- ⇒ **a suite must be running**: no suite collecting ⇒ no count produced ⇒ the standard cannot be satisfied,
  only bypassed. **That gap has been wired up** (`9f26e1ef`): `ci.yml` adds a `collected-suite`
  job that runs the entry point `bun run test` on every run and reports the collected domain (303 files, 249 of which come
  from the generated tree `reference/ts/gen-tests`). The job blocks, with no `continue-on-error`;
  the baseline `1001 pass / 32 fail / 8 errors` is recorded in `BASELINE-FAILURES.md`, not yet settled.
- ⇒ the record's form must be "**known baseline failure + explicit PIN**", and must **not** be named "zero-diagnostics satisfied":
  the owner's ruling at `tests/swift-gap-boundary/gap-boundary.test.ts:44` is this contract's landing.

**Supplement (`t-muo92xms-s28t` ruling, `1a486ebd`; see `rulings/BUILD-PHASE-DIAGNOSTIC-RULING.md`):
"which tool is used" and "which diagnostics can be seen" must be stated separately.**
The main clause of `:78` is universal ("on every target"), but when enumerating tools it writes only *"the Swift type-checker"*.
That narrowing leaves a hole: **`swiftc -typecheck` does not run SILGen, and reports 0 in the baseline state**,
so for `Gap.swift:117`'s `will never be executed` it can **neither confirm nor refute**;
the only things that can actually see it are `-c` (including `-whole-module-optimization`) and `-o`.
⇒ **Ruling: build-phase diagnostics count toward `:78/:80`**. If only the "type checker" is recognized literally, "zero warnings" degenerates into
a **vacuous criterion** (every real emitter defect passes silently, while the downstream CI that compiles the binary still hits it).
**Counting discipline**: count by the `file:line:col: severity` **shape**, not `grep -c 'warning:'`
— Swift also prints caret/context lines, which turn 1 into 2 (PIT-336).
**Generalization to the same family**: for every target, ask whether the existing command is **blind** to the diagnostics it can report —
one same-family example this session is that `cargo check` and `cargo build` have different warning surfaces.

## Contract 4: the acceptance criterion for generated output must be able to observe the property under test

**Rule**: an acceptance check must **fail when that property is broken**.

**Three counterexamples this session** (same gap, three causes):
| Item | Why it cannot be observed |
|---|---|
| `branchBoundary` fixture | the two branches are equal length; the consumer only prints the length |
| missing-return shape | **`swiftc -typecheck` does not run SILGen, does not report "missing return"** |
| splice-type fix | the generated tree's pre/post are byte-for-byte identical (cannot distinguish "unchanged" from "changed correctly") |

**⇒ Landed criterion** (`LAYERED-VERIFICATION.md` will expand):
1. the assertion must be stricter than "not broken": e.g. `1:1:present` rather than `1:present`
2. **the shape stripped of `return` must use `swiftc -c`, not `-typecheck`**
3. splice-type changes must use a **discriminating backend** (deliberately taking the wrong branch / deliberately returning the wrong value) to prove it FAILs

## Contract 5: a fix must not change other categories' behavior

**Landing**: after a fix, regenerate with the **full driver set** and do a whole-tree comparison; **byte-for-byte identical after path normalization**
is a necessary condition. All four committed fixes satisfy it (W1: 19 drivers, only 2 lines of difference and those expected;
lambda: 19 drivers, empty diff).

**Limitation**: a whole-tree identical result **cannot** prove the fix correct, only that **nothing else was affected**;
"generation succeeded", "type check passed", and "runs correctly" are three different strengths and must be stated separately.

## Contract 6: a judgment may have only one source; what can be derived from facts must not be re-decided separately

**Rule**: when whether something "holds" affects the output, that judgment must have **only one authoritative source**.
If it can be **derived from facts that have already happened** (whether a file really was written, whether a declaration really was emitted),
it **must be derived**, and a second piece of code must not **independently** decide it again.

**Why**: when the criterion and the fact are **decided in parallel**, the two can disagree, and **disagreement is invisible in the passing state**.
This is the same family as Contract 4 but a different layer: Contract 4 says "the check must be able to observe the broken property",
this one says "**the criterion itself must not be decoupled from the fact it describes**".

**Measured (Rust target `state.shimsUsed`)**:
| Quantity | Value |
|---|---|
| Write sites (each believing "some shim is used") | **28 sites**, scattered across `RustDecl.hx` / `RustExpr.hx` / `RustImports.hx` |
| Read sites (deciding whether some resident is emitted) | **15 sites** |
| A contract specifying "which path must write" | **none** |

(Write-site distribution: `RustExpr.hx` 23, `RustImports.hx` 3, `RustDecl.hx` 2;
read-site distribution: `Compiler.hx` 13, `RustImports.hx` 1, `RustEmissionState.hx` 1.
Measured at `aceda352`, with the criterion being "line shape": left-hand assignment, subscript assignment, or `push|add|set|insert|remove|clear`.)

⇒ this global is **used with two meanings**: "the business referenced some extern" (intent layer) and
"whether some resident should write out `.rs`" (emission layer). **The two layers are not equivalent, and no one is responsible for guaranteeing equivalence.**
The artifact is that `runtime/mod.rs` declares a module that was never written out (`E0583`):
**declaration goes through one criterion, file emission goes through another, and the two write surfaces do not overlap.**

**Two repair routes, with different criteria**:
- **Add write sites**: each time an uncovered path is found, write the criterion again on that path
  (the one master added at the tail of `RustImports.requireType` is of this kind).
  Correctness is staked on "**write-site coverage being complete**"; and the number of write sites **cannot be exhaustively verified**, and degrades with each new path.
- **Derive from facts**: make the emission function **return whether it really wrote the file**, have the caller record it,
  and generate the declaration list **from that record** (this branch `94eace13`: `emitResidentModule` returns `Bool`
  ⇒ `emittedResidentMods` ⇒ `runtimeMods`). Correctness is staked on "**declarations coming from facts**",
  **verifiable and not degrading with new paths**.

**⇒ Landed criterion**:
1. when "two pieces of code make the same judgment" appears, first distinguish **same-layer duplication** from **write side / read side**;
   when both sides are needed, **specify which side is the correctness source**.
2. ask "**is there a contract specifying who must write**". If the answer is "none + far more write sites than read sites",
   the real defect is **not a missing merge**, but the criterion lacking a single source.
3. verify whether the derivation is **self-sufficient**: if, without lighting up those write sites, the invariant still holds by derivation alone,
   the derivation stands independently; **if it holds only when a certain write site fires**, correctness still depends on
   uncoordinated write sites; **this itself is a finding to report**, even if the code is syntactically correct.

**Ablation measurement (postscript, `aceda352`)**: disable the entire write site master added at the tail of
`RustImports.requireType`, then regenerate `examples/rust.hxml`.

| Observation | Result |
|---|---|
| generation rc | 0 |
| generated-tree difference (excluding cargo's `target/`) | **zero**: 545 `.rs` files identical on both sides |
| `runtime/mod.rs` | **byte-for-byte identical** |
| declaration / reference | 15 / 15, violations = **0** |
| `cargo check` | rc=0, error count 0 |

⇒ that write site is **completely inert** on this corpus, so "zero violations" **proves neither self-sufficiency
nor that the write site is necessary**. The reason is that the two paths evaluate the same set of externs: the emission gate
at `Compiler.hx:862` itself reads `state.shimsUsed.exists(externModule)` (via `externsOf`),
using the same `(isResident, externsOf)` pair as the write site, and is necessarily consistent by construction.

To truly decide self-sufficiency, one needs a case "touched only by `requireType`, whose importer does not trigger
extern lighting"; until then this item is recorded as **open**, and must not be written as "self-sufficiency verified".

## Open

- **`switchExpression`'s destination**: Condition 3 requires giving it an explicit destination parameter
  (binding route `v.t`, parameter route using the callee's parameter), with `sw.t` only as the fallback when there is no contract.
  The implementation lane is running (`out/switchexpr-destination`). **That lane must report "output unchanged" as a
  legitimate result**, and must not manufacture a behavior difference to make the modification look necessary.
- **single-return fast path** (`functionLiteralInner`) has never applied boundary conversion:
  the P1 probe of `lambda-fix-xcheck` fails on two trees that are byte-for-byte identical. A residual gap.
- **J-category migration**'s contract is undefined.
