# Architecture Contracts

The classification document (`PROBLEM-CLASSIFICATION.md`) specifies "which category of failure belongs to whom"; this document specifies
**what each side of an interface commits to**, i.e.: what a given position must produce under what conditions.

## Contract 1: Destination Is Passed In by Composition (Category D)

**Rule**: A conversion site must receive a **destination** (target type) and must not infer it from compiler instance state.

**Current facts** (verified, candidate tree `SwiftExpr.hx` 7041 lines):
- `currentReturnType` is an **instance field** of `SwiftExpr` (`:218`), written only at `:544`
  (`functionBody`, from the member's `TFun` return), cleared at `:563`.
- `functionLiteral` (`:2338-2345`) only saves/restores `currentFuncReturnsOptional`,
  **does not rebind** `currentReturnType`.
- The correct value inside a lambda is **`f.t`** (`:2349` already uses it to print the closure header).

**Contract form**:
```
conversion-site(value, destination, fallback) -> text
where destination is provided by the composition that owns the position:
  - member body      -> the member's return type
  - lambda body      -> the lambda's return type (f.t)
  - inline block / anonymous helper -> the block's own result type (not the outer lambda's)
  - binding route    -> the bound variable's type (v.t)
  - parameter route  -> the parameter type declared by the callee
```
**The last clause is the lesson of this session**: a `blockExpression` block has its own destination;
treating it as the lambda's return contract **injects an incorrect conversion** (the P4 regression in
`lambda-fix-xcheck`, `mx/MXProbe.swift:19:12`, `cannot convert 'ReadOnlyArray<Int32>' to closure
result type 'TiqianArray<Int32>'`).

## Contract 2: nil-merge Intermediate Destination Provided by Composition (Category C Boundary × Category D Destination)

**Spec text** (`docs/compiler-policy-interfaces.md:171-173`, verbatim):
> "A nil-merge with a required final result passes an **optional intermediate
> destination** to the optional left operand's conversion."

**Implementation**: the third input `destinationOptionalOverride` of
`prepare(operand, destinationType, override)` (`SwiftArrayBoundary.hx:173`).
- `override == null` ⇒ the planner rules by the destination's own optionality (default context of the three REFUSED rows)
- `override == true` ⇒ composition declares "an optional intermediate result is accepted here" ⇒ that cell switches to conversion
  (`MapOptionalMutableArrayView` `:200-202`, etc.)

**Contract boundary**: `override` is **the composition's obligation**, not an operand attribute, nor an exemption.
The three REFUSED rows in `RECORD.md` are therefore scoped in the record as **PLANNER-CELL ONLY**
(CORRECTION 13).

## Contract 3: Warnings Count Toward Acceptance (Category F)

**Normative standard**: `docs/specs/style/02-translator-implementation-standard.md`
- `:78` *"Generated code compiles **without warnings** on every target … A
  translation that produces a warning is an emitter defect **with the same
  severity as a translation that produces wrong output**."*
- `:80` *"…counts the warning lines in the target suite output that name files
  under the generated trees; **the count is zero**."*

**Corollary (decided and recorded in this session, TCN-156)**:
- Warnings **count**; **baseline failures must be recorded, but do not grant exemption** (`work-plan:417`).
- ⇒ **A suite must be running**: no suite collection ⇒ no count produced ⇒ the standard cannot be satisfied,
  merely bypassed. **This gap has been wired** (`9f26e1ef`): `ci.yml` adds a `collected-suite`
  job that runs `bun run test` at every entry point and reports the collection domain (303 files, of which 249 come from
  the generated tree `reference/ts/gen-tests`). This job blocks, no `continue-on-error`;
  the baseline `1001 pass / 32 fail / 8 errors` is recorded in `BASELINE-FAILURES.md`, not yet resolved.
- ⇒ The recorded form must be **"known baseline failure + explicit PIN"**, must **not** be named "zero diagnostics satisfied":
  the ownership ruling at `tests/swift-gap-boundary/gap-boundary.test.ts:44` is the implementation of this contract.

**Supplement (`t-muo92xms-s28t` ruling, `1a486ebd`; see `rulings/BUILD-PHASE-DIAGNOSTIC-RULING.md`):
"Which tool is used" and "which class of diagnostics it can see" must be stated separately.**
The main clause of `:78` is universal ("on every target"), but when enumerating tools it writes only *"the Swift type-checker"*.
This narrowing leaves a hole: **`swiftc -typecheck` does not run SILGen and reports 0 diagnostics even in the baseline state**,
so it **can neither confirm nor disconfirm** the `will never be executed` at `Gap.swift:117`;
the only tools that can actually see it are `-c` (including `-whole-module-optimization`) and `-o`.
⇒ **Ruling: build-phase diagnostics count under `:78/:80`**. If we take "type-checker" literally, "zero warnings" degrades to
**an empty criterion** (real emitter defects all pass silently, while the downstream CI that compiles binaries will still hit them).
**Counting discipline**: count by the **shape** `file:line:col: severity`, do not use `grep -c 'warning:'`
—— Swift also prints caret/context lines, which can count 1 diagnostic as 2 (PIT-336).
**Generalization to peers**: for every target ask "does the current command **miss** diagnostics it could report"——
one peer case in this session is that `cargo check` and `cargo build` have different warning surfaces.

