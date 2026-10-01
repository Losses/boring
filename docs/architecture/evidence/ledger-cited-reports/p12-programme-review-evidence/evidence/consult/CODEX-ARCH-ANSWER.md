# Independent architectural judgment

Read-only consultation on 2026-09-30, against HEAD `e1c6597514634fd347d392709793cc19bd96c9a2` and the existing working-tree changes. I read the original brief, SOL-ANSWER.md, all four required repository documents, both review reports, and the relevant Swift source. I ran no builds or tests.

Version qualification: RECORD.md changed during this inspection. I first read a 186-line version containing four corrections, then a 279-line version containing eight, SHA-256 `0ac047d6c34ae12fc8a9fad2f7d8da6810213a45d950b7b44bdb0d5203976eaf`. Both review reports identify an earlier 131-line version. My assessment distinguishes the earlier review failures from the later record. The four required architecture documents, SwiftExpr.hx, and SwiftArrayBoundary.hx retained the same hashes across my checks.

## PART 1 — Independent verdict on the six original questions

### 1. Is the diagnosis correct?

**Partly. The blocker is failure to make the approved fact handoffs hold throughout the selected migration.** Naming a producer and obtaining agreement between outputs are both insufficient.

I agree with SOL that “no mechanism has a defined producer” overstates the evidence. The approved J design already distinguishes declaration selection, expression lowering, boundary selection, and emission, with concrete integration owners. The responsibility survey itself names existing producers such as FloatPrecision. The policy interface document also records integrated source-container, presence, comparison, and diagnostic work. These have different acceptance limits; they cannot fairly be collapsed into “nothing architectural has happened.” [Prepared-value responsibilities](/home/losses/Development/tq-workspace/boring-wt-architecture/docs/investigations/architecture-round-1/j-prepared-value-design.md:24), [named APIs and consumers](/home/losses/Development/tq-workspace/boring-wt-architecture/docs/compiler-policy-interfaces.md:27).

The concrete defect is an interface that accepts representation facts while its callers can still fabricate those facts independently of the operation that emitted the value. At SwiftExpr.hx:2687–2691, text comes from expression lowering, while storage usually comes from classifying `e.t`. The compiler therefore has a record with the required field names without the required guarantee. An independently reviewed design has not yet become an enforced implementation contract.

The “verification versus architecture” diagnosis also needs narrowing. Verification infrastructure belongs to responsibility F, and behavior tests can assert source semantics. That work is useful. The mistake is letting a result establish more than its observation supports: cross-target agreement cannot prove coverage, correct ownership, or correct semantics for unobserved compositions. Likewise, attributing all 48 failures to the baseline establishes a bounded non-regression result, not a passing required suite.

The tracked-source mutation concern is real in the inspected code: `runHaxe` writes the stub at line 75 and restores it only after the awaited subprocess completes, at line 85. There is no cleanup guarantee around that interval. Moreover, even successful restoration would conceal the transient input substitution from a simple before/after hash comparison. I have not established which historical runs were affected or how a particular timeout interrupted execution. Those require execution records. [Package test helper](/home/losses/Development/tq-workspace/boring-wt-architecture/tests/ts/package-artifacts.test.ts:58).

### 2. What is the single next architectural move?

**Decision: require a candidate-specific Swift array handoff conformance case under P08, using the already approved P07 design as its contract.**

I differ from SOL's recommendation to make acceptance of a new boundary policy record the next milestone. The ordinary shared-storage ruling and producer design already exist. Another narrative record can restate them while misidentifying the implementation, as this consultation demonstrates. The next artifact must establish agreement between that design and an exact candidate.

That conformance case must have an independently fixed domain: the accepted source forms and producer families in feature 18 and the J design. For each family and result position, it must identify the actual lowering route, the operation that establishes the result facts, the relevant declaration and flow environment, the destination requirement, the subsequent consumer, and any reconstruction being removed. Delegation, partial migration, and unverified source reachability must be separate statuses.

Its central invariant is: **the operation that produces an array value establishes its actual representation; every subsequent handoff preserves that representation and applies requirements from the actual destination.** Alias visibility, lifetime, absence, evaluation count, and lazy effects remain obligations of the same translation.

