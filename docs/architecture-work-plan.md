# Compiler architecture work plan

## Goal and completion criteria

Improve the compiler's architecture through delegated work and use the results
to improve the instructions available to subsequent agents. Apply the
[compiler problem analysis method](compiler-problem-analysis.md) and the
[translator implementation standard](specs/style/02-translator-implementation-standard.md).
Existing semantic rulings and required verification remain binding.

The initial programme is complete when all of these conditions hold:

1. A revision-specific survey covers TypeScript, Kotlin, Rust, Swift, and Dart,
   maps recurring failures to compiler responsibilities, and records unknowns.
2. The repository documents task assignment, architectural review, verification,
   and reflection, with clear ownership for each kind of decision.
3. Execution agents complete one selected mechanism change through its analysis,
   representation, lowering, and printing consumers as applicable.
4. The accepted candidate has fresh Boring checks and the required Tiqian
   platform regression evidence from a recorded pair of revisions.
5. A later agent task exercises the revised guidance on another case. Review
   records whether the agent used the intended reasoning and where guidance
   still failed. Passing tests alone do not establish this condition.

The initial scope ends with that evaluated cycle. Further mechanisms remain
separate scheduled work. Completion does not establish universal compiler
correctness or the absence of regressions outside the tested domain.

## Roles and authority

The coordinator investigates, designs contracts, writes task instructions and
repository documentation, assigns work, reviews changes, runs verification,
and records acceptance decisions. Implementation and test code are written by
execution agents. A rejected implementation returns to its execution owner with
an explanation and revised instructions where needed.

Each task has a semantic owner who compares the mechanism across the five
targets. Each changed backend has one integration owner. Shared modules also
have one assigned writer at a time. Investigators may read the same files;
editing shared emitters requires an explicit assignment from the coordinator.

Available execution routes are native Luna, Goose with the configured local
Qwen service, and Claude Code. Record the actual model and provider for each
run. The availability check on 2026-09-27 found Claude Code using a custom
service with `glm-5.3-flash[1m]`; its CLI name does not identify its model.
These checks establish basic availability. Task quality requires separate
evaluation. Give every external session an explicit brief and repository
instructions; it does not inherit the coordinator's conversation.

## Document responsibilities

| Document | Responsibility |
| --- | --- |
| `AGENT.md` | Entry instructions and required reading |
| `docs/compiler-problem-analysis.md` | Diagnosis method, architectural criteria, and reasoning record |
| `docs/specs/style/02-translator-implementation-standard.md` | Binding ownership, consolidation, variation, and acceptance rules |
| Relevant feature or standard library specification | Observable semantics and accepted input domain |
| This plan | Task order, assignments, dependencies, and programme status |
| Task records under `docs/investigations/` when created | Revision-specific evidence, briefs, decisions, and round reviews |

Update the document that owns a rule. A repeated checklist in several documents
creates ambiguity when one copy changes. Keep machine-specific paths, logs,
and large generated artifacts outside normative documentation; link evidence
from the task record. Mark planned tooling as planned until it exists and has
been exercised.

## Todo and dependencies

Current status: the first investigation round is running on independent branch
`arch/agent-guided-governance`, based on
`e3b8bab39ac2da0e17e9d04e031f03bd39290274`. See the
[round 1 record](investigations/architecture-round-1.md) for version evidence,
ownership, and assignments. The owner has selected shared alias visibility for
ordinary read-only arrays. Brief J now includes the required Swift type and
runtime scope and is ready for executor assignment. Earlier investigations are
leads that require revision checks.

- [x] P00: Establish the coordinator role and create the programme goal.
- [x] P01: Verify basic availability of Luna, Goose, and Claude Code routes;
  distinguish native availability from the external tool probes.
- [x] P02: Record this plan, task brief requirements, and acceptance criteria.
- [x] P03: Record current remote heads, local changes, active work ownership,
  toolchains, and the Boring version actually consumed by Tiqian. Identify a
  reproducible baseline before assigning writes.
- [x] P04: Assign three bounded investigation tasks from that baseline:
  A, architecture and recent fixes; B, verification and cost; C, documentation
  usability and upstream compiler references.
- [x] P05: Review A, B, and C; reconcile their evidence and publish the initial
  responsibility map, missing contracts, and ordered mechanism work list.
- [x] P06: Update existing internal guidance from the investigation findings.
  Record unresolved semantic rulings separately from implementation choices.
