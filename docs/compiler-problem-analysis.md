# Compiler problem analysis

## Purpose and use

Use this method when diagnosing translation failures, adding language support,
or changing compiler structure. It applies to TypeScript, Kotlin, Rust, Swift,
and Dart. Begin with the source behavior, identify the missing or incorrect
compiler fact, and assign its correction to the responsibility that owns it.
Each repair must explain the family of programs it handles and the conditions
under which the rule is valid.

Read this document with the relevant feature specification,
[design principles](specs/design-principles.md), and
[translator implementation standard](specs/style/02-translator-implementation-standard.md).
Feature specifications define accepted behavior. The design principles govern
semantic rulings. The implementation standard governs consolidation, target
variation, and acceptance. This method supplies the analysis required to apply
those rules. Existing owner rulings and validation requirements still apply.

The stages below describe responsibilities and their contracts. The current
compiler combines some of them in the same modules. For each investigation,
record where they occur today and where the proposed change belongs. A small
structured result can establish a missing contract before a larger migration.
Add an abstraction when the existing model cannot express the required facts.

## Analyze both stages and semantic dimensions

A compilation stage states when a decision is made and what later work may
assume. A semantic dimension states which behavior must remain valid through
those stages. Investigate both: a nullable array argument can involve null
flow, container representation, argument evaluation, and borrowing at once.

### Compilation responsibilities

| Responsibility | Input and decision | Required result |
| --- | --- | --- |
| Source contract | Accepted Haxe constructs and boring specifications | Observable behavior, accepted domain, and diagnostics for unsupported input |
| Normalization | Typed Haxe expressions and registered source rewrites | Defined expression forms with preserved evaluation order, scope, and source positions |
| Semantic analysis | Normalized expressions and control flow | Facts about types, initialization, nullability, effects, identity, and use of values |
| Target representation | Semantic facts and target capabilities | Explicit storage, parameter, return, container, error, and ownership representations |
| Target lowering | Representations and source operations | Legal target operations, explicit conversions, temporary bindings, and control flow |
| Printing | Target structure and naming decisions | Text with correct precedence, escaping, declarations, and formatting |
| Platform integration | Declared extern and runtime contracts | Consistent symbols, signatures, imports, runtime dependencies, and output files |

Analysis may need several passes or a fixed point across functions. State its
dependencies and convergence condition. A syntax printer consumes completed
decisions. Source positions support diagnostics; names identify bindings and
declared APIs. Neither source order nor a consumer's type name proves a
control-flow or object-identity property.

### Semantic dimensions

| Dimension | Questions to answer |
| --- | --- |
| Types and numbers | What are the source type and target representation? Which widths, rounding, overflow, and conversions apply? |
| Nullability and initialization | Can the value be null or uninitialized? Which paths establish a fact, and which writes invalidate it? |
| Control flow and errors | Does a branch yield a value, assign, return, throw, or continue? Where does an error propagate? |
| Evaluation and effects | How often and in what order are operands evaluated? Can an operation mutate, throw, allocate, or call unknown code? |
| Identity, aliases, and ownership | Must references observe the same object? Is a copy independent? When can a value move or be borrowed? |
| Calls and boundaries | How are omitted arguments, explicit nulls, defaults, closures, overrides, externs, and runtime calls represented? |

Record the dimensions relevant to the failure and their interactions. A repair
to one dimension must preserve the others. For example, extracting a nullable
argument must preserve how many times its receiver runs and when it can throw.

## Architecture correctness criteria

Evaluate the proposed repair against these criteria. Record an existing
violation that the repair depends on, along with the affected scope and the
remaining work. A passing example establishes evidence for that example;
the rule's preconditions explain its broader applicability.

1. **Semantic decisions use explicit facts.** Source types, target storage
   types, and expression result types have distinct meanings. Preserve the
   distinctions in typed data. Checks for generated fragments such as
   `Some(`, `?.`, or an assertion suffix cannot establish those facts.
   A choice in one semantic dimension proves a fact in another only through
   a stated rule. For finite decision models, record the legal combinations
   and the diagnostics for unsupported states before implementing selection.
2. **Each fact has an owner and a lifetime.** Name its producer, consumers,
   scope, and invalidation conditions. Branch facts require a valid merge;
   loop facts account for repeated execution; closure analysis accounts for
   captured mutation. A source position comparison cannot establish that a
   check executes on every path to a use.
3. **Queries preserve semantic state.** Inspecting an expression or comparing
   two expressions must not change the facts used by later lowering. Printing
   may manage layout state, but it must not establish non-null proofs or
   change ownership decisions. Repeated printing of the same prepared input
   must preserve its semantic result.
