# Swift array checkpoint and remaining work

## Checkpoint status

On 2026-09-28 the owner requested a checkpoint of the current Swift array
implementation and a transition to parallel architecture work across targets.
This checkpoint preserves unfinished implementation and tests. It is not an
accepted release candidate. No merge into master or Tiqian dependency update
is implied by publishing the architecture branch.

The executable baseline is `e3b8bab39ac2da0e17e9d04e031f03bd39290274`.
The checkpoint adds a `ReadOnlyArray` runtime view, a finite array conversion
planner, parameter representation planning, consumer changes, and focused
fixtures. The later J1 assignment made no further changes before it was stopped.
The [prepared-value design](j-prepared-value-design.md) remains the design
input for the cross-target policy work.

Historical focused runs passed subsets of the fixtures. The r10 capture has
26 runtime observations. The later nullable-fallback investigation reproduced
a generated Swift type error: a mutable optional array was reported as an
already converted read-only value. A subsequent focused run passed 29
observations before the current ordinary-conditional edits and typed-consumer
fixtures. Those results do not validate this checkpoint's current source.
The current branch changes remain unverified. Full Boring verification and
fresh Tiqian native regression evidence are outstanding.

## Required follow-up

- [ ] SW01: Have actual expression producers return their selected operation's
  storage and optionality. Remove contextual-type guesses after text emission.
  Include ordinary calls, replaced calls, constructors, literals, reads, casts,
  and transparent wrappers.
- [ ] SW02: Preserve stable declaration representation across initialization
  and assignment. Invalidate current value and flow facts independently.
  Verify nullable initialization followed by assignment and a typed consumer.
- [ ] SW03: Reconcile ordinary conditional results under separate branch facts.
  The current branch adapter lacks demonstrated use of the existing narrowing
  protocol. Verify both selections, lazy effects, and restored outer facts.
- [ ] SW04: Convert an optional nil-merge target through the optional form of
  the destination representation. Establish a required result only after a
  required fallback or a valid presence proof. The current adapter sends the
  optional target toward the final required destination too early.
- [ ] SW05: Migrate block tails, switch results, enum captures, and try binding
  and return routes. Use the actual destination for each result. The enclosing
  function return type can differ from a local initializer's destination.
- [ ] SW06: Complete static-field, runtime, and public-signature compatibility
  review. Keep ordinary shared views and decode-specific protections distinct.
- [ ] SW07: Remove superseded predictors and temporary diagnostics after their
  consumers migrate. Preserve lightweight source occurrence and input lineage.
- [ ] SW08: Run complete focused conformance and the independent storage-lifetime
  exercise, then required Boring and Tiqian checks on fixed revisions. Preserve
  generated artifacts, toolchain identity, child streams, statuses, and warnings.
- [ ] SW09: Keep existing `TiqianArray` and exception branding in the migration
  inventory with public API dependencies. The new view is named `ReadOnlyArray`.

These items belong to the relevant policy migration tasks. Completing the
array pilot is no longer a prerequisite for starting those tasks. The required
semantics and final verification obligations remain in force.
