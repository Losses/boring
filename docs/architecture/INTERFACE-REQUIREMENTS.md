# Architecture Contract

The classification (`PROBLEM-CLASSIFICATION.md`) clarifies "which class of failure belongs to whom"; this file clarifies
**what each side of an interface commits to**, i.e., what a given site must deliver under what conditions.

## Contract 1: Destination Is Passed In by the Composition (Class D)

**Rule**: a conversion site must be given its **destination** (target type) and must not infer it from compiler-instance state.

**Current facts** (verified, candidate tree `SwiftExpr.hx` 7041 lines):
- `currentReturnType` is an **instance field** of `SwiftExpr` (`:218`), written only at `:544`
  (`functionBody`, from the member's `TFun` return), cleared at `:563`.
- `functionLiteral` (`:2338-2345`) only saves/restores `currentFuncReturnsOptional`,
  and does **not rebind** `currentReturnType`.
- The correct value inside a lambda is **`f.t`** (`:2349` already uses it to print the closure header).

**Contract form**:
```
conversionSite(value, destination, fallback) -> text
where destination is provided by the composition the site belongs to:
  - member body       -> the member's return type
  - lambda body       -> the lambda's return type (f.t)
  - inline block / anonymous helper -> the block's own result type (not the outer lambda's)
  - binding route     -> the bound variable's type (v.t)
  - parameter route   -> the callee-declared parameter type
```
**The last item is this session's lesson**: `blockExpression`'s block has its own destination;
treating it as the lambda's return contract will **inject a wrong conversion** (P4 regression from `lambda-fix-xcheck`,
`mx/MXProbe.swift:19:12`, `cannot convert 'ReadOnlyArray<Int32>' to closure
result type 'TiqianArray<Int32>'`).

## Contract 2: nil-merge's Intermediate Destination Is Provided by the Composition (Class C Boundary × Class D Destination)

**Specification source** (`docs/compiler-policy-interfaces.md:171-173`, verbatim):
> "A nil-merge with a required final result passes an **optional intermediate
> destination** to the optional left operand's conversion."

**Implementation**: the third input of `prepare(operand, destinationType, override)`
`destinationOptionalOverride` (`SwiftArrayBoundary.hx:173`).
- `override == null` ⇒ the planner adjudicates based on the destination's own optionality (default context for the three REFUSED rows)
- `override == true` ⇒ the composition declares "optional intermediate result accepted here" ⇒ that cell becomes a conversion
  (`MapOptionalMutableArrayView` `:200-202` etc.)

**Contract boundary**: `override` is an **obligation of the composition**, not a property of the operand, nor an exemption.
`RECORD.md`'s three REFUSED rows are therefore scoped in the record as **PLANNER-CELL ONLY**
(CORRECTION 13).

## Contract 3: Warnings Count Toward Acceptance (Class F)

**Binding standard**: `docs/specs/style/02-translator-implementation-standard.md`
- `:78` *"Generated code compiles **without warnings** on every target … A
  translation that produces a warning is an emitter defect **with the same
  severity as a translation that produces wrong output**."*
- `:80` *"…counts the warning lines in the target suite output that name files
  under the generated trees; **the count is zero**."*

**Corollaries (arrived at and recorded in this session, TCN-156)**:
- warnings **count**; **baseline failures must be recorded but are not exempted** (`work-plan:417`).
- ⇒ **a suite must be running**: no suite collecting ⇒ no count produced ⇒ the standard cannot be met,
  merely bypassed. **This gap has been wired up** (`9f26e1ef`): `ci.yml` gained a `collected-suite`
  job, which runs `bun run test` on every invocation and reports the collected domain (303 files, 249 of them from
  the generated tree `reference/ts/gen-tests`). The job blocks, no `continue-on-error`;
  baseline `1001 pass / 32 fail / 8 errors` recorded in `BASELINE-FAILURES.md`, not yet settled.
- ⇒ the recorded form must be "**known baseline failure + explicit PIN**", and must **not** be named "zero diagnostics satisfied":
  the owner ruling at `tests/swift-gap-boundary/gap-boundary.test.ts:44` is this contract's implementation.

**Addendum (`t-muo92xms-s28t` ruling, `1a486ebd`; see `rulings/BUILD-PHASE-DIAGNOSTIC-RULING.md`):
"Which tool to use" and "which class of diagnostics it can see" must be specified separately.**
`:78`'s main clause is universal ("on every target"), but when enumerating tools it only writes *"the Swift type-checker"*.
This narrowing leaves a hole: **`swiftc -typecheck` does not run SILGen, and reports 0 even in the baseline state**,
so for `Gap.swift:117`'s `will never be executed`, it can **neither confirm nor refute**;
the only modes that actually see it are `-c` (including `-whole-module-optimization`) and `-o`.
⇒ **Ruling: build-phase diagnostics count for `:78/:80`**. Taking "type-checker" literally degrades "zero warnings" to
**an empty criterion** (real emitter defects all silently pass, while downstream CI compiling binaries will still hit them).
**Counting discipline**: count by the `file:line:col: severity` **shape**, not with `grep -c 'warning:'`
— Swift also prints caret/context lines, which can double-count 1 occurrence as 2 (PIT-336).
**Generalizing**: for every target, ask "does the current command **fail to see** diagnostics it can report" —
a sibling example from this session is that `cargo check` and `cargo build` have different warning surfaces.