It is complete as a design-to-candidate assessment when an independent reviewer can account for every required family, classify every remaining contradiction, and distinguish a reviewable checkpoint from a conforming mechanism. It supports P08 closure only after the required implementation and behavior reviews pass. A pending required family prevents complete J acceptance; it does not become unsupported source. The approved J1–J4 phases permit intermediate progress with explicit pending entries. [Phased acceptance](/home/losses/Development/tq-workspace/boring-wt-architecture/docs/investigations/architecture-round-1/j-prepared-value-design.md:185).

This decision does not require a universal target IR or complete diagnostic tooling. Direct source inspection and retained evidence can establish the bounded contract. It requires a demonstrable handoff, not another assertion that a helper is the owner.

### 3. Is work order 1–4 still right?

**Keep the dependency order; reject a programme-wide requirement to finish Swift first.**

Source semantics and representation distinctions precede conversions. Evaluation facts support string and null reasoning. Result construction depends on agreed representation and flow interfaces. The five earlier repairs do not invalidate those dependencies.

However, the current work plan explicitly says that the unfinished Swift pilot is no longer a prerequisite for other policy migrations. SOL's “hard architectural gate” reading is too broad if applied to the whole programme. The architecture permits A, B, C, E, and F to begin interfaces and inventories concurrently, and permits independent implementation after the required interfaces agree. D follows the A and B interfaces it actually needs. [Current programme scope](/home/losses/Development/tq-workspace/boring-wt-architecture/docs/architecture-work-plan.md:5), [package dependencies](/home/losses/Development/tq-workspace/boring-wt-architecture/docs/compiler-policy-architecture.md:98).

The gate belongs at a dependent handoff: a consumer cannot proceed on invented representation or flow facts. It does not require unrelated work to wait for every Swift path. Existing repairs should retain their bounded evidence and enter a coherent candidate; neither their existence nor their count completes the boundary mechanism.

### 4. What must P08's independent reviews mean?

**P08 accepts a conforming implementation candidate for subsequent full verification. It cannot close through approval of a document alone.**

I agree with SOL's distinction between reviewing behavior and reviewing implementation. I would make the acceptance condition explicit:

1. **Behavior review:** derive the expectations and required case families from the source specifications and accepted brief. Verify source/interception acceptance, a discriminating oracle, and observations that expose representation, aliasing, lifetime, null/default behavior, and evaluation effects. Reading elements successfully is insufficient where two incompatible representations support the same reads.
2. **Implementation review:** independently reconstruct the lowering routes from source dispatch and definitions, including delegates, alternate statement routes, and declaration emitters. Verify that each selected operation establishes its own output facts, uses the actual destination, and preserves the environment in which proofs apply.
3. **Agreement:** both reviews identify the same candidate bytes, required scope, and evidence. Every required handoff is accounted for; finite decisions have defined outcomes and precedence; no unexplained competing decision remains within the migrated scope. Retained terminal text adapters have an explicit justification.
4. **Failure treatment:** an accepted source form with missing lowering remains a compiler obligation. A known violating route can be recorded in a checkpoint, but cannot be silently excluded from the mechanism's completion claim.

The independent reviewer needs an independently derived denominator. Counting only the sites an author supplied repeats the author's coverage error. Useful negative controls must establish that the production acceptance procedure rejects a missing route, a contradictory fact, or the wrong destination for the intended reason.

The work plan's line 134 reports the current open status; it should not create a circular dependency in which P08 needs final P09 acceptance before a candidate can be selected for P09. The more specific dependency text places focused candidate acceptance before final verification, and places P10's final reflection and P12 after it. [Gate text and dependencies](/home/losses/Development/tq-workspace/boring-wt-architecture/docs/architecture-work-plan.md:216).

### 5. What is the minimum evidence for P09?

**One accepted candidate, one fixed Boring/Tiqian input pair, and complete evidence for both required check sets.** “Minimum” means avoiding duplicate execution; it cannot mean omitting a required gate.

