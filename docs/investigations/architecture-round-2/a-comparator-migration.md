# A3: Comparator planning and consumer migration

## Status and objective

This is the coordinator's design for the next package A consumer migration.
Implementation requires the A2 source analyzer's accepted interface and the
bounded five-target caller audit. No A3 compiler writer is assigned by this
document. Completing A2's three adapters leaves this migration outstanding.

The current `ComparatorPlan` shares field classification with TypeScript,
Kotlin, and Dart. Swift and Rust import it but retain inline classification.
Target helper preparation and comparison bodies can also classify the same
field independently. A helper import or shared class name does not establish
that the actual generator consumes a shared decision.

## Responsibilities

The migration has four distinct decisions:

| Decision | Authoritative input | Output and consumer |
| --- | --- | --- |
| Stored source fields | Typed declaration, instantiated field types, source stored-field rule | Ordered field identities and canonical source shapes for every later decision |
| Sorted-key admission | Those source shapes and standard library spec 16 | Accepted key contract or the specified field-path diagnostic |
| Target comparison planning | Source shapes, required comparison semantics, target operations and declaration representation | A complete comparison plan, or an explicit missing target capability |
| Target declaration closure | The selected comparison plan | Helper declarations, imports and body operations needed by that same plan |

A source shape retains outer absence, collection element shape, nominal
identity and supplied type arguments. Its source information comes from A2
and the owning source-type analyses. The plan preserves field declaration
order and excludes computed `(get, never)` properties consistently at the
top level and during nested record analysis.

Sorted-key admission remains governed by spec 16. A target's ability to compare
additional scalar types cannot expand that domain. Swift's current capability
query also affects equality selection, so replacing it requires tracing that
consumer separately from sorted-key admission. A missing target operation for
an admitted source key is a compiler migration obligation.

## One selected plan for helpers and body

A target comparison plan names the operations its body will perform and the
symbols those operations require. Helper emission and body emission consume
that plan. They must not independently inspect a field's raw type to decide
whether an enum ordinal helper or nested record comparator is needed.

The selected plan must retain enough information for:

- Null ordering and extraction of the present operands under the target's
  actual declaration representation.
- Element comparison, traversal order and the prefix-length result for a
  read-only collection.
- Enum declaration identity, constructor order, and target constructor shape
  required by the ordinal operation.
- Nested record comparator identity and its module reference.
- String comparison under the specified UTF-16 unit order.
- Safe helper placement, target names, imports, and required visibility.

Names and helper placement are target construction decisions. Source membership
and field participation remain source decisions. A target adapter can realize
the same selected operation with different syntax or native facilities. It
cannot recover a missing semantic decision by examining emitted strings.

A successful plan provides every required operation and dependency. A capability
predicate can remain as a transitional adapter that asks whether planning
succeeds. The actual emitter must consume the same planning algorithm and
result guarantees; a separate optimistic capability traversal would recreate
the disagreement this migration is intended to remove.

Recursive records require explicit recursion state. Declaration identity and
actual type arguments distinguish an instantiated record; a short class name
cannot distinguish declarations in different modules. Detect an active cycle
separately from a previously completed dependency. An unresolved source type
or target dependency cannot be represented as a completed comparison plan.

## Concrete migration sites

| Target or owner | Required adoption and removal |
| --- | --- |
| Shared `ComparatorPlan` | Replace target-controlled outer/inner identity strictness flags with canonical source facts. Preserve field order and stored-field filtering. |
| `PolicyQueries` | Keep key-domain diagnostics and optional comparator capability meanings explicit; align nested field traversal with the source field plan. |
| TypeScript declaration generator | Move enum helper preparation and body field decisions to the selected plan; verify and remove the unused `rawArrayElement` helper. |
| Kotlin declaration generator | Replace the raw field helper prepass, `rawArrayElement`, and body reclassification with plan consumption. Account for nullable field extraction and helper references together. |
| Rust declaration generator | Replace inline source classification and nullable collection classification; preserve borrowing, enum patterns and module imports as target operations. |
| Swift declaration/type generators | Replace inline field classification and duplicated capability traversal; preserve the equality consumer's explicit decision contract. |
| Dart declaration generator | Use planned nullable/collection/nested-record operations and helper requirements; retain qualified module references and remove verified unused classification helpers. |

This table names the migration responsibilities. The executor brief must name
exact functions and exclusive file ownership before writes begin. The audit
supplies source locations and distinguishes live callers from unused imports
or helper definitions.

## Verification and parallel integration

The baseline and candidate use identical authored inputs, configuration and
compiler provenance. Tests distinguish source admission, plan selection,
helper declaration closure, target compilation, runtime ordering and warnings.
A generated declaration alone cannot establish that all its references resolve.

Use discriminating cases for direct and aliased read-only fields, nullable
collections, enum elements, nested records in another module, computed
properties, field-order changes, and unsupported sorted-key fields. Additional
nesting forms require a cited source rule before entering the accepted domain.
Test same-short-name records from distinct modules and recursive dependencies
without equating the two cases. Observe the first production query in the
admitted phase, as required by the source-resolution contract.

Preserve direct-form behavior where the source contract is already satisfied.
Alias identity corrections, missing helper repairs, or altered source-domain
behavior have separate expected results and explicit rationale. A byte-equal
subset cannot support a claim of equivalence for changed paths.

After the shared interface is accepted, one writer owns its implementation.
Separate writers may then own disjoint target adapters against that interface.
Tests and cross-review can proceed independently in pinned checkouts. Shared
interface changes return to the coordinator before downstream edits. The
coherent candidate must satisfy the programme's Boring and fixed-version
Tiqian verification; these focused cases do not replace that requirement.