## Contract 4: Acceptance Criteria for Generated Output Must Be Able to Observe the Property Under Test

**Rule**: an acceptance check must **fail when that property is violated**.

**Three counterexamples from this session** (same gap, three causes):
| Item | Why it is not observable |
|---|---|
| `branchBoundary` fixture | both branches are equal-length, and the consumer only prints length |
| missing-return shape | **`swiftc -typecheck` does not run SILGen, does not report "missing return"** |
| splicing-type fix | generated tree pre/post identical byte-for-byte (cannot distinguish "unchanged" from "correctly changed") |

**⇒ Implemented criteria** (`LAYERED-VERIFICATION.md` will elaborate):
1. assertions must be stricter than "not broken": e.g., `1:1:present` rather than `1:present`
2. **the return-stripped shape must use `swiftc -c`, not `-typecheck`**
3. splicing-type changes must use a **discriminative backend** (deliberately take the wrong branch / deliberately return a wrong value) to prove it would FAIL

## Contract 5: A Fix Must Not Change Behavior of Other Classes

**Implementation**: after a fix, regenerate against the **full driver set** and perform a whole-tree comparison; **path-normalized byte-for-byte identity**
is a necessary condition. Four committed fixes all satisfy it (W1: 19 drivers, only 2 lines of diff and expected;
lambda: 19 drivers, diff is empty).

**Limitation**: whole-tree identity does **not** prove the fix is correct, only that it did **not affect other areas**;
"generation succeeded", "type-check passed", "run correctly" are three different strengths and must be stated separately.

## Contract 6: A Judgment May Have Only One Source; What Can Be Derived from Facts Must Not Be Independently Decided

**Rule**: when whether something "holds" affects output, that judgment must have **exactly one authoritative source**.
If it can be **derived from facts that have already occurred** (whether a file was actually written, whether a declaration was actually emitted),
then it **must be derived**; a second site must not **independently** decide it again.

**Why**: when criterion and fact are decided **in parallel**, they can diverge — and **divergence is invisible in the passing state**.
This is the same family as Contract 4 but at a different layer: Contract 4 says "the check must be able to observe the violated property",
this one says "**the criterion itself must not be decoupled from the facts it describes**".

**Empirical finding (Rust target `state.shimsUsed`)**:
| Quantity | Value |
|---|---|
| Write sites (each asserting "some shim was used") | **28 sites**, scattered across `RustDecl.hx` / `RustExpr.hx` / `RustImports.hx` |
| Read sites (deciding whether a resident should be emitted) | **12 sites** |
| Contract specifying "which path must write" | **none** |

⇒ this global is used with **two different meanings**: "some business code referenced an extern" (intent layer) and
"whether some resident should be written out as `.rs`" (emission layer). **The two layers are not equivalent, and no one is responsible for ensuring equivalence.**
The product is `runtime/mod.rs` declaring a module that was never written out (`E0583`):
**declarations follow one criterion, file emission follows another, and their write surfaces do not overlap.**

**Two repair routes, with different criteria**:
- **Add write sites**: for every uncovered path discovered, add another criterion write on that path
  (the one added at the tail of `RustImports.requireType` on master is of this kind).
  correctness is staked on "**complete write-site coverage**"; but write-site count **cannot be exhaustively verified**, and degrades with each new path.
- **Derive from facts**: make the emission function **return whether it actually wrote the file**, have the caller record it,
  and **generate the declaration list from that record** (this branch `94eace13`: `emitResidentModule` returns `Bool`
  ⇒ `emittedResidentMods` ⇒ `runtimeMods`). Correctness is staked on "**declarations come from facts**",
  **verifiable and does not degrade with new paths**.

**⇒ Implemented criteria**:
1. When "two sites make the same judgment", first distinguish whether it is **same-layer duplication** or **write-side/read-side**;
   when both sides are needed, **one side must be designated the correctness source**.
2. Ask "**is there a contract specifying who must write**". If the answer is "none + write sites far outnumber read sites",
   the real defect is **not a missing merge**, but the criterion's lack of a unique source.
3. Verify whether the derivation is **self-sufficient**: if, without activating those write sites, the invariant still holds by derivation alone,
   then the derivation stands independently; **if it only holds when a specific write site fires**, then correctness still depends on
   uncoordinated write sites; **this itself is a finding to report**, even if the code is syntactically correct.

## Open

- **`switchExpression`'s destination**: Condition 3 requires giving it an explicit destination parameter
  (binding route uses `v.t`, parameter route uses callee parameters), with `sw.t` only as a fallback when there is no contract.
  The implementation seat is running (`out/switchexpr-destination`). **That seat must report "output unchanged" as
  a valid result** and must not fabricate behavioral differences to make the change appear necessary.
- **Single-return fast path** (`functionLiteralInner`) has never applied boundary conversion:
  `lambda-fix-xcheck`'s P1 probe is byte-for-byte identical across both trees and both fail. This is a residual gap.
- **Class J migration**'s contract is undefined.