| Evidence | Minimum content |
| --- | --- |
| Candidate and inputs | Exact revisions and consumed working-file bytes; toolchain, defines, driver identity, fixtures and transformed configurations; unchanged relevant inputs or a demonstrably immutable execution copy. |
| Boring | Fresh focused conformance evidence; the complete required root verification procedure; all ten configurations actually declared in boring.json; required unchanged-output comparisons and any additional affected-interface checks. |
| Tiqian | The pinned consumer revision, presently specified as `8504d230228e8206689a2049bbb84b671c1f079a`; all twelve generation and eleven target-test obligations; the engine and protocol comparison groups with their independently established test-ID sets. |
| Actual routing | Observed candidate compiler/module paths during generation, covering explicit HXML includes, backend, standard-library and runtime paths; driver compatibility established for this candidate. A haxelib mapping alone is insufficient. |
| Outcomes | Retained commands, child stdout/stderr, numeric statuses, generated-output identities, warning results, and post-run input checks. Expected stages and test sets must be established independently of successful output. |

The current root `verify` script extends well beyond the driver comparison. Its required checks must be expanded before scheduling so a matrix is executed once where appropriate. Tiqian's protocol-C bundle retains its generation obligation even though it has no target-test obligation. Engine and protocol outputs must be compared within their agreed domains. [Root command](/home/losses/Development/tq-workspace/boring-wt-architecture/package.json:47), [consumer obligations](/home/losses/Development/tq-workspace/boring-wt-architecture/docs/investigations/architecture-round-2/tiqian-preparation-review.md:23).

A complete failure record can be excellent evidence and still fail acceptance. The 48/48 baseline attribution cannot waive required failures, and generated-code warnings or suppression markers remain acceptance failures under the repository standard. Stable hashes also cannot rehabilitate a run whose harness temporarily substituted unrecorded compiler inputs. [Acceptance rules](/home/losses/Development/tq-workspace/boring-wt-architecture/docs/architecture-work-plan.md:415).

If Tiqian is absent locally, P09 remains pending consumer evidence. An authorized external or CI environment can legitimately supply that exact evidence; local absence is not proof that execution is impossible. Freezing the candidate, completing Boring evidence, and preparing the consumer execution contract are legitimate progress. Neither preparation nor an old consumer result passes P09. I have not checked current Tiqian availability or independently audited the cited regression bundles, so I make no availability or pass claim.

### 6. What risk is most likely being missed?

**The implementation is being allowed to determine the language and acceptance domain against which it is judged.**

The strongest warning is RECORD.md's exclusion of any position it has not listed. That lets incomplete discovery reduce the obligations. The J design expressly prohibits that move. The test helper's temporary replacement of assertion-bearing source with no-op methods is another instance of changing the measured program to accommodate an emitter problem.

This risk extends SOL's diagnosis of semantic fragmentation: even a compiler with fragmented facts can appear complete if the author also controls which source forms, expected values, and routes count. An acceptance process can then improve its reports while reducing the behavior it demonstrates.

The accepted language and semantic oracle must have authority independent of the implementation inventory. Missing accepted paths stay open. An implementation correction cannot supply its own exemption. [Open-path rule](/home/losses/Development/tq-workspace/boring-wt-architecture/docs/investigations/architecture-round-1/j-prepared-value-design.md:81).

## PART 2 — Reaction to the failed review

### (a) Was NOT-ACCEPTABLE the right verdict?

**Yes. Keep NOT-ACCEPTABLE for an acceptance-ready record.** The findings affect semantic authority and coverage, not merely citation presentation. A useful draft or checkpoint can be retained without qualifying as an accepted mechanism.

Several defects survive the later corrections:

- **The semantic ruling is inadequate.** Feature 18 requires shared container storage, visible alias mutations, one source evaluation, retained lifetime, and unchanged element identity. A target storage enum cannot define those source observations. Section 1 still substitutes a description of boundary detection for this ruling.
- **The domain remains wrong.** Limiting accepted positions to the record's own inventory conflicts with the approved design. Limiting a report's inspected scope is legitimate; deleting obligations from the accepted language is not.
- **The producer attribution remains conceptually wrong.** `sourceStorage` explicitly classifies source syntax. It is not the general producer of actual emitted storage. `prepare` produces a conversion plan; it does not retrospectively certify the facts its callers supplied. [Classifier and planner](/home/losses/Development/tq-workspace/boring-wt-architecture/packages/compiler/reflaxe/swift/swiftcompiler/SwiftArrayBoundary.hx:147).
- **The decision specification remains incomplete and overlapping.** Adding a refusal row beneath an existing “any/pass through” row requires a precedence rule or replacement of the earlier row. The new blanket presence-veto row also overstates the code: an optional operand with NoPresenceProof can legitimately convert to an optional destination. The actual veto concerns a nullable source reported as required without an admissible presence explanation.

