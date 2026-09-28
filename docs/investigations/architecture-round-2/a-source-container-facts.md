# A2: Canonical source container facts

## Status and scope

This batch establishes a source-analysis foundation for package A. Its isolated
implementation checkout is based on `c762b8ed`; the executor has started the
assigned implementation after handing over the C observation fixture. It does not complete the prepared-value, comparator, or Swift boundary
migrations. Those obligations remain in the
[policy architecture](../../compiler-policy-architecture.md).

The assigned implementation scope is one shared source-container analysis
module, the three container queries in `StaticFieldHelper`, and focused tests.
The coordinator's executor brief records exact worktree and file ownership.
Feature 18 and standard library spec 06 establish the read-only source face.
The [policy contracts](../../compiler-policy-contracts.md) retain ownership of
target storage, presence, permissions, and conversion decisions.

## Authoritative source result

One typed analysis distinguishes the built-in `Array` declaration, the reserved
`std.ReadOnlyArray` declaration, another resolved type, and unresolved input.
Container variants retain their element type. Resolve transparent typedefs
with their actual type arguments and preserve explicit outer `Null` wrappers
before an erasing normalization. Element nullability is a separate fact.
The absence of an explicit outer wrapper does not prove runtime presence.

Recognize declarations by their source identity. A foreign declaration sharing
the name `ReadOnlyArray` remains distinct; a transparent alias resolving to the
reserved declaration has its container contract. Inspect actual compiler-typed
identity; a display string cannot establish it. Resolve genuine lazy
handles through the pinned macro API and retain unresolved state explicitly.
Classifying the outer container requires no recursive element classification.

The query consumes source types and returns source facts. It performs no target
rendering, target-name dispatch, storage selection, or flow-state update.

## First consumer migration

The existing public signatures remain transitional adapters. Each reads the
new result and retains its explicitly named optional-container scope:

| Existing query | Requested result |
| --- | --- |
| `isArrayType` | Mutable array with no explicit outer `Null` wrapper. |
| `isReadOnlyArrayType` | Read-only source face, including its existing outer `Null` case. |
| `arrayElementType` | Element of either container with no explicit outer `Null` wrapper. Nullable payload remains available through the new typed result for later consumers. |

Alias resolution and reserved identity are shared decisions. The new analyzer
does not need a separate mode for each adapter. Transparent alias recognition
and removal of foreign-name matches are deliberate classification corrections.
Existing direct-form output is expected unchanged; changed cases need their
own behavioral evidence. Other nullability helpers remain explicit migration
work because some consumers use them to infer produced representation.

Actual callers include the interception iteration gate, pipeline iteration
normalization, static declarations, and target parameter/return boundaries.
The executor verifies these callers before adoption. An unresolved result
reached by accepted source identifies an analysis-phase dependency; it cannot
authorize a new source rejection or invented container facts.

## Verification and subsequent consumers

Independently specify direct and generic-aliased containers, outer and element
`Null`, foreign same-name declarations, scalar and unresolved inputs, and genuine
lazy types. Test the source result and the real adapters. Complete ordinary
fixture compilation and observe production queries before another probe forces
their type handles. Synthetic macro forms retain separate labels.

Use identical authored alias-iteration and boundary fixtures on all five target
generators. Record baseline and candidate inputs, actual compiler identity,
generated output, compilation, runtime results, and raw warnings. A pre-existing
failure remains a recorded limitation; it does not justify an unrelated backend
repair. The coherent integration candidate still requires Boring verification
and fixed-revision Tiqian regression.

The next consumer migration remains required: comparator field plans, their
helper requirements, key eligibility, capability queries, and all five printers.
A target's ability to emit an operation does not widen the sorted-key domain of
standard library spec 16. Kotlin's helper prepass currently reclassifies fields
independently of the shared comparator body plan; both must eventually consume
one decision. Completing the three initial adapters does not complete that work.

## Pinned host API review

The coordinator inspected Haxe 4.3.7's installed standard library during A2
review. `std/haxe/macro/Type.hx` declares `TMono` through a nullable type
reference and `TLazy` through a delayed type computation.
`std/haxe/macro/TypeTools.hx` implements alias argument substitution in
`applyTypeParameters` and rejects unequal argument counts; its traversal
helpers also distinguish unresolved monomorphs from resolved ones.
`std/haxe/macro/Context.hx` states the typing-phase precondition for `follow`
and describes the `onAfterTyping` callback, including additional callback
invocations when new types are defined.

This is API evidence from the pinned installation. It does not establish the
behavior of the new analyzer or each Boring caller. The
[source resolution contract](../../compiler-policy-contracts.md#source-analysis-phase-and-resolution)
now makes unresolved state, coherent resolution, permitted host resolution,
and resource exhaustion explicit. The implementation must verify these rules
on real typed inputs before its source facts support target migration.
