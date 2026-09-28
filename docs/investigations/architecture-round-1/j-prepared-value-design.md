# J: Prepared array values and representation ownership

## Status and purpose

The owner subsequently requested an unfinished Swift checkpoint and parallel
cross-target policy migration. See the [checkpoint TODO](swift-checkpoint-todo.md).
The phases below remain reviewed design inputs. J1 was stopped without further
edits; resumption requires a policy-package assignment.

This design follows the reopened P07 review after conditional expressions
exposed an incorrect representation handoff. Independent review on 2026-09-28
approved the producer inventory, guarantees, and phased implementation order.
Implementation resumes by explicit phase assignment. The current code's
compliance remains unverified. The [J brief](j-boundary-implementation.md) retains the source
semantics, file ownership, runtime requirements, and full verification gates.

The concrete failure is recorded in the
[round review](../architecture-round-1.md). A Haxe expression context required
a read-only array, but its Swift conditional produced a mutable wrapper.
Preparation reported an existing read-only view and selected no conversion.
Reading collection elements did not expose that mismatch. A later typed
consumer did.

## Responsibility and data flow

The mechanism has four responsibilities. Their interfaces must agree before
moving helpers between files.

| Responsibility | Inputs | Authoritative result | Current integration owners |
| --- | --- | --- | --- |
| Declaration selection | Source declaration, target type mapping, parameter default plan | Stable binding representation and the selected read behavior | `SwiftType`, `SwiftDecl`, `SwiftParameterPlan` |
| Expression lowering | Typed expression, required result context, current binding and flow environment | Prepared expression with its actual storage, optionality, and presence evidence | Producer paths in `SwiftExpr` |
| Boundary selection | Prepared expression and destination requirements | Conversion operation and resulting representation | `SwiftArrayBoundary.prepare` |
| Emission | Selected operation and its prepared operands | Target text implementing that operation | Boundary renderer and terminal expression/statement adapters |

An expected result type constrains lowering. It does not describe the storage
already produced. The expression producer selects its output operation and
returns the corresponding facts together. A generic call to `expr(e)` followed
by a classification of `e.t` does not establish this guarantee.

Keep the existing finite boundary planner. Complete the producer interface
around it. This work does not require replacing all scalar expression lowering
or introducing a general target IR. A module extraction is justified by a
defined responsibility and dependency interface; file size alone cannot prove
that the representation handoff is correct.

## Prepared expression and stable binding

The existing prepared-operand record supplies the minimum expression result:
emitted expression, source type evidence, actual container representation,
actual optionality, and presence evidence. Retain the source expression's
identity and position for diagnostics. Source type evidence must not override
an already selected target representation.

A result belongs to one lowering environment and expression evaluation site.
Consume it directly when composing a conversion or enclosing expression.
Reusing its text or facts after changing substitutions or flow conditions
requires a new preparation. Lowering may allocate temporary names; pure
decision queries must not call lowering to discover their answer.

A binding has a separate, stable declaration representation. Each initializer
and assignment must satisfy that representation through a checked conversion.
A null initializer supplies a null value to an optional binding; it does not
make the binding's permanent storage kind `NullArrayValue`. Writes invalidate
applicable value and presence facts. They do not replace the declaration's
storage type with the current RHS's representation.

Explicitly annotated and inferred declarations must both establish agreement
between the emitted declaration and the binding record. An inferred declaration
cannot claim a read-only view while its initializer emits a mutable wrapper.
Reads combine the binding's declared type with the facts valid at that
read. Parameter reads use the body representation after entry normalization,
which can differ from the signature.

Text-only adaptation is allowed at a terminal printer. `arrayBoundaryText` can
remain such an adapter if it delegates to the authoritative producer and its
consumer neither reconstructs lost representation facts nor violates the
selected declaration. Keeping an unused result record is not evidence that
later reads consume the correct binding declaration.

## Producer inventory required before implementation

For each row, identify the selected emission rule, its result representation,
its binding/flow dependencies, and the next consumer. Existing compiler support
and source-language acceptance are separate evidence. An unverified path stays
open; it cannot be removed from the accepted language to simplify this pilot.