The unconditional “already converted means never convert again” row is independently wrong. A value already represented as a read-only view may legitimately require a subsequent conversion to a mutable destination. The planner selects that conversion. Avoiding a duplicate operation depends on current representation and the next requirement, not on whether any conversion has happened historically.

**The review was too lenient in some positive conclusions.** GLM's endorsement of the one-producer table and Qwen's statement that the mechanism itself needs no correction go beyond what their own findings establish. A centralized planner can be sound while its inputs, destination context, or composition are wrong.

I also correct two structural claims using the source:

1. **The boundary references are in `armLines`, not directly in the body of `switchReturn`.** The actual chain is `switchAssign` or `switchExpression` → `switchReturn` → `armLines` → `arrayBoundaryText` → `lowerArrayBoundary`. `switchReturn` itself has no direct boundary reference. Transitive consultation exists, so zero direct references cannot prove bypass. However, `armLines` selects conversion using `currentReturnType`; `switchAssign` then rewrites the return text into an assignment without supplying the target's type. Routing through the planner does not establish correct routing of facts. [Switch adapters](/home/losses/Development/tq-workspace/boring-wt-architecture/packages/compiler/reflaxe/swift/swiftcompiler/SwiftExpr.hx:5508), [arm decision](/home/losses/Development/tq-workspace/boring-wt-architecture/packages/compiler/reflaxe/swift/swiftcompiler/SwiftExpr.hx:5615).
2. **Try-body explicit returns and try-result tails are different routes.** Ordinary returns inside a try statement can reach line 811. But `tryBindingLines` and `tryReturnLines` both obtain normal tail text from `blockValueLines`, which calls `expr(parts.value)` at line 5168. They then construct the assignment or return from that text without explicitly reconciling the tail against its destination. The later correction's blanket claim that try tails reach the producer is still unjustified. [Try-result construction](/home/losses/Development/tq-workspace/boring-wt-architecture/packages/compiler/reflaxe/swift/swiftcompiler/SwiftExpr.hx:5160).

SwiftDecl also calls `prepare` and `render` directly, independently of the SwiftExpr wrapper. This is a legitimate arrangement if both integrations obey the same contract. It disproves the claimed single coordinating function; it does not by itself prove competing conversion policies.

Finally, the AST-type ban needs precision. Source types legitimately inform declaration selection and primitive lowering whose selected operation guarantees the mapping. The repository prohibits using them to certify arbitrary results after lowering or conversion. The general fallback at line 2689 lacks that operation-specific guarantee. Correcting the ban's wording cannot make that fallback conform.

These are static findings. I have not executed source witnesses establishing every proposed switch/try combination's reachability through Haxe typing and interception, or reproduced their generated-code failures.

### (b) What does this say about the acceptance model?

**Retain decision records and independent review, but replace narrative structural certification with conformance to explicit handoff contracts.**

The reviews worked as a rejection control: they caught defects before acceptance. Two author errors do not prove that independent review is useless or that a whole-compiler replacement is warranted. They do show that asking an author to declare a complete structure, then asking reviewers to find omissions, can continue indefinitely without producing a stable basis for closure.

A structural acceptance claim needs two independently rooted accounts:

- The **required account** comes from the accepted language, normalized producer families, destination positions, and contract invariants.
- The **actual account** comes from definitions, dispatch, delegates, fact-store writers/readers, and the candidate's observed lowering behavior.

Acceptance compares those accounts. The author's prose cannot define both. Source-aware enumeration should retain function identity and delegation; grep occurrence counts cannot establish function ownership, absence of alternate routes, or semantic correctness. Mechanical checks should cover enumerable obligations, while independent judgment establishes the source oracle and the validity of each transition.

