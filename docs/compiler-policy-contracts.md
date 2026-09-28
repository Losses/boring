# Policy interface contracts

## Status and authority

This document records the coordinator's interface decisions for the
[policy architecture](compiler-policy-architecture.md). It refines the input
and result distinctions required by the analysis method. It does not add a
source-language behavior ruling or certify an existing implementation.

Package A's revised separation of source contract, produced value, and
destination requirement is accepted as a design distinction. Its proposed
conversion table remains unaccepted. The rules below replace its overlapping
rows and its claim that a presence proof can make a null literal present.
Other packages can use these distinctions while their concrete interfaces
remain under review.

## Authoritative records

| Record | Producer and lifetime | Required distinctions |
| --- | --- | --- |
| Source value contract | Source type/declaration analysis, under the applicable specification | Source container kind, element type, declared nullability, and the scope of applicable semantic rules |
| Declaration requirement | Target declaration selection, stable for the binding | Actual declared target storage, admitted absence, read behavior, and origin |
| Prepared value | The selected target operation at one lowering occurrence | Actual storage, present/absent possibilities, source occurrence, input lineage, and applicable flow dependencies |
| Presence evidence | Flow analysis at a specific use, with dependencies and invalidation | The exact subject/read, environment, fact lifetime, and applicable proof; no independent rendered-text inference |
| Conversion plan | A pure decision consuming prepared value and destination | Required operand operations, result storage/presence, and the guarantees needed by the next consumer |

Source classification cannot populate actual produced storage. A target can
produce several storage forms for the same source type, including helper-native
collections and its ordinary runtime wrapper. Its producer vocabulary must
represent each admitted form or identify an explicit pending migration.
A missing migration is a compiler work item; it cannot redefine accepted source.

A declaration can select storage while considering the declared or inferred
source type and target capabilities. Every initializer and assignment must
satisfy that selection. A value conversion result never overwrites the stable
declaration record. A null initializer supplies absence to the selected storage.

## Presence and literal states

These states describe one prepared occurrence:

- **Present value:** the selected operation produces a value. Its target
  storage is explicit.
- **Maybe absent value:** the selected operation can produce absence. Its
  present payload storage is explicit.
- **Null literal:** this occurrence produces absence. No guard or default
  proof can turn that literal into a present value.
- **Contextual empty literal:** an empty container needs its constructor and
  element type from the result context. Once materialized, it is present.
- **Unreachable result:** control-flow analysis establishes that this path
  produces no reachable normal value. The value join excludes that path using
  the reachability evidence. Its null literals retain their absent state.

A positive proof attached to a null literal is contradictory input and must
be reported as an internal fact disagreement. If a source binding was
initialized to null and later assigned an array, a read of that binding is a
new occurrence. It consumes the stable declaration and current flow facts;
it does not retain the initializer's literal state.

## Conversion to a selected destination

Let `S` be the actual present payload storage and `D` the destination storage.
The target's representation policy supplies a valid `S` to `D` operation that
preserves the applicable source semantics. This table states presence rules;
it does not prescribe the same runtime representation on every target.

| Prepared input | Destination admits absence | Required decision and result |
| --- | --- | --- |
| Present value in S | Either | Apply the selected storage operation; the result is present in D. |
| Maybe absent value in S | Yes | Preserve absence and apply the storage operation only to a present payload; the result remains maybe absent in D. |
| Maybe absent value in S | No | Establish a valid extraction operation at this use before claiming a present result. A proof must match its subject, environment, and dependencies. Missing proof cannot be repaired by changing the result flag. |
| Null literal | Yes | Preserve absence with the destination's optional type context. |
| Null literal | No | No absence-preserving conversion satisfies this destination. A contradictory positive proof cannot authorize one. |
| Contextual empty literal | Either | Select a constructor with the required element type; return a present container in D. Missing element information is an unresolved lowering input. |
| Unreachable result | Either | Join only reachable normal results; retain the evidence establishing reachability. |

Failure to prove an extraction's preconditions is distinct from invalid source.
The lowering owner must use an applicable general translation or identify the
missing compiler contract for accepted source. A source rejection requires the
specified source-domain rule. This distinction does not authorize a silent
unwrap or a new null-handling behavior.

## Composition owns intermediate requirements

A nil-merge with a required final result passes an **optional intermediate
destination** to the optional left operand's conversion. It then combines that
result with the converted fallback. A required fallback establishes a required
normal result. A nullable fallback leaves the result nullable unless valid
control-flow evidence removes every absent outcome. The conversion planner
must never accept an optional result against a required destination by silently
assuming some later caller will reconcile it.