- [x] P07: Select the first mechanism and write a complete implementation brief,
  test matrix, file ownership list, and migration acceptance criteria.
  [Swift array boundary brief](investigations/architecture-round-1/j-boundary-implementation.md)
  includes the owner's shared-storage ruling, runtime representation, and
  fair comparisons between generation runs with identical inputs.
- [ ] P08: Delegate reproduction and contract tests, then implementation.
  Independently review both before accepting a candidate.
- [ ] P09: Run the candidate's required Boring checks and Tiqian checks on fixed
  revisions, preserving logs, generated-output identity, and warning results.
- [ ] P10: Classify review failures, revise the appropriate documents, and
  publish the first round's acceptance and reflection record.
- [ ] P11: Give an agent a related extension task using the revised documents.
  Assess its reasoning, implementation, and verification against the same
  standards. Apply required checks to any further code changes.
- [ ] P12: Publish the programme review, accepted revisions, evidence gaps,
  and next scheduled mechanisms. Close the goal only when its criteria hold.

P04's three investigations can run concurrently. P05 depends on all three.
P08 depends on an accepted P07 brief and resolved semantic dependencies.
Heavy platform tests use a measured resource limit even when investigation
capacity is available. Start with one heavy verification candidate at a time.

## First investigation assignments

### A: Architecture and recurring failures

Inspect recent fixes and their current implementations. Cover all five targets
and the shared layer. Classify each finding by compiler responsibility and
semantic dimension from the analysis method. Group by the missing fact or
contract; distinguish an observed failure from a static architectural concern.

Deliver a table of mechanisms, source locations, evidence, affected targets,
fact producers and consumers, and proposed ownership. For each target, use an
explicit status: affected, different mechanism, outside the accepted domain,
or not yet inspected. A blank cell cannot establish correctness.

Initial investigation subjects are value representation and conversion,
nullability and control flow, numeric behavior, string units, identity and
sharing, evaluation effects, and structured output. Check current code before
treating earlier examples as current defects.

### B: Verification, evidence, and execution cost

Inventory actual test entry points, their assertions, produced artifacts,
revision identity, required environment, and dependencies. Distinguish tests
of source semantics, compiler decisions, target compilation, runtime behavior,
warnings, cross-target consistency, and Tiqian integration.

Deliver a change-to-test matrix and a candidate verification procedure. State
which existing gates are mandatory and which focused checks provide earlier
feedback. Identify successful-output comparisons, stale artifact risks,
untested interactions, and checks that only inspect generated text.

Record observed timings separately from estimates. Inspect existing logs first;
schedule any expensive measurement through the coordinator. This assignment
does not start simultaneous full Tiqian runs or modify shared build outputs.

### C: Documentation usability and compiler references

Apply the current analysis method to two concrete cases involving different
targets. Record every missing instruction, ambiguous ownership decision, and
assumption required to proceed. Propose changes to the owning documents.

Compare relevant mechanisms in official Haxe compiler sources and Reflaxe
transpilers. Record upstream revision, source location, phase contract, and
target constraints. Explain which idea applies to Boring and what additional
facts Rust or another target requires. A strategy class or smaller file alone
does not establish semantic separation.

Deliver a documented reasoning exercise and a source-backed comparison of
specific mechanisms. Do not select a replacement architecture solely from
the organization or popularity of another compiler.

## Mechanism selection and parallel work

Select the first mechanism after the investigations. Swift mutable and read-only
array conversion is a candidate from earlier inspection. Confirm it against the
chosen revision and compare the corresponding contract on every target.
Selection criteria are repeated failures, a clear missing contract, a bounded
set of consumers, discriminating tests, and feasible integration verification.

For that candidate, inspect arguments, returns, local initialization, assignment,
literal elements, optional containers, and already-converted expressions.
Require preservation of evaluation count, order, null behavior, and aliasing
where the source contract requires it. Use these dimensions to derive cases;
the candidate remains provisional until its evidence has been reviewed.

Separate analysis tasks can investigate numbers, strings, flow facts, identity,
and output structure concurrently. Implementation order follows actual contract
dependencies. For example, an ownership change may depend on representation
decisions; a conversion may depend on established flow facts. Resolve those
dependencies before assigning edits to the same consumer.

Use isolated workspaces and output directories for execution tasks. Do not
reuse another worker's uncommitted tree or generated artifacts as a baseline.
Record file ownership before work starts. The coordinator integrates accepted
changes in a defined order and verifies the resulting combined candidate.

## Required task brief