The architectural interface should make produced facts travel with the selected operation and make the destination explicit. This gives review a stable object to inspect. The current pure boundary planner remains useful; the missing guarantee lies around it. This is the bounded prepared-value design already authorized by the repository.

The latest record weakens its negative condition to “every known re-derivation is either eliminated or individually ruled on.” That can support a truthful checkpoint. It cannot close a migration by granting acknowledgments to known violations. The wrong destination and lost produced representation already have governing design rules; they are implementation nonconformance, not necessarily requests for new semantic rulings. Existing contractual obligations must survive the acceptance process.

More reviewers or more corrections may find further defects. Neither is the single structural remedy. The remedy is a contract whose domain and handoffs do not change when a counterexample is discovered.

### (c) Is there a structural reason ownership is difficult here?

**Yes: lowering, representation prediction, flow state, result intent, and text construction coexist without a consistently preserved interface.**

| Structural feature | Why ownership becomes ambiguous |
| --- | --- |
| String and line-array results | Most lowering helpers return text. Actual storage and result intent can disappear before an enclosing consumer uses the result. |
| Ambient context | `currentReturnType`, substitutions, parameter-default state, and narrowing maps influence emission. A function's arguments do not fully reveal its dependencies. |
| Several routes for one source construct | Expression, binding, assignment, return, and statement dispatch can reach different helpers. A search at a dispatch site cannot establish what the delegated producer does. |
| Prediction after lowering | `expr(e)` selects emission, while a separate classification of `e.t` purports to describe it. Contextual source types can conceal the actual result. |
| Return text reused for other intents | Switch assignment and discard inherit return-oriented conversion decisions, then alter strings. The real destination is already lost when the adapter acts. |
| Different lifetimes | Stable declaration storage, per-evaluation results, and program-point presence facts are represented by nearby maps and fields with different validity rules. Naming their values alike does not unify their authority. |

SwiftExpr's roughly 7,000 lines increase inspection cost, but file size is not the architectural cause. Moving the same functions into smaller files would preserve these hidden dependencies. File ownership also governs who may edit; it does not establish semantic ownership. The relevant separation is between facts established by an operation and requirements supplied by its consumer.

## PART 3 — Distinct contribution: reframe the unit of analysis

### Decision: accept destination-sensitive translation handoffs

The useful unit is **one accepted source occurrence lowered in a specified environment for a specified result use**. Mechanism names remain useful for scheduling; “which mechanism has a defined producer?” is too coarse for correctness or closure.

An array result crosses A, B, C, D, and sometimes E before F can explain it. Selecting one named owner for “arrays” or finding a common call target cannot demonstrate those responsibilities agree. Conversely, several expression families can legitimately establish their own facts. “One authoritative producer” means one authoritative account of a particular fact at a particular occurrence, not one function permitted to create every value of that fact kind.

The governing contract has these parts:

| Handoff obligation | Required guarantee |
| --- | --- |
| Declaration → read/write | Stable declared storage and admitted absence agree with emitted declarations; reads and writes use that selection. |
| Expression operation → prepared value | The selected operation establishes actual storage and presence possibilities together with its output and occurrence. A later predictor does not recreate them. |
| Flow analysis → extraction | A presence proof identifies its exact subject and valid environment, including dependencies and invalidation. |
| Prepared value → conversion | A pure decision consumes actual representation and the actual destination, with explicit intermediate requirements for composition. |
| Composition → enclosing consumer | Reachable alternatives reconcile to the selected destination; the join returns their established facts and preserves lazy evaluation and exits. |
| Conversion → observation | The realization preserves shared storage, lifetime, element identity and evaluation behavior; retained evidence identifies the governing decisions. |

This reframing produces concrete judgments that a caller census cannot:

**Switch assignment:** the key question is whose destination reaches the arm. The inspected route supplies the enclosing function's return type, then prints an assignment to a different target. The earliest ownership error precedes the conversion planner. A discriminating acceptance witness would retain a local read-only destination while varying the enclosing function's unrelated return type. Its translation must remain governed by the local destination. Source/interception admission must be established before claiming a reproduced failure.