An ordinary conditional converts each reachable arm under that arm's flow
environment and joins the resulting facts. A reachable null arm prevents a
required result. Both forms preserve runtime branch selection and lazy
evaluation. A proof about one field access does not establish proofs for its
prefixes or other accesses without explicit evaluation and invalidation rules.

Parameter defaults retain source argument semantics, registration facts,
target placement, raw signature storage, and normalized body storage as
separate decisions. Native placement alone proves no presence. Apply feature
22 together with feature 51 and their documented variations before defining
default evaluation or call-completion behavior.

## Flow environments and effect dependencies

A flow fact describes a particular value or read at an evaluation point. Its
identity retains the binding or evaluated object and every supported projection.
`x.left.value` and `x.right.value` cannot share a key that keeps only `x` and
`value`. An unsupported projection yields an unknown identity. Rendered text
and source offsets cannot establish identity or control-flow dominance.

Distinct access paths do not establish disjoint storage. If `x.left` and
`x.right` can refer to the same object, a write through either path can
invalidate facts about the other's fields. Keep access identity separate from
the alias dependencies used for invalidation. Preserving a sibling fact after
a write requires evidence that the write cannot affect that fact's dependencies.

Fact validity and lexical visibility have separate lifetimes. Leaving a nested
scope removes its local bindings; it does not undo writes to outer bindings or
objects. A join consumes the exit environments of reachable incoming paths.
Restoring an entry snapshot after a branch is valid only for facts whose
dependencies remain unchanged along every relevant path.

Control exits retain their destinations. A `continue` contributes to the
selected loop's next iteration; a `break` contributes to the exit of its
enclosing construct. Returns and throws have their own destinations. A helper
that reports only whether a statement falls through cannot by itself supply
the environments for these different destinations.

| Situation | Required analysis distinction |
| --- | --- |
| A branch may assign a nullable value to a previously present binding | The exit may lack presence even when the binding remains visible. |
| A loop may write a fact's dependency | Zero iterations and executed iterations both contribute to the exits. Use a fixed-point analysis or a conservative treatment of the possible writes; restoring all entry facts is unsound. |
| A call has incomplete effect information | Account for captured bindings and reachable mutable storage. Invalidating local facts while preserving every field fact is not conservative. |
| Short-circuit operands, arguments, or assignment operands have effects | Represent their distinct evaluation points and edges. One statement index cannot describe every use within the expression. |
| A value has a non-null contextual type | Establish presence through its actual producer or the applicable source rule. The contextual type cannot make a null literal present. |

Effects invalidate dependent facts; the owning analysis states which dependencies
it can distinguish. A fact about an immutable, uncaptured local value can survive
a call when the available information establishes its independence. A fact about
mutable storage requires the relevant effect and alias information. Unknown
effects cannot be relabelled as a registered read operation to retain a proof.

Missing flow evidence remains distinct from invalid source. A conservative
analysis must compose with a valid translation of the accepted source domain.
The target adapter separately establishes how to read the value legally under
its storage, borrowing, and native promotion rules. Those target operations do
not change the source analysis result.

## Prepared assignment locations

Where the source operation requires a write to an already selected location,
preparation retains the evaluated receiver, projections, indices, and applicable
access operations. Rebinding the original variable during the right operand
does not authorize computing a new destination from the original expression.
The location's logical identity is separate from a physical address that a
target allocation or growth operation could invalidate.

Permission applies to an operation at a location. Permission to replace a field,
store an element, and call a mutator on a referenced object are separate queries.
A final binding or getter-only property does not by itself establish transitive
immutability of every reachable object.

A target value intermediate on an assignment path may require an ordered chain
of writebacks. Each writeback names its owner location and required evaluation
point. A value copied into an independent source binding has a different
contract; its later mutation does not automatically require writing to the
original binding. Retain the governing rule's target and source scope when
deciding between these cases.

## Implementation admission

An executor must demonstrate that its finite decision rows are disjoint and
that each declared operation has sufficient input facts. Cover definite null,
contextual empty, optional payload, contradictory evidence, and optional
intermediate composition as distinct cases. Test an implementation against
these independent requirements; enumerating its own branches is insufficient.

Source classification consolidation can proceed as a separate foundation once
the existing helpers and their callers are compared. It does not complete
produced-value or boundary migration. Each target migration must replace named
reconstruction sites and connect actual producers to consumers. Unused shared
records and adapters that still guess from contextual types remain incomplete.

An equivalence claim compares the existing producers and their actual callers.
Similar function names or overlapping cases do not establish the same rule.
Record wrapper handling, result ordering, branch placement, and other writers
of each consumed fact store. Share only the decisions established as equivalent
in a preservation batch. Changed joins, effects, or accepted proof conditions
belong to an explicitly verified correctness change.
