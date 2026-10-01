# Architecture Contracts

Classification (`PROBLEM-CLASSIFICATION.md`) explains "which class of failures belongs to whom"; this document explains
**what each side of the interface commits to**, i.e., what a site must deliver under what conditions.

## Contract 1: Destination Passed In by Composition (Class D)

**Rule**: A conversion site MUST receive a **destination** (target type) and MUST NOT infer it from compiler instance state.

**Current facts** (verified, candidate tree `SwiftExpr.hx` 7041 lines):
- `currentReturnType` is an **instance field** of `SwiftExpr` (`:218`), sole write at `:544`
  (`functionBody`, from the member's `TFun` return), cleared at `:563`.
- `functionLiteral` (`:2338-2345`) only saves/restores `currentFuncReturnsOptional`,
  **does not rebind** `currentReturnType`.
- The correct value inside a lambda is **`f.t`** (`:2349` already uses it to print the closure header).

**Contract form**:
```
conversionSite(value, destination, fallback) -> text
where destination is provided by the composition that site belongs to:
  - member body      -> the member's return type
  - lambda body      -> the lambda's return type (f.t)
  - inline block / anonymous helper -> that block's own result type (not the outer lambda's)
  - binding route    -> the type of the bound variable (v.t)
  - parameter route  -> the parameter type declared by the callee
```
**The last item is the lesson of this session**: `blockExpression`'s block has its own destination;
treating it as the lambda's return contract **injects incorrect conversions** (P4 regression in
`lambda-fix-xcheck`, `mx/MXProbe.swift:19:12`, `cannot convert 'ReadOnlyArray<Int32>' to closure
result type 'TiqianArray<Int32>'`).

## Contract 2: Nil-merge Intermediate Destination Provided by Composition (Class C boundary × Class D destination)

**Specification text** (`docs/compiler-policy-interfaces.md:171-173`, verbatim):
> "A nil-merge with a required final result passes an **optional intermediate
> destination** to the optional left operand's conversion."

**Implementation**: the third input `destinationOptionalOverride` of
`prepare(operand, destinationType, override)` (`SwiftArrayBoundary.hx:173`).
- `override == null` ⇒ the planner adjudicates by the destination's own optionality (default context of the three REFUSED rows)
- `override == true` ⇒ the composition declares "an optional intermediate result is accepted here" ⇒ that cell becomes a conversion
  (`MapOptionalMutableArrayView` `:200-202` etc.)

**Contract boundary**: `override` is an **obligation of the composition**, not an attribute of the operand, nor an exemption.
The three REFUSED rows in `RECORD.md` are therefore qualified in the record as **PLANNER-CELL ONLY**
(CORRECTION 13).

## Contract 3: Warnings Count Toward Acceptance (Class F)

**Binding standard**: `docs/specs/style/02-translator-implementation-standard.md`
- `:78` *"Generated code compiles **without warnings** on every target … A
  translation that produces a warning is an emitter defect **with the same
  severity as a translation that produces wrong output**."*
- `:80` *"…counts the warning lines in the target suite output that name files
  under the generated trees; **the count is zero**."*

**Corollary (made and recorded in this session, TCN-156)**:
- Warnings **count**; **baseline failures must be recorded, but not exempted** (`work-plan:417`).
- ⇒ **A suite MUST be running**: no suite collection ⇒ no count produced ⇒ the standard cannot be met,
  only circumvented. **This gap has been connected** (`9f26e1ef`): `ci.yml` adds a `collected-suite`
  job that runs `bun run test` on every entry and reports the collection domain (303 files, of which 249 come from
  the generated tree `reference/ts/gen-tests`). This job is blocking, no `continue-on-error`;
  the baseline `1001 pass / 32 fail / 8 errors` is recorded in `BASELINE-FAILURES.md`, not yet discharged.
- ⇒ The form of the record MUST be "**known baseline failures + explicit PIN**", and MUST NOT be named
  "zero diagnostic compliance":
  the owner's ruling at `tests/swift-gap-boundary/gap-boundary.test.ts:44` is the operationalized form of this contract.

