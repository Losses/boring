# A3: Generic schema probe review

The coordinator reran the isolated A3 entry on its current dirty source. The
procedure exited one and retained `run-i8cBorGe`. Its macro probe child exited
normally with status zero and empty stderr, but one authored output row differs.
The observed `GenericNested` field describes a record use with the argument
`TInst(comparisonplan.GenericNested.T,[])`; the expected row spells that
argument `TAnonymous(<anonymous>)`. All later Swift generation, compilation,
and execution stages were recorded as not attempted. No target behavior follows
from this run.

`GenericNested<T>` stores `Box<T>`. The schema builder records a reusable
`Box` declaration and carries its actual type argument. In the current Haxe
macro process the argument prints as a named type parameter owned by
`GenericNested`. That is consistent with the intended binder, but a raw
`Std.string(Type)` comparison does not establish binder identity or operation
selection. The implementation already has `ownParameterSlot` and
`schemaParameterIndex` queries for that purpose.

The executor should make this probe assert the semantic slot and owner of the
argument, plus the selected comparison operation for the nested field. Its
expected text should then describe that stable result. A control with a
same-named parameter owned by another declaration must remain distinct. Rerun
the full A3 procedure after revising the probe; retain all target stage results
and the selected input hashes. The 41-row admission run remains separate
evidence and cannot substitute for this blocked Swift procedure.
