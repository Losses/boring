# J: Prepare Swift array boundary decisions

## Status and purpose

The owner selected shared alias visibility for ordinary read-only conversion.
Feature 18 now states that ruling. This revised brief includes the Swift
representation and runtime changes required to preserve it. A single assigned
executor may implement the scope below after recording its starting revision.

The executable baseline is `e3b8bab39ac2da0e17e9d04e031f03bd39290274` in the
owned `boring-wt-architecture` worktree. Record its current documentation
commit before executing. Tiqian validation uses the separately locked
`architecture-workspaces/tiqian-validation` checkout at
`8504d230228e8206689a2049bbb84b671c1f079a`.

The objective is one explicit conversion decision consumed at every applicable
Swift array boundary. Acceptance requires consistent decisions and preserved
evaluation behavior across positions. Removing the two observed diagnostics
alone does not satisfy this task.

## Evidence and cause

Read the investigation record, A revision 2, D revision 2, and H. The observed
optional-local failures follow `SwiftExpr.functionBody`, `blockLines`, and
the `TVar` branch of `stmtLines`. At baseline lines 759 through 782:

- An optional mutable source is wrapped in `Array(source)` without handling
  the optional value before conversion.
- A guarded source renders as `source!`, converts to `Array(source!)`, then
  receives another unwrap based on the original source type.

The source type, the current Swift value representation, and the destination
requirement are distinct. Current local rendering combines those decisions
without recording the conversion result. Other consumers independently make
similar decisions; some detect prior conversion by inspecting generated text.

## Design record

The [prepared-value design](j-prepared-value-design.md) records the producer
design review after the conditional-result failures. Independent review approved
phased implementation on 2026-09-28. Follow its phase assignments and review
conditions. It specifies declaration stability, expression producer coverage,
branch/default composition, and the required interactions for acceptance.

Lower `ReadOnlyArray<T>` to a public Swift type named `ReadOnlyArray<T>`,
retaining the exact existing
`TiqianArray<T>` object. Forward count, indexed reads and iteration to that
storage. Keep the backing object private and expose no mutable slot API.
Apply the implementation standard's runtime naming rule to the declaration,
type mappings, conversion rendering, and fixtures. Record the existing mutable
wrapper's branded name separately with its compatibility obligations.
J's naming acceptance covers the new view and every reference to that view.
The existing mutable wrapper and exception names remain inventoried migration
work. Acceptance of J establishes no complete runtime naming conformance.
Fresh array construction may allocate fresh backing storage; conversion of an
existing mutable value must retain its storage. Preserve existing element
identity and equality rules, optional values, and storage lifetime.

Update both ordinary and substituted type rendering. Audit generated field
comparisons, runtime algorithms, module visibility, and public Swift signatures
that currently require native arrays. Name every required adapter and its
source specification before implementing it. Decode-specific protection remains
governed by feature 18. Runtime view construction cannot substitute for a
separately specified mutation protection. Reverse read-only-to-mutable conversions
retain their existing source acceptance and require separate analysis if this
representation change affects them.

Prepare a target-owned decision before rendering a conversion. It records:

1. Source container identity and element type from the typed Haxe input.
2. The prepared operand's actual Swift container and optional representation.
3. The applicable flow fact and the operand to which that fact applies.
4. Destination container, element, and optional requirements.
5. The selected operation, required operand evaluation, and result representation.

Use a small typed result with explicit alternatives and an immutable result
type. Document the producer of each fact. An AST type is insufficient when
a previous conversion or narrowing has changed the emitted representation.
Record a completed conversion so a later consumer can use its result directly.

Keep expression results, binding representations, and flow facts distinct.
A null initializer describes that expression's value; a nullable array binding
still has a declared container representation when present. Reads use that
binding representation and the flow facts valid at the read. Initializer facts
cannot be cached as the binding's permanent value state. The parameter
declaration producer must also provide its selected representation to body
lowering, including whether a default has already supplied a required value.
Assignment, branch exit, and captured mutation must respect each fact's
invalidation rule.

The operand producer returns emitted text with its established representation.
Use the following provenance requirements when reviewing that producer:

| Operand operation | Evidence for the returned representation |
| --- | --- |
| Primitive local, field, or parameter read | The declaration's target mapping and any applicable flow fact agree with the selected read operation. |
| Literal construction | The selected construction determines storage and contextual element type. |
| Completed conversion | The conversion's result type supplies the representation for the next consumer. |
| Guarded extraction | The valid guard applies to this operand and the selected extraction produces a required value. |
| Default selection or branch merge | The selected lowering reconciles both alternatives and preserves lazy evaluation; the existence of default metadata alone proves no materialization. |

Keep operation selection and its returned facts together. A separate predictor
that guesses what a later renderer will select creates a second decision owner.
An unavailable optional optimization must retain the valid general lowering.
If accepted source has no valid lowering, report the missing rule for review.

State when preparation occurs relative to the first operand rendering. Queries
that prepare facts cannot call `expr` to discover those facts. Operand lowering
may produce both text and its established representation once; subsequent
consumers use that result. Argument default substitution must have a defined
preparation environment. Reuse a plan only while that environment and its flow
facts remain valid; changed substitutions require an explicit new preparation.
Test query repeatability and state preservation separately from runtime operand
evaluation. Repeated compiler rendering alone does not prove repeated runtime
evaluation.

The renderer consumes that decision and one prepared operand. It does not infer
conversion state from `TiqianArray([])`, `.map { Array($0) }`, a trailing `!`,
or another generated fragment. Empty literals carry their identity and required
element type structurally. Optional extraction applies to the representation
that actually exists at that step. Preserve exceptions and evaluation order.

