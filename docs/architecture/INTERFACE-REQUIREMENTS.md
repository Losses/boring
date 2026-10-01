# Architecture Contract

Classification (`PROBLEM-CLASSIFICATION.md`) makes clear "which class of failure belongs to whom"; this file makes clear
**what each side of the interface promises**, i.e.: what a site must hand over under what conditions.

## Contract 1: destination passed in by composition (Class D)

**Rule**: a conversion site must be handed the **destination** (target type) and must not infer it from compiler-instance state.

**Current facts** (verified, candidate tree `SwiftExpr.hx` 7041 lines):
- `currentReturnType` is an **instance field** of `SwiftExpr` (`:218`), its only write at `:544`
  (`functionBody`, from a member's `TFun` return), cleared at `:563`.
- `functionLiteral` (`:2338-2345`) only saves/restores `currentFuncReturnsOptional`,
  and does **not rebind** `currentReturnType`.
- The correct value inside a lambda is **`f.t`** (`:2349` already uses it to print the closure header).

**Contract form**:
```
conversion-site(value, destination, fallback) -> text
where destination is supplied by the composition the site belongs to:
  - member body     -> the member's return type
  - lambda body     -> the lambda's return type (f.t)
  - inline block / anonymous helper -> that block's own result type (not the outer lambda's)
  - binding route   -> the bound variable's type (v.t)
  - argument route  -> the callee-declared parameter type
```
**The last line is this session's lesson**: `blockExpression`'s block has its own destination;
treating it as the lambda's return contract **injects a wrong conversion** (the P4 regression of `lambda-fix-xcheck`,
`mx/MXProbe.swift:19:12`, `cannot convert 'ReadOnlyArray<Int32>' to closure
result type 'TiqianArray<Int32>'`).

## Contract 2: nil-merge's intermediate destination supplied by composition (Class C boundary × Class D destination)

**Spec original text** (`docs/compiler-policy-interfaces.md:171-173`, verbatim):
> "A nil-merge with a required final result passes an **optional intermediate
> destination** to the optional left operand's conversion."

**Landing**: the third input of `prepare(operand, destinationType, override)`,
`destinationOptionalOverride` (`SwiftArrayBoundary.hx:173`).
- `override == null` ⇒ the planner adjudicates by the destination's own optionality (the default context of the three REFUSED rows)
- `override == true` ⇒ the composition declares "an optional intermediate result is accepted here" ⇒ that cell turns into a conversion
  (`MapOptionalMutableArrayView` `:200-202` etc.)

**Contract boundary**: `override` is a **composition obligation**, not an operand property and not an exemption.
The three REFUSED rows of `RECORD.md` are therefore qualified in the record as **PLANNER-CELL ONLY**
(CORRECTION 13).

## Contract 3: warnings count toward acceptance (Class F)

**Normative standard**: `docs/specs/style/02-translator-implementation-standard.md`
- `:78` *"Generated code compiles **without warnings** on every target … A
  translation that produces a warning is an emitter defect **with the same
  severity as a translation that produces wrong output**."*
- `:80` *"…counts the warning lines in the target suite output that name files
  under the generated trees; **the count is zero**."*

**Corollaries (made and written down in this session, TCN-156)**:
- warnings **count**; **baseline failures must be recorded, but not exempted** (`work-plan:417`).
- ⇒ **a suite must be running**: no suite collection ⇒ no count is produced ⇒ the standard cannot be satisfied,
  only bypassed. **That gap is now wired up** (`9f26e1ef`): `ci.yml` adds a `collected-suite`
  job that runs the entry `bun run test` on every run and reports the collected domain (303 files, of which 249 come from
  the generated tree `reference/ts/gen-tests`). That job blocks, with no `continue-on-error`;
  the baseline `1001 pass / 32 fail / 8 errors` is recorded in `BASELINE-FAILURES.md`, not yet discharged.
- ⇒ the record's form must be "**known baseline failure + explicit PIN**", and must **not** be named "zero-diagnostic satisfaction":
  the owner ruling at `tests/swift-gap-boundary/gap-boundary.test.ts:44` is this contract's landing.