| Producer family | Required representation owner and review evidence |
| --- | --- |
| Local, field, and parameter read | Selected declaration and read representation; parameter body normalization and current guard facts are explicit. Cover inferred declarations and optional field reads. |
| Literal and construction | The selected target constructor determines storage. Null and contextual empty literals retain their distinct identities until materialization. Audit built-in array construction separately from constructors that cannot return an array. |
| Ordinary and specialized call | Emitted callable return representation, or the selected intrinsic/helper operation when it replaces a call. A source return annotation alone does not certify a replaced operation. |
| Cast and completed conversion | Consume the inner prepared result and return the conversion plan's result. Parentheses and metadata preserve that result; a contextual cast does not erase its actual storage. |
| Ordinary conditional | Prepare each arm under its branch environment and reconcile reachable results to one representation. Return the joined facts. |
| Structural nil-merge | One shared structural decision selects the guarded value and lazy fallback. Both operands participate in representation selection. |
| Registered default | Declaration/body plan and selected default operation establish the result. Registration or native-default placement alone proves no presence. |
| Block tail | Statement scope and tail producer determine the returned value, including any generated closure or temporary. Preserve its result representation at the enclosing boundary. |
| Switch result and pattern binding | Audit expression, assignment, and return lowering routes, destination temporaries, arm results, and payload declarations. |
| Try result | Audit `tryBindingLines`, return paths, and statement paths. Rejection in the generic expression dispatcher does not establish source-domain exclusion. |
| Nested collection element | The element producer/conversion supplies the element representation; the outer constructor independently supplies the container representation. |

The source inventory in this review identifies open owners for calls, blocks,
switches, and try result paths. P07 cannot be accepted by treating those rows
as ordinary source-type predictions. Inspect their existing alternate lowering
paths and assign a concrete adapter or demonstrate that the source specification
excludes the particular array-producing form.

## Conditional and default composition

Prepare the condition once. Each ordinary branch is lowered under its own
valid flow facts; restore the enclosing environment between alternatives.
Compile-time preparation of both alternatives must retain their runtime lazy
evaluation. Use the existing boundary plan to reconcile each produced value
with the selected destination representation.

| Operation | Required result rule | Optional result rule |
| --- | --- | --- |
| Ordinary conditional | Every reachable arm produces a required value. | At least one reachable arm can be null, and the destination permits null. |
| Nil-merge | The guarded target is already required, or the fallback supplies a required value when the target is null. | Both target and fallback can be null, and the destination permits null. |
| Parameter with native default | The selected body type and operation establish a required value. | The selected body type remains nullable; native placement supplies no additional proof. |
| Entry-normalized parameter | The normalization's possible results are all required. | A permitted normalization result remains nullable. |

Present alternatives use the common destination container representation.
A null literal represents an absent value. Empty literals
receive their element type and constructor from the result context. Do not
accept incompatible alternatives by copying one arm's storage field.

For nil-merge recognition, the arm returning the guarded target must be the
non-null outcome of the comparison. Account for both `==` and `!=`, either
comparison operand order, and either branch orientation. Reuse the existing
structural decision across its consumers, with one owner for recognition.
Its stability precondition must justify any eliminated repeated source read.
Otherwise preserve the general conditional form.

An optional nil-merge target can remain optional during preparation even when
the final result is required: the fallback may supply the required result.
Do not force that target through a required-destination conversion before the
merge has established presence. A prior valid guard can instead make the
prepared target required, in which case the fallback is unreachable. Source
`Null<T>` spelling alone decides neither case.

## Acceptance and work order

1. Complete the producer table with source owners and supported lowering paths.
   Independently review declaration representations, expression result representations, flow facts, and boundary conversions.
2. Implement the producers and conversions together. Remove superseded
   predictors and temporary diagnostics. Document any retained terminal adapter.
3. Exercise interactions that depend on the returned representation: construct
   or merge, bind, then pass or return through a typed consumer. Cover existing
   ordinary conditional and coalescing cases with both branch selections and
   empty/nonempty results. Direct collection reads alone are insufficient for
   the diagnosed mismatch.
4. Check evaluation order, lazy effects, alias visibility, and valid presence
   proofs alongside the type-sensitive interactions. Planner purity and
   repeatability remain separate checks from runtime evaluation counts.
5. Review a fixed candidate and its complete migration inventory before the
   independent lifetime exercise and full Boring/Tiqian verification. A passing
   focused run does not discharge those later gates.

## Diagnostic evidence

The inspected compiler retains Haxe source positions and some backend-specific
emission traces. The inspected output paths do not provide a unified source
range and decision trace. Current Swift output assembly joins strings and
writes completed files without carrying expression spans through that join.