4. **Rewrites have explicit contracts.** State the accepted input form,
   output form, required earlier passes, facts invalidated, and permitted
   repetition. If repeated application is allowed, verify idempotence or
   document the iteration and its termination condition. Every entry that
   admits the same construct must satisfy the same preconditions.
5. **Control flow remains structural until printing.** Represent whether a
   branch returns, assigns, or discards a value. Replacing generated `return`
   text does not provide a contract for nested functions or branches.
6. **Optimizations preserve a valid general translation.** Prove the
   conditions for moving, removing, or duplicating evaluation. A failed
   optional match retains the general translation. A required lowering that
   cannot handle an accepted construct reports a compiler defect; unsupported
   source input receives the specified diagnostic.
7. **Target variation has a named responsibility.** Keep shared source
   semantics in shared analysis. Keep borrowing, storage choices, and target
   legality in the target mechanisms that own them. Use the implementation
   standard's declared variation forms when sharing an algorithm.
8. **Application integration uses declared contracts.** Standard library
   symbols and registered extern bindings can select known implementations.
   Consumer class names cannot serve as evidence of sharing, mutability, or
   ownership. Express such requirements through the accepted semantic model,
   validated declarations, or analyses that establish them.
   At a host boundary, distinguish the declared API result from an arbitrary
   caught value. A destination type annotation does not validate that value.
   Establish the required runtime shape before reading foreign metadata;
   convert validated fields into the internal result in one owning boundary.
9. **Evidence follows the decision.** Preserve source identity and record the
   responsible stage or rule for a generated operation. Keep runtime
   observations, compilation results, structural inspection, and performance
   measurements distinct in reports.

These criteria guide the next change in the affected mechanism. They do not
describe completed infrastructure in the current tree. When a mechanism spans
old and new representations, define their conversion and ownership of facts,
and remove superseded decisions as each path moves to the new representation.

## Recognize valid rules and missing abstractions

Pattern matching is a normal compiler mechanism. A rule is general when its
conditions express semantic requirements and its result preserves the source
contract. Recognizing integer division by operand types, a standard library
call by its resolved symbol, or a loop by a proven invariant can satisfy this
test. The number of branches or files does not establish correctness.

Use three separate mechanisms where they are needed:

- **Node dispatch:** an exhaustive match over a defined set of expression or
  statement forms.
- **Pass sequencing:** ordered transformations with input and output
  invariants and declared analysis dependencies.
- **Conditional rules:** alternatives within a stage, selected by explicit
  facts and target capabilities.

A rule collection needs a stable identifier for each rule, match conditions,
required facts, an output guarantee, and behavior when no rule applies. Define
how competing matches are resolved and how composed rewrites terminate. Use
explicit precedence or disjoint conditions for alternatives; use dependencies
for sequential transformations. Moving a conditional into a class preserves
its original assumptions until those contracts are addressed.

Group failures by the fact or operation that is missing. Similar function
names can implement different target mechanisms. Different diagnostics can
come from one missing representation decision. Share a mechanism after
comparing its semantics and target requirements under the implementation
standard's consolidation procedure.

## Investigation and repair procedure

### Establish the authority of each claim

For a behavior claim, cite the exact specification section and identify which
targets and input forms it covers. Record implementation code, implementation
comments, observed results, and inferred requirements separately. A comment
that cites a feature number does not establish that the specification rules
the commented behavior. Read the cited text before relying on it.

Read the enclosing heading, definitions, exclusions, and amendments with each
quoted sentence. Write the rule's domain beside the case under investigation.
For example, an equality rule under a parameterless-enum amendment does not
establish equality for enums with payloads. A restriction on direct sorted
keys applies to fields inside record keys only when a rule establishes that
relationship. Confirm overlapping domains before declaring two rules in
conflict. A runtime disagreement outside a cited rule's domain remains an
observation pending an applicable authority.

When a specification covers some targets, mark the remaining targets as
unruled or identify another applicable ruling. For example, a target's use of
a value array does not by itself establish when the source contract requires
a snapshot, which aliases must remain visible, or whether element objects are
copied. State those questions before changing conversion behavior.

A missing ruling permits further investigation and an explicit proposal.
Existing implementation behavior can define an output-preservation baseline
for consolidation, but it cannot resolve a disagreement about intended source
semantics. Follow the implementation standard's owner-ruling procedure for an
unresolved behavioral divergence.

For an upstream implementation comparison, record the repository, immutable
revision, file and function, input facts, output guarantee, and downstream
consumer. State a limit on applying the design to Boring. An architectural
description can identify a path to inspect; verify the actual implementation
before treating that path as evidence.

When intended behavior is unresolved, an observational probe can still record
the accepted source form and each target's actual result. Keep those results
separate from a conformance test's required expectation. Use a demonstrated
disagreement to support the semantic decision process.