**Supplement (`t-muo92xms-s28t` ruling, `1a486ebd`; see `rulings/BUILD-PHASE-DIAGNOSTIC-RULING.md`):
"which tool is used" and "which class of diagnostics is visible" must be stated separately.**
The main clause of `:78` is universal ("on every target"), but when enumerating tools it only writes *"the Swift type-checker"*.
That narrowing leaves a hole: **`swiftc -typecheck` does not run SILGen, and reports 0 at baseline too**,
so it **can neither confirm nor falsify** the `will never be executed` on `Gap.swift:117`;
the only things that can actually see it are `-c` (including `-whole-module-optimization`) and `-o`.
⇒ **Ruling: build-phase diagnostics count toward `:78/:80`**. If one literally recognizes only "the type-checker", "zero warnings" degrades into
**an empty criterion** (real emitter defects all pass silently, while the downstream CI that compiles the binary will still hit it).
**Counting discipline**: count by the **shape** `file:line:col: severity`, do not use `grep -c 'warning:'`
— Swift also prints caret/context lines, which would count 1 as 2 (PIT-336).
**Same-family generalization**: for every target, ask "does the existing command **not see** the diagnostics it can report" —
one same-family example from this session is that `cargo check` and `cargo build` have different warning surfaces.

## Contract 4: acceptance criteria for generated output must be able to observe the property under test

**Rule**: an acceptance check must **fail when the property is violated**.

**Three counterexamples in this session** (the same gap, three causes):
| Item | Why it is unobservable |
|---|---|
| `branchBoundary` fixture | the two branches are equal-length, and the consumer only prints the length |
| missing-return form | **`swiftc -typecheck` does not run SILGen and does not report "missing return"** |
| splice-type fix | the generated tree pre/post are byte-identical (cannot distinguish "not changed" from "changed correctly") |

**⇒ Landed criteria** (`LAYERED-VERIFICATION.md` will expand):
1. assertions must be stricter than "not broken": e.g. `1:1:present` rather than `1:present`
2. **the `return`-stripped form must use `swiftc -c`, not `-typecheck`**
3. splice-type changes must use a **discriminating backend** (deliberately take the wrong branch / deliberately return a wrong value) to prove it FAILs

## Contract 5: a fix must not change the behavior of other classes

**Landing approach**: after the fix, regenerate over the **full driver set** and diff the whole tree; **byte-identical after path normalization**
is a necessary condition. All four committed fixes satisfy it (W1: 19 drivers, only 2 lines of difference and expected;
lambda: 19 drivers, diff empty).

**Limit**: whole-tree identity **cannot** prove the fix is correct, only that it **did not ripple elsewhere**;
"generation succeeds", "type-check passes", and "runs correctly" are three different strengths and must be stated separately.

## Contract 6: a judgment can have only one source; what can be derived from facts must not be judged separately

**Rule**: when whether something "holds" affects the output, that judgment must have **a single authoritative source**.
If it can be **derived from facts that have already happened** (whether the file was really written, whether the declaration was really emitted),
then it **must be derived**, and a second piece of code must not judge it again **independently**.

**Why**: when the criterion and the fact are judged **in parallel**, the two can disagree, and **a disagreement is invisible in the passing state**.
This is the same family as Contract 4 but a different layer: Contract 4 says "the check must be able to observe the violated property",
this one says "**the criterion itself must not detach from the fact it describes**".

**Measurement (Rust target `state.shimsUsed`)**:
| Quantity | Value |
|---|---|
| Write sites (each thinks "some shim is used") | **28 sites**, scattered across `RustDecl.hx` / `RustExpr.hx` / `RustImports.hx` |
| Read sites (decide from this whether some resident is emitted) | **15 sites** |
| A contract stipulating "which path must write" | **none** |

(Write-site distribution: `RustExpr.hx` 23, `RustImports.hx` 3, `RustDecl.hx` 2;
read-site distribution: `Compiler.hx` 13, `RustImports.hx` 1, `RustEmissionState.hx` 1.
Measured at `aceda352`, with the criterion being "line shape": left-side assignment, subscript assignment, or `push|add|set|insert|remove|clear`.)

⇒ This global is used as **two meanings**: "business referenced some extern" (intent layer) and
"whether some resident should be written out to `.rs`" (emission layer). **The two layers are not equivalent, and no one is responsible for guaranteeing equivalence.**
The product is that `runtime/mod.rs` declares a module that was never written out (`E0583`):
**the declaration goes by one criterion and file emission by another, and the two write surfaces do not overlap.**