Every execution task records:

1. Task identifier, brief revision, objective, and explicit completion criteria.
2. Repository and baseline revisions, workspace, input configuration, and the
   documentation versions the agent must read.
3. Observed evidence, hypotheses, unknowns, and the governing semantic ruling.
4. Scope, allowed files, excluded responsibilities, and dependencies on other
   tasks, facts, or contracts.
5. The contract to establish: input domain, preconditions, output guarantee,
   fact ownership and lifetime, invalidation, and unsupported cases.
6. Expected target comparison and the proposed general rule. Permit the agent
   to challenge the design with evidence before implementing a contradiction.
7. Required tests and commands, expected observations, output directories,
   resource limits, and evidence to retain. Mark unresolved commands explicitly.
8. A delivery record containing changed files, remaining old paths, commands
   actually executed, results, uncertainties, and documentation findings.
9. Conditions requiring review: unresolved behavior, conflicting ownership,
   insufficient facts, or a failed required check. Follow existing rulings and
   session authorization when deciding whether owner input is necessary.

An agent's summary is a claim to inspect. Acceptance requires reviewing the
actual changes and evidence. Additional reproductions or code corrections are
assigned to an execution agent; the coordinator can run existing checks.

Preserve the assigned scope when evidence is difficult to obtain. A missing
external reference is an incomplete requirement; substituting the repository's
own implementations does not complete an external comparison. Report the
attempted access, remaining requirement, and alternative evidence available.
The coordinator reviews partial findings without marking the whole task done.

## Verification and acceptance

Give each candidate a Boring revision, Tiqian revision, relevant local-change
record, toolchain versions, defines, selected suites, generation commands, and
artifact locations. Test the exact candidate that is proposed for acceptance.
Keep the candidate fixed while expensive checks run. New work forms a later
candidate with its own evidence.

For consumer verification, trace the complete HXML include structure and all
explicit compiler, standard-library and runtime paths. A correct haxelib mapping
does not replace this check. Record actual loaded module paths during generation
where the compiler supports it. Preserve the consumer working directory and
input semantics when deriving configuration files for a candidate checkout.

Use focused reproductions and contract tests for early feedback. Apply affected
target compilation and execution checks, then every gate required by the
implementation standard and repository instructions. Follow with the required
Tiqian platform matrix. Document the actual scope of that matrix before launch.
Reuse evidence only when the relevant inputs and artifact identities match.

Expand composite commands before scheduling checks. When the full verification
command already runs a target matrix, schedule that matrix once for the fixed
candidate. Earlier feedback should use focused checks. Repeat a completed check
when its inputs change, a specific result needs investigation, or an applicable
gate requires repetition. Name the reason in the execution record.

Generated-code warnings and suppression markers are acceptance failures under
the current standard. Record any baseline failure separately, including its
revision and reproduction; a baseline finding does not waive the standard.
Cross-target agreement supplements assertions against the specified semantics.

Review architectural criteria alongside test results: facts have owners,
queries preserve state, printing consumes established decisions, optional
optimizations retain a valid general translation, and migrated consumers no
longer infer semantic facts from generated text or consumer-specific names.
File count, line count, and number of strategy classes are insufficient criteria.

## Reflection and guidance evaluation

For each rejected or incomplete delivery, record:

| Field | Required observation |
| --- | --- |
| Expected reasoning | The documented decision and evidence required |
| Actual behavior | The agent's decision, changed code, and verification |
| Cause | Missing guidance, ignored guidance, incorrect architecture assumption, missing verification, or environment failure |
| Correction | Owning document, task brief, design, or execution setup to change |
| Next evaluation | A later task or counterexample that can expose recurrence |

Support the cause classification with evidence; an execution failure alone
does not prove that the instructions were deficient. Preserve the original
brief revision so retrospective edits cannot obscure what the agent received.

Evaluate revised guidance on a related case with different syntax or a different
boundary. Observe whether the next agent finds the responsible contract, avoids
the previous special case, proposes relevant counterexamples, and produces
verifiable evidence. Record coordinator interventions and recurring omissions.
Compare outcomes with their task difficulty and model configuration; a single
successful task cannot establish a general model ranking.

Promote durable reasoning into the analysis method or implementation standard.
Put behavior rulings in semantic specifications and keep incident details in
the investigation record. Each round ends with an explicit documentation
decision: revise a rule, clarify an example, or retain the rule with reasons.
Run the documentation style checker and review the final wording after edits.