**Supplement (`t-muo92xms-s28t` ruling, `1a486ebd`; see `rulings/BUILD-PHASE-DIAGNOSTIC-RULING.md`):
"Which tool is used" and "which class of diagnostics it can see" MUST be explained separately.**
The main clause of `:78` is universally quantified ("on every target"), but when enumerating tools it only writes *"the Swift type-checker"*.
This narrowing leaves a hole: **`swiftc -typecheck` does not run SILGen and also reports 0 in the baseline state**,
so it can **neither confirm nor falsify** `Gap.swift:117`'s `will never be executed`;
the only things that can actually see it are `-c` (including `-whole-module-optimization`) and `-o`.
⇒ **Ruling: build-phase diagnostics count toward `:78/:80`**. If only "the type checker" is recognized literally, "zero warnings" degenerates into
an **empty criterion** (real emitter defects all silently pass, while downstream CI compiling binaries will still hit them).
**Counting discipline**: count by `file:line:col: severity` **shape**, do not use `grep -c 'warning:'`
— Swift also prints caret/context lines, which would double-count 1 as 2 (PIT-336).
**Generalization by analogy**: for every target, ask whether the current command **cannot see** the diagnostics it can report —
a same-family example from this session is that `cargo check` and `cargo build` have different warning surfaces.

## Contract 4: Acceptance Criteria for Generated Output MUST Be Able to Observe the Property Under Test

**Rule**: An acceptance check MUST **fail when that property is violated**.

**Three counterexamples from this session** (same gap, three causes):
| Item | Why unobservable |
|---|---|
| `branchBoundary` fixture | Both branches equal length, consumer only prints length |
| Missing return form | **`swiftc -typecheck` does not run SILGen, does not report "missing return"** |
| Splicing-class repair | Generated tree pre/post byte-identical (cannot distinguish "unchanged" from "correctly changed") |

**⇒ Operationalized criteria** (`LAYERED-VERIFICATION.md` will expand):
1. Assertions must be stricter than "not broken": e.g. `1:1:present` rather than `1:present`
2. **The return-stripped form MUST use `swiftc -c`, not `-typecheck`**
3. Splicing-class modifications MUST use a **discriminating backend** (deliberately taking the wrong branch / deliberately returning the wrong value) to prove it would FAIL

## Contract 5: A Fix MUST NOT Change the Behavior of Other Classes

**Implementation approach**: After a fix, regenerate against the **full driver set** and perform a full tree diff; **byte-identical after path normalization**
is a necessary condition. Four submitted fixes all satisfy this (W1: 19 drivers, only 2 lines diff and expected;
lambda: 19 drivers, diff is empty).

**Limitation**: Full tree identity **cannot** prove the fix is correct; it can only prove **it did not spill over elsewhere**;
"generation succeeds", "type-check passes", and "runs correctly" are three different strengths and must be stated separately.

## Contract 6: A Judgment MUST Have Exactly One Source; Anything Derivable From Facts MUST NOT Be Independently Determined Elsewhere

**Rule**: When whether something "holds" affects output, that judgment MUST have **exactly one authoritative source**.
If it can be **derived from facts that already occurred** (whether a file was actually written, whether a declaration was actually emitted),
it **MUST be derived**; a second piece of code MUST NOT **independently** decide it again.

**Why**: When a criterion and a fact are **determined in parallel**, the two can be inconsistent, and **inconsistency is invisible in passing state**.
This is the same family as Contract 4 but a different layer: Contract 4 says "the check must be able to observe the violated property";
this one says "**the criterion itself cannot be decoupled from the fact it describes**."

**Empirical (Rust target `state.shimsUsed`)**:
| Quantity | Value |
|---|---|
| Write sites (each believing "some shim was used") | **28 sites**, scattered across `RustDecl.hx` / `RustExpr.hx` / `RustImports.hx` |
| Read sites (deciding, based on this, whether a resident is emitted) | **15 sites** |
| Contract stipulating "which path must write" | **None** |

(Write site distribution: `RustExpr.hx` 23, `RustImports.hx` 3, `RustDecl.hx` 2;
read site distribution: `Compiler.hx` 13, `RustImports.hx` 1, `RustEmissionState.hx` 1.
Counted at `aceda352`, criterion "line shape": left-side assignment, subscript assignment, or `push|add|set|insert|remove|clear`.)