**Try results:** the key question is whether the normal body/catch tail retains its produced facts up to the binding or function-return destination. Explicit returns in statement prefixes do not answer it. The body and handler need separately justified normal results and exit behavior. `blockValueLines` returning raw tail text establishes neither representation reconciliation nor the authority of the final destination.

**Null initialization and later assignment:** the stable binding owns a nullable container representation; the initial expression owns an absent value. A later read is a new occurrence using current flow facts. Treating the initializer's NullArrayValue as permanent binding storage would conflate two lifetimes. Counting an initializer's boundary call says nothing about the later read.

**Nil-merge and conditionals:** a required final result does not make an optional left operand required before the fallback executes. The composition owns an optional intermediate requirement, then joins with the fallback. Ordinary alternatives require their branch environments. Copying one arm's storage is justified only after compatible reachable results have been established. Supplying one final destination flag to every intermediate is insufficient. [Composition rule](/home/losses/Development/tq-workspace/boring-wt-architecture/docs/compiler-policy-interfaces.md:169).

**Replaced calls:** the authoritative result is the selected helper operation plus any selected wrapper. `platformModuleCall` actually inserts a TiqianArray constructor in one route, but returns only text. Its declared Haxe return type cannot supply the missing account for all replacement routes. Here the E-to-A handoff matters more than whether a subsequent argument conversion reaches `prepare`.

**Text adapters:** extracting `.text` at a terminal printer is permitted. Extracting it before another component needs the value's facts creates a new opportunity for reconstruction. Thus `arrayBoundaryText` is neither automatically sound nor automatically a second authority. Its position in the composition determines whether the information loss is legitimate. [Terminal adapter allowance](/home/losses/Development/tq-workspace/boring-wt-architecture/docs/investigations/architecture-round-1/j-prepared-value-design.md:75).

The runtime illustrates why ownership inspection and semantic inspection must meet. The inspected ReadOnlyArray constructor retains the exact TiqianArray object in a private backing field, and its reads delegate to that object. That is static support for the required shared-view design. Its `toMutableArray` method creates a fresh wrapper, which is a different operation requiring its own applicable source semantics. Neither fact proves that every lowering route invokes the correct operation once, or that all generated modules compile. [Runtime representation](/home/losses/Development/tq-workspace/boring-wt-architecture/packages/compiler/reflaxe/swift/swiftcompiler/SwiftRuntime.hx:485).

### What makes this finite enough to finish?

Use a fixed set of producer families and compositional guarantees. Establish the contract for each primitive family, then for each composition that combines or retargets results. This avoids trying to enumerate every possible source program while still checking that the accepted grammar's required routes are covered.

Coverage must therefore have three independent dimensions: source admission, structural routing, and preservation of facts/semantics. A row can be routed but unverified for fact preservation; a static path can exist without a demonstrated accepted source witness. One “covered” flag erases those distinctions and invites the observed overcorrection.

Under this decision, success is observable: a formerly required reconstruction disappears, the actual destination reaches the producer, and a typed downstream consumer plus semantic observations exercise the composed result. The producer-family denominator stays fixed when a defect is found. Pending J2/J3 work can coexist with accepted J1 phase evidence, as the approved design allows; it cannot establish complete J acceptance.

This is a local architectural requirement around the existing planner. It does not depend on completing a general IR, unified source maps, or every responsibility across five targets. For other approved migrations, use the same unit with their own input contracts and required scope.

## PART 4 — What I would inspect next, in priority order

These priorities deepen the present static inspection and establish the missing execution evidence.