## Contract 4: Acceptance Criteria for Generated Output Must Be Able to Observe the Property Under Test

**Rule**: An acceptance check must **fail when the property is violated**.

**Three counterexamples from this session** (same gap, three causes):
| Item | Why It Is Not Observable |
|---|---|
| `branchBoundary` fixture | Both branches are equal-length; the consumer only prints length |
| Missing return form | **`swiftc -typecheck` does not run SILGen, does not report "missing return"** |
| Splicing-type fix | Generated tree pre/post are byte-for-byte identical (cannot distinguish "unchanged" from "fixed correctly") |

**⇒ Implemented criteria** (`LAYERED-VERIFICATION.md` will elaborate):
1. Assertions must be stricter than "not broken": e.g. `1:1:present` rather than `1:present`
2. **Forms stripped of `return` must use `swiftc -c`, not `-typecheck`**
3. Splicing-type changes must be proven to FAIL with a **discriminative backend** (deliberately taking the wrong branch / returning the wrong value)

## Contract 5: Fixes Must Not Change Behavior of Other Categories

**Implementation**: after a fix, regenerate with the **full driver set** and compare the full tree;
**byte-for-byte identical after path normalization** is a necessary condition. All four committed fixes satisfy this
(W1: 19 drivers, only 2 lines differ and as expected; lambda: 19 drivers, diff is empty).

**Boundary**: full-tree identity does **not** prove the fix is correct; it only proves **no collateral impact elsewhere**;
"generation succeeds", "type-check passes", and "runs correctly" are three different strengths and must be stated separately.

## Contract 6: A Judgment Must Have a Single Source; If It Can Be Derived from Facts, It Must Not Be Separately Decided

**Rule**: When whether "something holds" affects output, that judgment must have **exactly one authoritative source**.
If it can be **derived from facts that have already occurred** (whether a file was actually written, whether a declaration was actually emitted),
it **must be derived**; a second piece of code must not **independently** decide it again.

**Why**: When a criterion and the fact are **decided in parallel**, the two can diverge, and
**the divergence is invisible in the passing state**. This is the same family as Contract 4 but a different layer:
Contract 4 says "the check must be able to observe the violated property",
this clause says "**the criterion itself must not decouple from the fact it describes**".

**Field measurement (Rust target `state.shimsUsed`)**:
| Quantity | Value |
|---|---|
| Write points (each believes "some shim is used") | **28 locations**, scattered across `RustDecl.hx` / `RustExpr.hx` / `RustImports.hx` |
| Read points (decide from these whether a resident is emitted) | **15 locations** |
| Contract specifying "which path must write" | **None** |

(Write point distribution: `RustExpr.hx` 23, `RustImports.hx` 3, `RustDecl.hx` 2;
read point distribution: `Compiler.hx` 13, `RustImports.hx` 1, `RustEmissionState.hx` 1.
Measured at `aceda352`, criterion is "line shape": left-hand assignment, subscript assignment, or `push|add|set|insert|remove|clear`.)

⇒ This global is used in **two meanings**: "business code references some extern" (intent layer) and
"whether a resident should be written as `.rs`" (emission layer). **The two layers are not equivalent, and nobody is responsible for ensuring equivalence.**
The product is `runtime/mod.rs` declaring a module that was never written (`E0583`):
**the declaration follows one criterion, file emission follows another, and the two write surfaces do not coincide.**

**Two repair routes, with different criteria**:
- **Add write points**: every time an uncovered path is found, write the criterion again on that path
  (the one added by master at the tail of `RustImports.requireType` is of this kind).
  Correctness is staked on "**write-point coverage is complete**"; but the number of write points
  **cannot be exhaustively verified**, and new paths cause immediate regression.
- **Derive from facts**: have the emission function **return whether it actually wrote the file**, recorded by the caller,
  and generate the declaration list **from that record** (this branch `94eace13`: `emitResidentModule` returns `Bool`
  ⇒ `emittedResidentMods` ⇒ `runtimeMods`). Correctness is staked on "**declarations come from facts**",
  **verifiable and does not regress with new paths**.

**⇒ Implemented criteria**:
1. When "two pieces of code make the same judgment", first distinguish whether it is
   **same-layer duplication** or **write-side / read-side**;
   if both sides are needed, **one side must be designated as the source of correctness**.
2. Ask "**is there a contract specifying who must write**". If the answer is "no + write points far outnumber read points",
   the real defect is **not a missing merge** but rather the criterion lacking a unique source.