⇒ This global is used to mean **two different things**: "the business referenced some extern" (intent layer) and
"whether a resident should be written out as `.rs`" (emission layer). **The two layers are not equivalent, and no one is responsible for guaranteeing equivalence.**
The product is that `runtime/mod.rs` declares a module that was never written out (`E0583`):
**declarations follow one criterion, file emission follows another, and the write surfaces of the two do not overlap.**

**Two repair routes, different criteria**:
- **Fill in write sites**: every time an uncovered path is discovered, write the criterion again at that path
  (the one added at the tail of `RustImports.requireType` on master is of this kind).
  Correctness bets on "**write-site coverage is complete**"; but write-site count **cannot be exhaustively verified**, and degrades on any new path.
- **Derive from facts**: have the emit function **return whether it actually wrote the file**, recorded by the caller,
  and the declaration list **generated from that record** (this branch `94eace13`: `emitResidentModule` returns `Bool`
  ⇒ `emittedResidentMods` ⇒ `runtimeMods`). Correctness bets on "**declarations come from facts**",
  **verifiable and does not degrade with new paths**.

**⇒ Operationalized criterion**:
1. When "two pieces of code make the same judgment", first distinguish whether it is **same-layer duplication** or **write-side / read-side**;
   if both sides are needed, **MUST specify which side is the source of correctness**.
2. Ask "**is there a contract stipulating who must write**". If the answer is "no + write sites far outnumber read sites",
   the real defect is **not a missing merge**, but the criterion lacking a unique source.
3. Verify whether the derivation is **self-sufficient**: if, without illuminating those write sites, the invariant still holds on derivation alone,
   the derivation stands independently; **if it holds only when a particular write site fires**, correctness still depends on
   uncoordinated write sites; **this is itself a finding to report**, even if the code is syntactically correct.

**Ablation measurement (postscript, `aceda352`)**: Disabled the entire write-site block at the tail of master's
`RustImports.requireType` and regenerated `examples/rust.hxml`.

| Observation | Result |
|---|---|
| Gen rc | 0 |
| Generated tree diff (excluding cargo `target/`) | **Zero**: 545 `.rs` files identical on both sides |
| `runtime/mod.rs` | **Byte-identical** |
| Declarations / references | 15 / 15, violations = **0** |
| `cargo check` | rc=0, error count 0 |

⇒ This write site is **completely inert** on this corpus, so "zero violations" **proves neither self-sufficiency of derivation
nor necessity of the write site**. The reason is that both paths evaluate over the same set of externs: `Compiler.hx:862`'s
emission gate itself reads `state.shimsUsed.exists(externModule)` (via `externsOf`),
using the same `(isResident, externsOf)` pair as the write sites, and is necessarily consistent by construction.

To truly determine self-sufficiency, a case is needed where something is **touched only by `requireType` while its importer does not trigger
extern illumination**; until such a case exists, this item is recorded as **unresolved** and MUST NOT be written as "verified self-sufficient."

**The above conclusion has been overturned (correction, independent reproduction)**: the table of "zero full-tree diff" above is **true,
but it carries almost no information for judging whether the write site is necessary** — the gate computes a global union over the **same shared `shimsUsed`
map**, so any explicit illumination anywhere in the full corpus causes all residents to emit as usual,
and the absence of the write site is masked by the corpus itself. **Byte-identity on the full corpus cannot be taken as evidence of "inertness."**

Minimal counterexample (write site disabled, leaving only the single root `boring.DataClassStringCompare`,
the sample added together with this write site at `19ae7db6`):

| Observation | Write site present | Write site disabled |
|---|---|---|
| Gen rc | 0 | 0 |
| `runtime/mod.rs` | 9 `pub mod`, includes `sorted_table` | **5, `sorted_table` disappeared** |
| `boring/data_class_string_compare.rs` | Normal | Still `use crate::runtime::sorted_table::SortedTable;` (:1), :26 still calls |
| `cargo check` | **rc=0** | **rc=101, `error[E0432]: unresolved import`** |

