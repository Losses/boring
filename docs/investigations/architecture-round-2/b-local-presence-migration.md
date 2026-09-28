# B2: Local presence analysis and Kotlin adoption

## Decision and scope

This is the coordinator's implementation contract, based on source inspection
at `02fce867`. The preceding external design reports remain unaccepted. They
identified useful consumers but contained incorrect transfer rules, incomplete
function entry coverage and an unsupported expansion into field alias analysis.

Implement an authoritative source-local presence analysis and its Kotlin
consumers. The shared analysis knows typed source operations and evaluated
paths. Kotlin retains storage, promotion, extraction and produced-value decisions.
Other target adapters and field alias analysis remain programme obligations.
This assignment does not establish acceptance of package B as a whole.

## Shared analysis contract

The analysis input is one prepared function body, its parameters and a summary
of captured bindings that may be assigned. The result owns the body identity,
facts at evaluated uses, reachable exits and diagnostics for unsupported facts.
Queries are pure. They do not render expressions or mutate an emitter's maps.

Local binding identity uses the typed variable identity within the body.
Presence is `Present`, `Absent` or `Unknown`; reachability is separate. Join
reachable alternatives: equal presence remains known and differing presence
becomes unknown. Assignment replaces the binding's fact after evaluating its
operands. Definition provenance uses finite source sites, without allocating
a new identity each time a loop is analyzed.

Record evaluation occurrences, including separate operands inside expressions.
Physical node lookup requires both stable nodes and unambiguous occurrences.
If a rewritten or reused node cannot be mapped to its source occurrence, return
an explicit unknown result. Source positions support diagnostics only. Never
equate a query about `x.field` with presence of its root binding `x`.

Establish presence from a justified source producer or an evaluated guard.
An explicit null remains absent through a contextual non-null annotation.
A constructed object, literal or array has its applicable source guarantee;
an unknown call result requires its producer contract before gaining a fact.
Target nonoptional storage can make a native read legal independently of this
source analysis. Keep that target decision explicit.

Apply the short-circuit transfer table in
[the policy contracts](../../compiler-policy-contracts.md). Evaluate operands
in source order, propagate their effects and retain both reachable exits.
Only supported comparisons against the null literal refine these facts.
Do not infer presence from an arbitrary inequality or from the order of source
positions. Leaving a block removes its declarations and retains writes to
outer bindings.

For the first implementation, use conservative loop analysis. Compute all
bindings the condition, body, increment or invoked unknown effects may assign.
Remove their incoming facts before analyzing repeated uses. Conditions and
body guards can then establish facts for the current iteration. Join actual
reachable condition-false and break exits; never restore the entry environment
as the loop result. Preserve continue destinations and distinguish loops that
can execute zero times from loops that execute their body first.

Unknown calls invalidate captured bindings that may be assigned, including
captures whose closure was declared outside the current loop. Creating a
closure does not execute its body. Analyze each nested body in its own context;
do not inherit mutable captures' current outer facts as guarantees at a future
invocation. Constructor calls and accessor effects require the same care.

Try regions must account for effects before an exceptional exit. A conservative
handler entry can discard facts for every binding the protected region might
assign, then join normal and handler exits. Preserve return, throw, break and
continue destinations. Unsupported effects produce conservative facts without
rejecting admitted source or inventing a successful normal exit.

## Prepared function and target ownership

Introduce one Kotlin preparation artifact per function emission. Create it
before the declaration's return-shape query and reuse it for body rendering.
It owns the normalized tree and shared source analysis. Required preparation
includes the existing default-argument, pipeline and enum-query expansions,
with explicit ownership of declaration fusion and loop regrouping. Retain the
existing value-wrapper exclusions when normalizing.

`matchInterval` identifies a target loop form; it is not a source AST rewrite.
Keep that distinction when moving preparation. Later target construction can
retain an origin reference or return unknown for a synthetic use. It must not
silently invalidate node-based facts by rewriting their source tree.

Review every entry below, including context restoration on exit:

| Entry | Required responsibility |
| --- | --- |
| `KotlinDecl.funcDecl` | Prepare before `bodyUsesSafeCallReturns`; pass the same artifact to `functionBody` |
| `extractedFuncDecl`, `flushEntryDecl`, `testFuncDecl` | Create their own artifact and preserve existing declaration and test-wrapper contracts |
| `valueTypeFunctionBody` | Preserve parameter naming and use the member's prepared context |
| `initBlockStatements`, `valueTypeConstructorBody` | Analyze constructor operations and preserve the origin of operations selected for emission |
| `functionLiteral`, `functionLiteralNamed` | Enter a separate body context and restore the enclosing context afterwards |
| Static initializers and other expressions outside a prepared body | Return explicit unavailable flow information; never reuse the previous function's facts |