3. Verify whether the derivation is **self-sufficient**: if those write points are not lit and the invariant still holds from derivation alone,
   the derivation is independently valid; **if it only holds when a particular write point fires**, correctness still depends on
   uncoordinated write points; **this itself is a finding to report**, even if the code is syntactically correct.

**Ablation measurement (postscript, `aceda352`)**: disable the entire block at the write point in master's `RustImports.requireType`
tail, then regenerate `examples/rust.hxml`.

| Observation | Result |
|---|---|
| Generation rc | 0 |
| Generated tree diff (excluding cargo's `target/`) | **Zero**: 545 `.rs` files identical on both sides |
| `runtime/mod.rs` | **Byte-for-byte identical** |
| Declarations / references | 15 / 15, violations = **0** |
| `cargo check` | rc=0, error count 0 |

⇒ This write point is **completely inert** on this corpus, so "zero violations" **proves neither that the derivation is self-sufficient
nor that the write point is necessary**. The reason is that both paths evaluate the same set of externs: the emission gate at
`Compiler.hx:862` itself reads `state.shimsUsed.exists(externModule)` (via `externsOf`),
using the same pair `(isResident, externsOf)` as the write point, and is thus necessarily consistent by construction.

To truly determine self-sufficiency, a use case is needed where "something is touched only by `requireType` and its importers do not trigger
extern lighting"; until then this item is marked as **unresolved** and must not be written as "self-sufficiency verified".

**The above conclusion has been overturned (correction, independently reproduced)**: the "full-tree zero diff" table above is **true,
but it carries almost no information about whether the write point is necessary**——the gate computes a **global union over the same shared `shimsUsed`
map**, so any single explicit lighting in the full corpus causes all residents to emit as usual,
and the write point's absence is masked by the corpus itself. **Byte identity on the full corpus cannot be taken as evidence of "inertness".**

Minimal counterexample (write point disabled, only the single root `boring.DataClassStringCompare` remaining,
i.e. the sample added together with that write point at `19ae7db6`):

| Observation | Write point present | Write point disabled |
|---|---|---|
| Generation rc | 0 | 0 |
| `runtime/mod.rs` | 9 `pub mod` entries, including `sorted_table` | **5 entries, `sorted_table` disappeared** |
| `boring/data_class_string_compare.rs` | Normal | Still `use crate::runtime::sorted_table::SortedTable;` (:1), :26 still calls it |
| `cargo check` | **rc=0** | **rc=101, `error[E0432]: unresolved import`** |

⇒ This write point is **load-bearing, not redundant**, and **must not be deleted**. Contract 6 therefore has a much stronger
implemented criterion: **the judgment of "whether a write point is necessary" must be done by ablation on a minimal root set,
not on the full corpus**——the full corpus's passing state masks single-point defects, the same phenomenon as Category G's
"divergence is invisible in the passing state". Path: `RustDecl.hx:557` /
`RustType.hx:196-207`'s `requireType("runtime.SortedTable", …)` only lights
the `std.SortedMap` family, while in the full corpus these keys are also lit by `RustImports.hx:61` via
`RustType.hx:197/200/203/206`.

**Applicability boundary of this rule (postscript, measured from review at `9081d0d0`)**: Contract 6 requires criteria to be derived from
facts, but **"derived fields" do not equal "mutually attestable"**. Within the same record,
`stdoutAvailable` is derived from whether a stream object exists on the host outcome (`ChildEvidence.hx:439`),
`stdoutBytes` is derived from the final write-buffer length (:505); the two have **different sources**:
out of 1005 records in a healthy tree, 236 are simultaneously `available=true` and `bytes=0`.
Therefore one **must not** use the available flag to verify "the stream was indeed preserved", nor assert
available/bytes consistency as an invariant——it is normal form in this system.

By the same token, **a mutation test must be done before weakening an assertion**: after relaxing
`stdout>0 && stderr>0` to `stdout+stderr>0`, a real regression that "silently drops stderr on the upper-limit path"
passed the full suite with rc=0 all green (reverting to the old assertion catches it with rc=1).
The basis for relaxation can only be "what guarantee does the subject under test provide",
not "it no longer fails sporadically after the change".

## Unresolved

- **Destination of `switchExpression`**: Condition 3 requires it to receive an explicit destination parameter
  (binding route `v.t`, parameter route using the callee's parameter); `sw.t` serves only as a fallback when there is no contract.
  The implementation branch is underway (`out/switchexpr-destination`). **This branch must report "output unchanged" as
  a legitimate result** and must not manufacture behavioral differences to make the change appear necessary.
- **The single-return fast path** (`functionLiteralInner`) never applies boundary conversion:
  the P1 probe from `lambda-fix-xcheck` shows both trees byte-for-byte identical and both failing. This is a residual gap.
- **The contract for Category J migration** is undefined.