⇒ This write site is **load-bearing, not redundant**, and **MUST NOT be deleted**. Contract 6 therefore has
a much stronger operationalized criterion: **judging "whether a write site is necessary" MUST be done via ablation on a minimal root set,
not on the full corpus** — the passing state of the full corpus masks single-point defects, the same phenomenon as Class G's
"inconsistency is invisible in passing state." Path: `RustDecl.hx:557` /
`RustType.hx:196-207`'s `requireType("runtime.SortedTable", …)` only illuminates
the `std.SortedMap` family, while in the full corpus these keys are also illuminated via `RustImports.hx:61` through
`RustType.hx:197/200/203/206`.

**Applicability boundary of this rule (postscript, measured from the re-review of `9081d0d0`)**: Contract 6 requires that criteria be derived from
facts, but **"derived fields" do not equal "mutually certifying"**. Within the same record,
`stdoutAvailable` is derived from whether the host outcome's stream object exists (`ChildEvidence.hx:439`),
`stdoutBytes` is derived from the length of the final written buffer (:505); the two have **different sources**:
in a healthy tree of 1005 records, 236 are simultaneously `available=true` and `bytes=0`.
Therefore one **MUST NOT** use the available flag to verify "the stream was indeed retained", nor treat
available/bytes consistency as an invariant assertion — it is normal form in this system.

By the same token, **before weakening an assertion, a mutation test MUST be performed**: after relaxing
`stdout>0 && stderr>0` to `stdout+stderr>0`, a real regression of "silently dropping stderr on the upper-bound path"
passes the entire test suite with rc=0 all green (reverting to the old assertion gives rc=1 and is caught). The basis for relaxation can only be
"what the system under test guarantees", not "it no longer flakes after the change."

## Unresolved

**The site references of the three items in this section were measured item by item on 2026-10-01 as follows** — all three **point to nothing**,
but the **technical issues** they express **remain valid**, so each item is broken down into "claim" vs. "location":

- **`switchExpression`'s destination**: Condition 3 requires giving it an explicit destination parameter
  (binding route `v.t`, parameter route using callee parameters), with `sw.t` as a fallback only when no contract exists.
  ~~Implementation seat in progress (`out/switchexpr-destination`)~~ → **The worktree does not exist** (checked three ways: by directory name,
  branch name, worktree name; none found; `git worktree list` has 122 entries total, none for this).
  **Remove the "in progress" status word**: it claims a present fact; once the document desyncs, it becomes false.
  Keep the technical issue itself, and that constraint: **that seat MUST report "output unchanged" as a valid result**,
  and MUST NOT fabricate behavioral differences to make the modification appear necessary.
- **Single-return fast path** (`functionLiteralInner`) never applied boundary conversion:
  ~~the P1 probe of `lambda-fix-xcheck` is byte-identical across both trees and both fail~~ →
  **`lambda-fix-xcheck` does not exist** (same three search methods). Keep the claim: this path has never applied
  boundary conversion, a residual gap; **a probe must be re-established** before it can be referenced again.
- **Class J migration** (legacy Kotlin → Haxe) contract is undefined —— **This item stands**,
  unlike the two above: the classification document `:92` **registers Class J** and writes that it is "a classification gap outside A–F"
  (per CODEX-AUDIT's "complete J migration were not established").
  So this is a **valid** unresolved item: **a class that is registered but not yet contracted**.

**These three are not the same thing; they can only be distinguished after measurement**:

| Item | Claim holds | Location reachable |
|---|---|---|
| `switchExpression` destination | Holds | **No** —— worktree does not exist |
| Single-return fast-path gap | Holds | **No** —— `lambda-fix-xcheck` does not exist |
| Class J migration contract undefined | Holds | **Yes** —— classification document `:92` |

**Postscript (my own correction)**: I initially judged Class J as a "dangling reference" as well — **that was wrong** —
it is indeed registered in the classification document, just not in the A–F table, so searching by class alphabet I didn't find it.
**Checking whether "a class exists" cannot only check the main table**: the subsection registering gaps is equally part of the definition.
The two that are truly invalid are **worktree references**, because they point to **temporary** locations.

**The common shape of these three is worth recording**: they are the **most fragile** form of "known but unresolved" —
referencing a **temporary** worktree, and worktrees get cleaned and cleanup leaves no trace.
**Postscript rule**: unresolved items should write down **the technical issue itself** (long-lived) + **a reproducible probe command**,
not + a worktree name. A worktree name is a location, and locations disappear; the issue is content, and content does not.