1. [SwiftExpr.hx](/home/losses/Development/tq-workspace/boring-wt-architecture/packages/compiler/reflaxe/swift/swiftcompiler/SwiftExpr.hx:2578) — Trace complete definitions and environments around preparation, block/switch/try results, and narrowing to settle where representation or destination first disappears.
2. [SwiftDecl.hx](/home/losses/Development/tq-workspace/boring-wt-architecture/packages/compiler/reflaxe/swift/swiftcompiler/SwiftDecl.hx:569) — Check static-initializer lowering and its admitted domain to settle whether constructed storage/presence facts describe the emitted operation.
3. [SwiftType.hx](/home/losses/Development/tq-workspace/boring-wt-architecture/packages/compiler/reflaxe/swift/swiftcompiler/SwiftType.hx) — Compare ordinary and substituted mappings with emitted declarations and public signatures to settle stable representation selection.
4. [SwiftParameterPlan.hx](/home/losses/Development/tq-workspace/boring-wt-architecture/packages/compiler/reflaxe/swift/swiftcompiler/SwiftParameterPlan.hx:49) — Follow signature versus normalized body representation to settle which parameter facts apply at each read.
5. [DefaultArgExpander.hx](/home/losses/Development/tq-workspace/boring-wt-architecture/packages/compiler/DefaultArgExpander.hx) — Follow registration, rewrite timing and substitution to settle the source operation and environment behind default-result claims.
6. [SwiftArrayBoundary.hx](/home/losses/Development/tq-workspace/boring-wt-architecture/packages/compiler/reflaxe/swift/swiftcompiler/SwiftArrayBoundary.hx:165) — Compare every legal input state with independently specified decisions to settle totality, vetoes, optional intermediates and no-plan outcomes.
7. [SwiftRuntime.hx](/home/losses/Development/tq-workspace/boring-wt-architecture/packages/compiler/reflaxe/swift/swiftcompiler/SwiftRuntime.hx:378) — Follow runtime emission and generated declarations to settle shared backing, escaping lifetime, copy operations and helper compatibility.
8. [ReadOnlyBoundaryOps.hx](/home/losses/Development/tq-workspace/boring-wt-architecture/tests/swift-readonly-boundary/boring/ReadOnlyBoundaryOps.hx) — Inspect each source witness and typed consumer to settle which producer/position interactions are actually represented.
9. [SwiftBoundaryPlanChecks.hx](/home/losses/Development/tq-workspace/boring-wt-architecture/tests/swift-readonly-boundary/boring/SwiftBoundaryPlanChecks.hx) — Check expectations against independent requirements to settle whether planner checks discriminate contradictory or missing states.
10. [readonly-boundary.test.ts](/home/losses/Development/tq-workspace/boring-wt-architecture/tests/swift-readonly-boundary/readonly-boundary.test.ts) — Match source admission, generated artifacts and retained native results to settle what the focused harness proves at the exact candidate.
11. [package-artifacts.test.ts](/home/losses/Development/tq-workspace/boring-wt-architecture/tests/ts/package-artifacts.test.ts:58) — Trace source substitution, interruption and concurrent invocation to settle which verification inputs were actually consumed.
12. [MathNaNTestSupport.hx](/home/losses/Development/tq-workspace/boring-wt-architecture/samples/boring/MathNaNTestSupport.hx) — Compare authoritative bytes with retained execution-root inventories to settle whether assertion methods were intact during affected runs.
13. [package.json](/home/losses/Development/tq-workspace/boring-wt-architecture/package.json:47) — Expand the candidate's required command closure to settle what remains beyond the driver agreement result.
14. [boring.json](/home/losses/Development/tq-workspace/boring-wt-architecture/boring.json) — Derive configurations and test membership to settle the independent Boring coverage denominator.
15. [p09-fixed-matrix-preparation-runbook.md](/home/losses/Development/tq-workspace/boring-wt-architecture/docs/investigations/architecture-round-2/p09-fixed-matrix-preparation-runbook.md) — Check its pinned candidate and transformed inputs against the proposed final candidate to settle whether the recipe is still applicable.
16. The pinned Tiqian checkout's `boring.json` and its twelve recursively included HXML roots — Settle actual compiler routing, generation/test obligations and comparison domains; the current checkout path and availability remain unverified.
17. [p09-chainA-full/REPORT.md](/home/losses/Development/tq-workspace/dc-warn/out/p09-chainA-full/REPORT.md) and its referenced raw records — Audit candidate identity, statuses, child diagnostics and assertion fingerprints to settle how much regression evidence can be reused.

I would need accepted source/interception witnesses, generated Swift, and native results before committing to runtime conclusions about the switch/try discriminators. P09 additionally requires complete evidence for the fixed Boring/Tiqian pair.