At a conversion boundary, vary source nullability, destination nullability,
and established flow facts independently. Cover the applicable plain-to-plain,
plain-to-optional, optional-to-optional, and guarded optional-to-required
forms. Record source acceptance and target compilation separately from runtime
results. Use the same authored operation for the source oracle and target run;
a native harness may expose its result without implementing the conversion.

### 1. Record the observation and source contract

Record the checkout, commit, local changes relevant to the result, target,
toolchain versions, defines, generation command, and test command. For a
translation failure, collect the four items required by `AGENT.md`: the Haxe
construct, the emitter function and line, generated text, and the target's
failing site. For a wrong result, include expected and actual behavior and
the operation that exposes the difference.

Verify the complete compiler input path when testing a consumer checkout.
A package-manager mapping establishes one source of inputs. Recursively inspect
included HXML files, explicit class paths, macro source directories, standard
library shadows, and runtime source roots for references to another compiler
checkout. Record the driver's revision separately. Preserve the consumer's
working directory when deriving a validation configuration; a project file's
location may determine that directory. Where available, retain compiler module
loading output to confirm the paths actually selected by the generation run.

Before launching a new runner, resolve its working directory, repository root,
shared helper paths, and output parent to absolute paths and check them against
the assigned checkout. Script directories at different depths need different
relative paths. Record the actual child cwd in the attempt. If an expected
output is absent, inspect that cwd and the command's resolved output path
before attributing the absence to process or filesystem behavior. Preserve a
mislocated attempt with its original path and command metadata.

Reduce the input while retaining relevant effects, aliases, null states, and
control flow. Add an isolated reproducer under the repository's test layout;
preserve the source whose failure prompted the investigation. Cite the
specification that defines expected behavior. Record a missing observation
as unknown and a proposed explanation as a hypothesis. For an architecture
review without an executable failure, report the inspected dependency and
the contract it lacks; do not claim a reproduced runtime defect.

Before generation, map each requested semantic case to the authored values that
exercise it. Check where each relevant state occurs. For example, comparing a
record with a `Null<ReadOnlyArray<Int>>` field requires present record objects
whose fields hold the selected null or collection values. Passing null as the
record key exercises a different boundary. Review this mapping before native
execution; correct process capture and a complete case-name list cannot repair
a fixture that tests the wrong subject.

### 2. Find the earliest incorrect decision

Follow the construct through normalization, analysis, representation,
lowering, and printing. At each relevant boundary, record the input, facts
available, decision taken, and output. Locate the first point where a fact
is incorrect, disappears, or cannot be represented.

Name each boundary's concrete representation, such as typed Haxe expressions,
prepared decisions, target nodes, or generated text. Pass names alone do not
establish responsibilities: a backend's normalization pass may clean target
text while a source normalization pass rewrites typed expressions.

The target compiler's diagnostic identifies an observation point. Continue
back through the producers until the violated contract is found. If the
required decision is correct and only spelling or precedence is wrong, the
repair belongs in printing. If a printer must guess a storage type, inspect
the representation decision and the data passed to the printer.

### 3. Compare the problem family across targets

Identify the semantic dimensions involved, then inspect the corresponding
mechanism in all five targets. Record each target as affected, implemented
by a different mechanism, outside the accepted domain, or not yet inspected.
Cite code or tests for each conclusion. Include ordinary methods,
constructors, static initializers, and nested functions where they admit the
construct. A failure in Rust does not establish that another target is correct.

Derive the consumer inventory from typed-expression dispatch and actual call
paths as well as source-language labels. A class constructor, enum payload,
function value, and ordinary method may take different argument paths in one
backend. A list headed "calls and constructors" does not prove those paths
share the same conversion decision. Mark untested source acceptance separately
from a path found through static inspection.

Compare the source guarantee first, then each target's representation needs.
Determine whether the common cause is missing analysis, lost representation
information, inconsistent pass order, an invalid optimization, or a printing
defect. Separate cases when their semantic requirements differ. Follow the
existing owner-ruling procedure when consolidation reveals an unresolved
behavioral divergence.

### 4. Define the correction and its responsibility

Write the rule before implementing it: preconditions, facts consumed,
decision produced, semantic guarantees, and behavior outside its domain.
Name the responsible stage and module, downstream consumers, and analysis
that must be recomputed after a rewrite.

Choose the smallest change that expresses the general rule. Use an existing
mechanism when its contract is sufficient. Introduce a structured plan or
target node when a required distinction is missing. State how the old path is
removed or adapted. A whole-compiler rewrite is unnecessary when one defined
boundary can carry the needed facts.

For several interacting changes, migrate one semantic mechanism through its
producers and consumers, verify it, and then extend the scope. Select examples
from different targets to check that the proposed shared contract supports
their different representations.

### 5. Verify the rule and its limits