**Two repair routes, different criteria**:
- **Fill in write sites**: for each uncovered path found, write the criterion once more on that path
  (the one master adds at the tail of `RustImports.requireType` is of this kind).
  Correctness is staked on "**write-site coverage is complete**"; but the number of write sites **cannot be exhaustively verified**, and a new path immediately degrades it.
- **Derive from facts**: make the emission function **return whether it really wrote the file**, recorded by the caller,
  and generate the declaration list **from that record** (this branch `94eace13`: `emitResidentModule` returns `Bool`
  ⇒ `emittedResidentMods` ⇒ `runtimeMods`). Correctness is staked on "**declarations come from facts**",
  **verifiable and not degraded by new paths**.

**⇒ Landed criteria**:
1. When "two pieces of code make the same judgment" appears, first distinguish **same-layer duplication** from **write-side/read-side**;
   if both sides are needed, **one must specify which side is the source of correctness**.
2. Ask "**is there a contract stipulating who must write**". If the answer is "no + write sites far outnumber read sites",
   the real defect is **not a missing merge** but a criterion lacking a single source.
3. Verify whether the derivation is **self-sufficient**: if, without lighting those write sites, the invariant still holds by derivation alone,
   then the derivation stands independently; **if it holds only when some write site fires**, then correctness still depends on
   uncoordinated write sites; **this itself is a finding to report**, even if the code is syntactically correct.

**Ablation measurement (postscript, `aceda352`)**: disable the whole write-site block that master has at the tail of `RustImports.requireType`
and regenerate `examples/rust.hxml`.

| Observation | Result |
|---|---|
| generation rc | 0 |
| generated-tree diff (excluding cargo's `target/`) | **zero**: 545 `.rs` files identical on both sides |
| `runtime/mod.rs` | **byte-identical** |
| declarations/references | 15 / 15, violations = **0** |
| `cargo check` | rc=0, error count 0 |

⇒ That write site is **completely inert** on this corpus, so "zero violations" **neither proves the derivation is self-sufficient
nor proves the write site is necessary**. The reason is that the two paths evaluate the same set of externs: the emission gate at `Compiler.hx:862`
itself reads `state.shimsUsed.exists(externModule)` (via `externsOf`),
using the same pair `(isResident, externsOf)` as the write site, so by construction they must agree.

To truly determine self-sufficiency, one needs a case "touched only by `requireType`, whose importers do not trigger
extern lighting"; until then this item is recorded as **open**, and must not be written as "self-sufficiency verified".

**Applicability boundary of this rule (postscript, measured from the re-verification at `9081d0d0`)**: Contract 6 requires the criterion to derive from
facts, but **"a derived field" does not equal "can vouch for each other"**. Within the same record,
`stdoutAvailable` derives from whether the host outcome's stream object exists (`ChildEvidence.hx:439`),
`stdoutBytes` derives from the length of the final written-to-disk buffer (:505), the two have **different sources**:
among 1005 records of a healthy tree, 236 are simultaneously `available=true` and `bytes=0`.
Therefore one must **not** use the available flag to verify "the stream was indeed preserved", nor take
available/bytes consistency as an invariant assertion — it is a normal shape in this system.

Likewise, **a mutation test must be done before weakening an assertion**: after relaxing `stdout>0 && stderr>0` to
`stdout+stderr>0`, a real regression "silently drops stderr on the cap path"
passes the whole suite with rc=0 all green (reverting to the old assertion gives rc=1 and catches it). The basis for relaxing can only be
"what the object under test guarantees", not "it no longer fails intermittently after the change".

## Open

- **Destination of `switchExpression`**: condition 3 requires giving it an explicit destination parameter
  (binding route `v.t`, argument route uses the callee's parameter), `sw.t` only as a fallback when there is no contract.
  The implementation bench is running (`out/switchexpr-destination`). **That bench must report "output unchanged" as
  a legitimate result**, and must not manufacture a behavior difference to make the change look necessary.
- **Single-return fast path** (`functionLiteralInner`) never applies boundary conversion:
  the P1 probe of `lambda-fix-xcheck` is byte-identical in both trees and both fail. It is a residual gap.
- The contract for **Class J migration** is undefined.
