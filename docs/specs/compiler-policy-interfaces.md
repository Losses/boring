# Compiler policy interfaces

This document lists the interfaces a target consumes when it asks the policy
layer for a decision. It complements `target-semantic-policy.md`, which defines
the policy entries themselves.

## Representation plan

`SemanticPolicy.RepresentationPlan` answers how one value is spelled in the
target: role, adapter edge, thread-safety bound, concrete spelling, receiver and
parameter ABI, conversion edges, and the provenance of the decision.

## Place plan

`PlacePlan.PlacePlan` answers which storage a write reaches:

| Field | Meaning |
|---|---|
| `root` | the rendered root expression (a local, self, static, field base) |
| `projections` | ordered steps, each `PreserveLocation`, `PreserveReferentIdentity` or `DetachedValueWithWriteback` |
| `intent` | `ReadValue`, `AssignSlot`, `MutateReferent` or `ReadModifyWrite` |
| `isPlace` | true when the whole chain is a place, with no detached copy lacking writeback |
| `writeback` | the statement that writes the value back, when the plan detaches |
| `verified` | true when the plan has been checked against the source semantics |

`PlacePlan.MutationPlan` pairs a target place plan with the intent and any
writeback, so a mutation is emitted only when the target is a place or carries
complete writeback.

## Validation entry points

| Function | Input | Output |
|---|---|---|
| `RustHandleValidator.placePlanFailure` | one `PlacePlan` | `null` when the plan proves its write, otherwise the first unmet obligation |
| `RustHandleValidator.validatePlacePlans` | many `PlacePlan` | `ValidationError` entries with rule `P-22` |

A target that receives a non-null failure must not emit code for that mutation.