Keep Swift representation policy in a focused module such as
`swiftcompiler/SwiftArrayBoundary.hx`. The shared source classifier remains
`StaticFieldHelper`; a common classifier can be extended only after the
five-target comparison establishes the same source question and answer.
Shared modules must not emit Swift text or branch on target identity.

A general target AST is outside this task. The conversion decision may coexist
with existing text emission while its inputs and outputs retain explicit facts.
Reject a proposal that adds another helper inside the large expression file
while leaving its consumers responsible for independent conversion decisions.

## Ownership and migration

One executor owns this compiler change. The initial file set is:

- `packages/compiler/reflaxe/swift/swiftcompiler/SwiftArrayBoundary.hx` for
  the focused representation and conversion specification.
- `SwiftExpr.hx` in that directory for preparation and expression consumers.
- `SwiftDecl.hx` in that directory for static fields and declaration consumers.
- `SwiftType.hx` for ordinary and substituted container types.
- `SwiftRuntime.hx` for shared storage, the public read-only view, and required
  collection or conditional equality operations.
- Focused Haxe fixtures, HXML entries, native harness, and a Bun-discovered
  `.test.ts` entry under `tests/swift-readonly-boundary/`. This separate directory
  avoids the existing SwiftPM vector target rooted at `tests/swift`.

Use an actual Haxe oracle and the generated Swift program on the same source
observations. Keep these focused fixtures outside shared sample discovery.
Ordinary aliasing is a shared rule; target exclusions cannot classify it
as inapplicable because another backend has not implemented it. Empty
assertions on another target do not supply semantic evidence.

The coordinator owns specifications and guidance. No other executor writes
these compiler files concurrently. Additional runtime registration or import
files require a named need and an updated file assignment before editing.
Every added file must serve a named responsibility.

Inventory and migrate locals, static and instance fields, assignments, returns,
casts, nested literals, function arguments, constructor arguments, defaults,
enum payload construction, coalescing, and branch results. Enum construction
uses `enumConstruct`, which directly renders payloads and bypasses ordinary
argument conversion. Verify source acceptance through interception before
classifying a proposed payload case as supported. Record each consumer as migrated, delegated to
another listed consumer, or outside the supported source domain with evidence.
Do not silently defer `SwiftDecl` while claiming a complete boundary mechanism.

## Tests and acceptance

For each applicable position, vary plain and optional sources and destinations,
including a guarded optional source reaching a required destination. Include
empty and nonempty values, absent and present optional values, nested elements,
and default selection. Distinguish omitted arguments from explicit null.
Vary optional containers independently from optional elements: include both
`Null<ReadOnlyArray<T>>` and a present `ReadOnlyArray<Null<T>>` containing mixed
null and non-null elements.

Use runtime counters and ordered observations to test evaluation count and
order. Counting the operand's spelling in generated text is supplementary
evidence. Add a case where conversion interacts with another argument's effect
or a throwing operation when the source subset accepts that form.

Alias expectations follow feature 18's ordinary conversion ruling. Retain the
scalar probe that distinguishes the existing Haxe and Swift behaviors: a
retained mutable alias updates both the visible element and length. Include an accepted
reference-element case that distinguishes copying container slots from copying
element objects. Its expectation requires an applicable element-identity
rule; report a missing ruling before claiming semantic completion.
Use an ordinary class element with mutable state to exercise reference identity;
a data-class value record does not establish that case. Existing interface
identity fixtures provide a separate source of evidence for reference equality.
Require both an element-field update through the original object and replacement
of its array slot with a different object after conversion. The first checks
element sharing; the second distinguishes shared container slots from a copied
container that still refers to the same elements.
Tests must exercise generated target code.
Do not repair expected values, input programs, or generated output to hide a
translator failure.

Run focused fixtures during implementation. At a fixed candidate, collect fresh
generation manifests and target diagnostics, then perform the required Boring
verification once. Compare baseline and candidate generation with identical
source fixtures for each target. Preserve unaffected output for the unchanged
common fixture set; review explicitly named fixture additions separately. An
older manifest from a smaller fixture set cannot establish an unexpected output
change. Swift-only runtime regressions may provide focused evidence, but they
do not establish all-target conformance. Record ordinary aliasing gaps on other
targets without weakening their tests or silently changing their implementation.
Preserve successful
compiler output because the current bundle driver discards it. Require zero
warnings attributed to generated files and no suppression markers.

Select a working capture route before the full command: either record child
tool output before the driver receives it, or use reviewed driver changes that
persist each step's output. An outer redirect alone is insufficient. Validate
the selected route with a successful command that writes to both streams and
a failing command whose status and diagnostics must survive. Any driver code
change requires its own file ownership and acceptance brief.

Tiqian generation compatibility is a prerequisite for the later consumer suite.
Its driver and effective haxelib compiler are separate recorded identities.
Verify the HXML include paths and explicit backend and runtime class paths as
well. Tiqian's existing HXML files refer to `.haxelib/boring/git` directly;
overriding `-lib boring` alone does not establish candidate backend identity.
One approved compatibility generation succeeded at Boring `483974d6` and
Tiqian `8504d230`, with actual candidate module paths captured. It establishes
generation compatibility for that pair only; no Tiqian regression result has
been established. The new implementation needs its own candidate evidence. Follow the work
plan's full consumer verification requirement after compatibility succeeds.

## Delivery and coordinator review

Deliver the decision specification, consumer migration table, changed-file list,
fixed candidate identity, commands with statuses, retained logs and manifests,
and remaining gaps. The coordinator independently checks at least one ordinary
case and one interaction not singled out by the initial diagnostics.

Review asks whether later consumers still need to rediscover facts or recognize
emitted text. Return such a delivery to the executor with the violated rule.
Record whether each failure came from missing guidance, ambiguous authority,
an execution deviation, or insufficient verification. Update the existing
method only where the review exposes a missing general instruction.