Choose tests that could disprove the explanation:

- The original failure and a reduced case that exercises the same mechanism.
- Cases satisfying each meaningful precondition and nearby cases where the
  rule must decline or produce the specified diagnostic.
- Equivalent accepted forms, such as renamed locals or transparent
  parentheses. Introduce a temporary only when its scope and evaluation
  placement preserve behavior.
- Interactions justified by the analysis: nullable containers, omitted and
  explicit-null arguments, branch joins, captured mutation, or shared objects.
- Observable effects that expose repeated or reordered evaluation, including
  mutations and exceptions where relevant.

Test analysis facts or plans when they are the changed contract. Compile and
execute freshly generated output on affected targets. Apply the implementation
standard's cross-target consistency, warning, and consolidation requirements.
Compare behavior against the specified contract; the Haxe runner has the oracle
role defined in the design principles. Compare generated bytes where the
consolidation procedure requires unchanged output. Measure runtime or compiler
cost before making a performance claim.

Trace how each new fixture enters the test runner and any other build that
discovers its directory automatically. A focused target harness needs explicit
registration and a stated scope. Applicability follows the semantic contract:
an unimplemented shared behavior remains an unmet requirement on that target.
An excluded test or an unconditional successful assertion cannot establish
conformance. Keep focused backend evidence distinct from shared-suite results.

An observation tool must establish that it visited the intended inputs. Define
the expected case identities independently of the traversal, then compare that
set with the retained observations. An empty result or a successful process
exit cannot establish coverage. Distinguish source typing, synthetic macro
inputs, Boring generation, target compilation, and runtime execution in each
record. A result at one stage establishes only that stage's observation.

Record commands, revisions, results, and gaps. A source-text search or an
existing path in an exception record cannot substitute for executing the
behavior that record claims to verify. A check that only repeats the
implementation's predicate gives little independent evidence.

When a rule claims to cover arbitrary user declarations, include an accepted
declaration whose name has no implementation registration. Adding a fixture's
name to a compiler policy table verifies that table entry. It does not verify
that the stated semantic preconditions select the rule for other declarations.
Standard library and extern registrations retain their specified contracts.

### 6. Review and retain the reasoning

Review the final change against the architecture criteria and inspect all
consumers of the changed fact. Confirm that obsolete guesses, duplicate
analyses, and temporary compatibility paths have been removed within the
migrated scope. Record remaining violations with their affected paths.

Update a semantic specification in the same change when its ruling changes.
For an implementation correction, cite the existing ruling and describe the
corrected contract. Keep the following compact record in the change description
or a linked investigation document. Scale detail to the mechanism; an ordinary
printing correction can answer it in a few sentences.

```text
Observation: revision, configuration, reproducer, expected and actual result
Contract: exact specification section, covered targets/forms, semantic dimensions
Authority gaps: implementation assumptions, missing rulings, unresolved behavior
First incorrect decision: stage, function, input facts, and output
Target comparison: evidence and status for each of the five targets
Correction: general rule, owner, preconditions, and output guarantee
Dependencies: consumers, pass order, scope, and invalidation
Verification: cases that distinguish the rule, commands, and results
Remaining work: unverified claims and retained legacy paths
```

## Examples of applying the method

| Observation | Question that identifies the mechanism | Architectural response to evaluate |
| --- | --- | --- |
| Rust adds an extraction to a value already stored without an optional wrapper | Where was the target storage type decided, and did the read receive that decision? | Preserve the storage and result representations in a plan consumed by declarations, assignments, and reads. |
| Kotlin suppresses an assertion after an earlier null comparison | Which paths establish non-nullness, and can a write invalidate it before this use? | Compute scoped flow facts with branch merges and mutation invalidation. |
| Swift converts a mutable array twice at a call | Which representation does the argument currently have, and which does the parameter require? | Record the conversion in target structure and resolve the call boundary from both representations. |
| Dart changes a later assertion after an expression was inspected twice | Does a query or a preliminary render modify analysis state? | Separate fact production from queries and pass the prepared result to printing. |
| TypeScript changes how often a loop bound is evaluated | What evaluation count does the normalized loop require, and is moving the bound valid? | Carry evaluation requirements and effect facts into loop lowering. |
| Several targets remove return text to obtain a statement switch | How should each branch deliver its result, including nested control flow? | Represent the result use structurally before printing the target switch. |
| A new consumer interface needs another entry in a sharing table | Which identity and aliasing contract requires shared storage? | Derive the representation from semantic facts or an explicit validated declaration. |

These examples identify questions and candidate corrections. Reproduce the
relevant behavior and inspect current code before selecting an implementation.
Successful analysis connects the observed failure to a contract, a responsible
stage, a general rule, and evidence that tests the rule's limits.
