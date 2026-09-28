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