Kotlin's `nonNullLocals` currently mixes guard facts and facts recorded while
printing extractions. Replace source-local proof consumers with the shared
result. A printed extraction is insufficient authority for a lasting source
fact. Target-produced guarantees retain their value, evaluation point and
invalidation boundary. Storage maps and native promotion checks keep their
target responsibility. A whole-function write set approximates Kotlin
promotion; the target language defines the actual conditions.

The first shared domain is locals. Inventory the remaining field consumers and
keep their transition explicit. A field-path fact requires its own invalidation
contract; deferring alias analysis cannot justify treating different paths as
disjoint. Do not expand the shared domain by copying the mixed `nonNullFields`
store into it. Remove local source-position proofs and duplicated local
simulation only after every local consumer uses the new result. Syntactic
null-test membership used to choose declaration storage remains a separate
query and must not become a presence proof.

Migrate `nullableAccess`, `provenNonNull`, `guardedNonNullTernary`, local inputs
to `rendersNullable` and `nullableChainHop`, and `bodyUsesSafeCallReturns`
coherently. Return widening remains a target-produced-shape decision using
these facts. On unknown source presence, preserve a justified general operation
for the actual storage and source-defined behavior. Legal target syntax or a
destination's non-null requirement alone cannot justify an extraction.

## Delivery and verification

One writer owns the shared analysis and Kotlin adoption. Before changing the
consumer boundary, submit the concrete result types, preparation call sites,
remaining source rewrites and field transition inventory. This is a coordinator
interface check. Once agreed, implement within the exclusive assignment.

Use independent source cases to verify skippable and dominating guards,
assignment after a guard, a writing right operand of a short-circuit condition,
reachable joins with exiting arms, loop-header invalidation, captured writes
through calls, and separate nested-function contexts. Include a nullable field
behind a present root to detect root/field proof conflation. Test ordinary and
fixed-contract returns so declaration shape agrees with body operations.

Observations of the analysis may establish facts on paths whose dereference
would be undefined. Native tests must use source-defined inputs and outcomes.
Retain source admission, selected fact, emitted operation, native compile,
runtime and warning evidence separately. Reuse the accepted child recorder and
stage checker; the B1 replay's verdict repair remains independently owned.
Do not write another capture implementation or enlarge the expected-failure
set to hide a changed consumer. Full candidate Boring and fixed Tiqian checks
remain required after integration.

## First interface review

The executor's checkpoint against `0fb5d1fa` preserves the intended shared
source analysis and Kotlin preparation owners. Consumer changes remain pending
review. The coordinator found contradictions between the stated rules and the
checkpoint's own traces: after an outer null guard, the surviving non-null arm
and the null arm join to unknown. Returning from a nested arm does not remove
the outer null arm. A use inside a guard's true arm, however, has the guard's
presence fact even when the incoming loop fact was unknown.

These trace errors violate the existing transfer contract. The correction is
to derive each use from its actual incoming edges and independently verify
the expected facts before implementing consumers. Repeating the correct join
rule beside an incorrect trace does not establish an implementation design.

The review also required concrete inputs for inherited capture facts and for
return-shape prediction before printing. A prepared artifact's method name
alone does not specify those inputs. Presence of a constructed result and the
effects of executing its constructor are separate decisions. Retained field
guard facts remain source-flow facts even while their implementation stays in
Kotlin; removing mixed proof snapshots must preserve their field portion until
that responsibility migrates. These interface and transition obligations
remain within the assigned local domain.

## Addendum review and implementation boundary

The revised checkpoint still derived presence from a declared non-null result
or binding type, with those predicates renamed as producer contracts. A reason
label needs an applicable source rule and its premises. Reference parameters
and calls remain unknown when their declarations supply no such guarantee.
Local reads transfer the current environment fact, including absence.

The coordinator returned concrete controls for explicit null assignment,
unknown call results, and two different present values joining to present.
Closure creation and closure invocation require separate effect transfers.
Capture facts need a complete enclosing assignment analysis; the first bounded
implementation may enter captures as unknown while that input is unavailable.

The context-restoration example also returned before restoring the successful
path. Every scoped entry must restore state on both normal and exceptional
completion. Return-shape planning must consume the target storage decisions
that rendering will use. Move required decisions into preparation when their
current implementation computes them during printing.

Pure analysis and independent fixtures remain assigned. Kotlin consumer
migration waits for those concrete facts and the corrected preparation inputs.
The next delivery is implementation evidence against these controls; another
general design report does not satisfy that boundary.
