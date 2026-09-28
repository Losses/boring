# A3: Comparator planning and consumer migration

## Status and objective

This is the coordinator's design for the package A comparison migration.
A2's bounded source foundation and the five-target caller audit are accepted.
Luna owns the shared analysis and first Swift consumer in a separate checkout
at `f3a8955a`. Implementation and focused verification are in progress. The
remaining four target adapters require an accepted shared-interface checkpoint
and their own file assignments before implementation.

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

For example, Swift's current scalar comparison capability includes `Float`
and `Bool`. Spec 16's sorted-key domain excludes those field types. Applying
the narrower source admission rule to Swift's optional comparator capability
would also change the decision used by `SwiftType.usesIdentityEquality` and
`SwiftExpr`. Preserve that consumer's behavior unless a separate verified
semantic correction requires a change.

Spec 16 also says that unsupported records have no generated comparator. The
existing Swift capability therefore needs a separate conformance decision;
preserving its equality consumer during extraction does not establish that
the current comparator domain satisfies the specification. Record this
disagreement explicitly and test equality selection separately before changing
the capability contract. The sorted-key domain remains unchanged.

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

## Comparison semantics compose through field shapes

A scalar comparison operation retains its specified ordering when used inside
a nullable field, a collection element or a nested record. Plan construction
must compose those operations. Independently selecting a collection strategy
and a scalar strategy does not prove that the collection applies the scalar's
ordering rule.

Static inspection at `8e106066` provides two cases for the next executor to
reproduce. In `SwiftDecl.dataClassComparator` and `nullableArrayComparator`,
the default collection-element branch emits a positive result for unequal
elements. If an admitted `ReadOnlyArray<Int>` reaches this branch, singleton
values `[1]` and `[2]` would compare positive in both directions. Scalar and
nullable integer branches also emit subtraction, which requires checking
extreme values against the target integer range. These observations identify
emission risks; this review did not generate or execute either case.

For each target, verify sign reversal when operands are exchanged, zero exactly
when the specified equality holds, and transitivity on selected ordered triples.
Include integer limits, null ordering, unequal singleton collections, equal
prefixes, enum constructor order and strings whose UTF-16 order differs from
Unicode scalar order. Cite the source rule for each accepted form. Trace any
failure through source admission, the selected plan and the emitted operation
before assigning its repair. Preserve correct baseline behavior; record a
reproduced semantic correction separately from structural extraction.

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

An acyclic identity test can use two distinct declarations named `Point`:
`A.Point` has a stored `B.Point` field, and `B.Point` has only an `Int` field.
The reference path `A.Point -> B.Point -> A.Point` is a real cycle and cannot
prove a false cycle rejection. Add instantiated generic cases independently;
module and declaration names alone do not identify their actual type arguments.

The [consumer audit review](a-consumer-audit-review.md) records verified caller
locations and corrections to the external audit. In particular, TypeScript's
and Dart's `rawArrayElement` definitions have no caller beyond self-recursion
at the checkpoint. Their presence cannot establish a live nullable-array path.

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

## Remaining target adapter boundaries

The coordinator rechecked these consumers at `1bee18f9`. The table is an
implementation inventory; it assigns no additional writer. Each target must
consume the shared source fields and required operations, then select legal
target operations and their declaration dependencies. Copying the Swift
printer or retaining an independent raw-type classifier cannot complete an
adapter migration.

| Target | Current consumers and required target decisions |
| --- | --- |
| TypeScript | `TsDecl.dataClassComparator` uses `ComparatorPlan.entries(false, false)` plus independent helper preparation and `nullableArrayComparator`. `TsType.canEmitDataClassComparator` delegates to `PolicyQueries`; `TsExpr.sortedComparator` names the selected declaration. Migrate those decisions together and retain the UTF-16 string contract. |
| Kotlin | `KotlinDecl.dataClassComparator` uses `entries(true, true)` and emits a comparator for every data class. Its nullable scalar branch can compare decimal strings for Int fields. Plan numeric ordering, immutable versus mutable nullable extraction, helper ownership and declaration eligibility; keep `KotlinExpr.sortedComparator` references coherent. |
| Rust | `RustDecl.dataClassComparator` retains its own stored-field and raw-type traversal, including separate scalar, nullable and element operations. Plan borrowing and enum patterns from target representation. Int ordering must decode the signed source value from business storage without introducing forbidden casts. Review `RustExpr.sortedComparator` and the existing numeric helper before reuse. |
| Dart | `DartDecl.dataClassComparator` uses `entries(false, false)` and independently checks nested comparator capability in several branches. Plan nullable, element and nested operations once, retaining module qualification and `DartExpr.sortedComparator` references. |

Each assignment must inventory references from builder creation as well as
ordinary calls. The existing scalar direct-key and anonymous-structure paths
remain separate consumers to review when a selected operation is shared with
them. A record-only change cannot establish their migration.

Preserve payload-enum behavior while its source ruling is unresolved. Source
admission, target comparator availability and ordinary object identity remain
separate queries. Include ordinary reference classes as controls whenever a
capability migration touches general equality selection.

The migration's source tests cover actual argument substitution, aliases,
computed fields and declaration identity. Target tests additionally establish
that planned helper identities, names, imports and native operand types agree.
An unresolved target naming limitation must remain visible even when source
identity is correctly represented. Remove the legacy strictness flags and
duplicate classification owner only after their last target consumer migrates.

## Interface checkpoint review

An independent review examined a frozen implementation checkpoint based on
`f3a8955a`. Its findings are static; the active implementation has subsequent
changes and requires its own verification. Acceptance remains open for:

- Helper symbol scope: a record-local helper counter can produce duplicate
  declarations at file scope. Use two records in one source module with the same
  enum field type to distinguish an invalid redeclaration from legal overloads.
- Instantiation agreement: admitting `SortedMap<P<Int>, String>` from actual
  type arguments requires a generated comparator for that same request.
  Analysis of an unconstrained declaration `P<T>` cannot establish it.
- Request identity: sorted-key admission and optional equality capability
  must remain distinguishable at adapter boundaries as well as inside the
  source planner.
- Termination reasoning: an observed increase in actual type arguments is
  insufficient evidence of indefinite expansion. The coordinator challenged
  the review's initial proof and assigned a separate analysis of the transition.

The termination challenge is symbolic, with no native execution claim. For a
record `R<A, B>` whose next field is `Null<R<Box<B>, Box<Box<Int>>>>`, starting
at `R<Int, Int>` produces argument pairs:

1. `(Int, Int)`.
2. `(Box<Int>, Box<Box<Int>>)`.
3. `(Box<Box<Box<Int>>>, Box<Box<Int>>)`.
4. The same pair as step 3.

The first argument grows before the sequence stabilizes. An implementation
must explain how its expansion decision handles this transition; adding an
exception for this record would leave the analysis rule unverified. The
executor owns the corresponding compiler observation and general correction.
