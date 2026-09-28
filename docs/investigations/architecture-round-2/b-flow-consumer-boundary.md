# B1: Flow evidence and its target consumers

## Status and architectural question

This is a coordinator review of the source at `abe3e900`. The observations below
are static. No runtime failure or equivalence between targets is established
by this review. No compiler writer is assigned here.

Package B must connect evidence about evaluated source paths to the operations
that consume it. A shared null-comparison recognizer supplies syntax facts.
Presence at a later use additionally depends on branch outcomes, reachable
incoming paths, assignments, and effects on the observed value.

The [policy contracts](../../compiler-policy-contracts.md) already distinguish
access identity, alias dependencies, lexical scope, flow validity and target
extraction. This review identifies actual consumers for the next bounded
observation batch.

## Concrete Kotlin owners

All expression functions in this table are in
`packages/compiler/reflaxe/kotlin/kotlincompiler/KotlinExpr.hx`.

| Function | Observed responsibility and review consequence |
| --- | --- |
| `scanNullGuards` | Records source ranges of null comparisons throughout a body, excluding nested functions. It does not record comparison outcomes or paths that reach a later use. |
| `bodyUsesSafeCallReturns` | Calls that scan and consults `guardProofBefore` while predicting whether return expressions produce nullable target values. This connects the source-position model to declaration representation. |
| `nullGuardPositionsInBlock` | Collects ranges for block rendering and excludes comparisons within call arguments. Its collection rules differ from `scanNullGuards`; similar result maps do not establish equivalent producers. |
| `blockLines` | Combines the block's ranges with enclosing ranges, renders statements, then restores the previous maps. A scope boundary alone cannot determine whether an outer value's earlier presence fact survived writes. |
| `guardProofBefore` | Accepts a recorded comparison in the same file whose end position precedes the use. That relation establishes textual order. The supplied record carries no branch outcome, dominance or effect dependency. |
| `functionBody` | Uses `bodyUsesSafeCallReturns` to set `currentReturnAllowsNullable`, alongside a separate interface return constraint. Expression lowering and declaration lowering therefore need a consistent produced-value contract. |

`KotlinDecl` also calls `bodyUsesSafeCallReturns` when selecting a rendered
method's return type. A repair must review both declaration and expression
consumers. Replacing one query with a stricter predicate can expose a disagreement
between the selected signature and the operations that the body emits.

These facts identify an architectural risk. Actual generated output and target
execution are needed to determine which accepted source cases expose it.
Other proof stores, native promotion and fallback operations can affect an
individual call path; their contribution must remain in the diagnosis.

## Required distinctions

The implementation must answer these questions separately:

1. Which value or read occurrence does the source condition describe?
2. Which condition outcome and evaluated paths establish presence here?
3. Which assignments or effects could invalidate that evidence before this use?
4. How does the target represent and legally extract that value at this point?
5. What representation and presence does the selected operation actually produce?

A target's native promotion rules answer part of the fourth question. They
cannot establish the source path facts in the second question. Likewise, a
source presence proof does not by itself establish a legal Rust borrow or
a Kotlin promotion of mutable storage.

An analysis with unknown flow facts must compose with a valid general
translation of accepted source. Missing proof cannot silently become source
rejection, a forced extraction, or an assertion that the result is present.
The operation planner must identify which supported translation supplies its
result guarantees.

## Next bounded observation batch

Use defined source behavior and independent expected values. A final null
normalization with a fallback can expose a removed or misclassified condition
without requiring an intentional null dereference as the expected behavior.

| Case | Distinction to observe |
| --- | --- |
| A null guard occurs within a branch that can be skipped. | Earlier text does not imply an evaluated guard on every incoming path. |
| A guard establishes presence, then a nullable assignment precedes a use. | Evidence about the old value does not establish presence of the replacement. |
| One reachable branch writes a nullable value; another preserves the guarded binding. | The join must include both reachable outcomes. Add an exiting-branch control. |
| A short-circuit operand changes a dependency before its next use. | Evaluation points within an expression can have different valid facts. Verify source admission first. |

Execute the admitted cases through Haxe, Kotlin and Rust with matching inputs.
Inspect the other three targets' owners and mark their runtime behavior
unmeasured. The expected results come from the governing source rules. Agreement
between targets cannot replace those expectations.

The handover must trace source admission, the responsible query and its input
environment, generated operations, native diagnostics and actual results. A
missing stage remains an explicit evidence limit. Reuse the accepted attempt
recorder available when the task is assigned.

The resulting implementation brief must name the authoritative fact producers,
invalidation owners, real consumers and old decisions to remove. Field aliasing,
captured writes, loop exits and other targets remain programme obligations after
this bounded batch. A null-syntax extraction alone does not complete package B.

The coordinator's [local-presence migration contract](b-local-presence-migration.md)
defines the next implementation boundary. It includes constructor and nested
function entry points, a prepared-function lifecycle, conservative effects and
the transition from mixed source and target proof stores. The external design
reports are investigation inputs; they do not replace that reviewed contract.

## Accepted bounded observation and verdict delivery

The delegated fixture under `tests/haxe/flow-contract/` now supplies two source
groups: normalized A cases with 25 authored outputs, and stable C cases with
six. The replay uses the shared child recorder and membership checker. Its
fixture-specific interpretation lives in `replay/verdict.ts`; consolidating
that responsibility across callers remains the follow-up recorded in the
[membership review](f-stage-membership-review.md).

The accepted worker attempt is
`out/flow-contract/replay-1790604435600-1800373` in the isolated
`policy-b-flow-observation` checkout at `41d67cad`. The coordinator verified
28 unique stage records, the terminal membership record, complete child
captures, and all 758 recorded input hashes against the unchanged checkout.
The bounded results are:

| Group and target | Observation |
| --- | --- |
| A Haxe and Kotlin | Each matches all 25 authored lines. |
| A Rust | 24 lines agree; the negative fallback renders `4294967295` where the source expectation is `-1`. |
| C Haxe and Rust | Each matches all six authored lines. |
| C Kotlin | Compilation exits 1 for a plain access on a nullable receiver; runtime is not reached. |

The procedure reports two retained nonconformance observations and zero
unexpected failures. Its successful exit establishes that bounded observation
contract. Target conformance still requires resolving the two observations.
The other three native targets remain unmeasured by this fixture, and final
candidate Boring and Tiqian checks remain open.

The coordinator also reran `replay/verify-verdict.sh`: attempt
`verifier-1790604733975-1804022` passed all 18 controls. They exercise the actual
CLI adapter, shared checker, comparison and final verdict from a complete
passing baseline. Missing, duplicate and undeclared records remain visible;
the reference stdout is checked against authored expectations; and exact Rust
agreement is distinguished from the documented replacement.
After copying the 32 delegated files unchanged, the coordinator repeated those
controls in the integration checkout. Attempt
`verifier-1790604873875-1806857` also passed all 18.

The review required two kinds of correction. The coordinator's pinned input
omitted the shared checker dependency, which has now been supplied unchanged.
The earlier executor's controls used incomplete manifests and bypassed the
production comparison entry, so their failures did not establish the claimed
properties. The accepted controls name the failure reason and retain a passing
baseline. The worker additionally injected three earlier defects and recorded
that the corresponding controls rejected them before restoring the source.

This delivery establishes reusable observations for the B2 local-presence
migration. The compiler migration, field invalidation and other target owners
remain separate required work.