Two diagnostic capabilities have distinct responsibilities:

- Source mapping associates generated ranges with original source spans and
  records synthetic output origins where a direct source range is unavailable.
- Decision tracing associates a lowering occurrence with its producer, input
  representation, flow/default evidence, selected operation, and output facts.

A source position is not a unique expression identity or a proof of dominance.
Rewrites can preserve the same source span on multiple expressions. A future
trace must preserve occurrence/parent identity and transformation origin, and
tie evidence to the compiler revision and input hashes. Trace formatting and
source-map export are diagnostic consumers; neither selects compiler semantics.

Unified diagnostic support remains implementation work. Its design must use
the prepared-result interface so the required provenance
is retained. The current representation repair and its full verification remain
required; adding a mapping file cannot establish their correctness.

## Reviewed implementation sequence

The implementation owner completed the producer inventory and a separate
executor reviewed it. The coordinator accepted the design for phased work.
Source acceptance and execution evidence remain implementation requirements.
The review reports are retained with the round's external evidence as
`representation-producer-inventory.md` and `p07-design-closure.md`.

| Phase | Concrete integration owners | Acceptance condition |
| --- | --- | --- |
| J1: Prepared values and direct producers | `SwiftArrayBoundary`; `SwiftExpr.scanLocals`, local/field/parameter reads, `callText`, `newExpr`, array literals, `castText`; `SwiftDecl`; `SwiftParameterPlan` | Declaration storage stays stable. Selected emission operations return their own facts. Ordinary callable signatures and replaced calls have explicit result owners. Casts and transparent wrappers preserve or convert the prepared result. Compile the macro implementation and inspect all migrated adapters. |
| J2: Conditional and default results | `expr(TIf)`, `optionalIfSite`, `lowerCoalescingExpression`, parameter normalization | Both branch selections reach a required typed consumer. Optional nil-merge targets convert through an optional destination representation before the required fallback joins. Preserve condition count, lazy effects, branch facts, and null-comparison polarity. |
| J3: Composed values and complete consumer migration | `blockExpression`; `switchExpression`, `switchBindingLines`, `switchAssign`, `switchReturn`, `armLines`; `blockValueLines`, `tryBindingLines`, `tryReturnLines`; terminal boundary consumers | Exercise accepted array-valued block, switch, and try routes through binding and return destinations. Each result uses that destination, independently of the enclosing function's unrelated return type. Enum captures use emitted payload declarations. Calls, constructors, enum arguments, static fields, assignments, returns, and nested elements consume the prepared result. |
| J4: Fixed candidate review | Complete changed-source manifest, producer inventory, focused harness | Remove superseded guesses and temporary diagnostics. Verify the complete focused matrix, alias behavior, evaluation order, repeatability, and typed downstream uses. Record child commands, statuses, warnings, hashes, and unresolved coverage. Independent lifetime work and full Boring/Tiqian checks follow. |

The direct call inventory includes `std.Process.args`, `std.Fs.readDir`, and
array-producing string operations in `callText` and `platformModuleCall`.
Inspect every selected replacement that can return an array. A helper's source
signature alone does not establish its emitted result. Built-in `new Array`
uses the constructor operation's storage; other constructors retain their
declared result representation unless a replacement operation changes it.

Each direct producer family needs a source fixture that constructs or reads
its value, crosses a read-only boundary, and reaches a typed consumer. Cover
field/static and parameter reads, null and contextual empty literals, nested
elements, ordinary and replaced calls, constructors, casts, and transparent
wrappers. Effectful inputs must expose evaluation count and order. Record the
actual accepted source route for block, switch, and try fixtures; a generic
expression rejection cannot exclude their binding or return routes.

J1 can leave composed producers pending J2/J3, with those entries explicitly
recorded as unaccepted. Its intermediate compile result cannot establish
end-to-end correctness. The coordinator reviews each phase's actual diff and
remaining migration entries before assigning the next phase. The executor
must report a missing owner or a contradictory source rule or target representation before adding a new
prediction or treating an accepted form as unsupported.

Retain a lightweight occurrence reference and source position with each
prepared result. Conversions and composed results retain their input lineage.
This supports later diagnostics; it makes no claim to reconstruct provenance
already lost before Swift lowering. Full normalization lineage and generated
range export remain separate work. Evaluation correctness is established by
the selected operation and composition rules; a generic boolean field cannot
serve as proof that an expression is pure or safe to duplicate.
