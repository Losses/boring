# Compiler policy architecture and parallel migration

## Objective and ownership

This document defines the target responsibilities and the work boundaries for
systematic architecture work across TypeScript, Kotlin, Rust, Swift, and Dart.

The coordinator owns architecture, semantic decisions, task briefs, reviews,
and acceptance. Claude Code and Goose own implementation and test changes.
Each executor receives the exact source revision, relevant repository rules,
interface specification, file ownership, test obligations, and durable handoff path.
Record the CLI, actual model, and provider independently.
Process records (owner requests, status, checkpoint follow-ups) live on the
workspace task board, not in this document.

## Layers and dependency rules

A policy is a decision over explicit facts with a typed result and documented
preconditions. Its alternatives may use an exhaustive match. The architecture
does not require a class per rule or a universal dynamic strategy registry.
Separate policy selection from the operations that realize its result.

| Layer | Owned decisions and outputs | Permitted dependencies |
| --- | --- | --- |
| Source specification and normalization | Accepted source forms, specified semantics, rewrite input/output guarantees, source occurrence | Source specifications and typed source; no target text |
| Semantic facts | Declaration identity, value identity, null and initialization facts, effect dependencies, flow joins and invalidation | Normalized source, symbol and control-flow information; no target spelling |
| Target representation policy | Storage, parameter/body/return representation, object sharing, numeric width, error and container representation | Semantic facts and declared target capabilities |
| Operation and boundary policy | Conversions, argument/default operations, writable-place operations, evaluation sequencing, branch result agreement | Actual produced representation, destination requirement, relevant flow/effect facts |
| Target construction | Structured values, places, statements, exits, temporaries, declarations, and helper calls | Selected plans and prepared operands; target syntax rules |
| Printing and diagnostic export | Text, precedence, escaping, source ranges and decision explanations | Completed target structure and retained provenance |
| Platform integration | Extern signatures, helper declarations, imports, module closure, output artifacts | Declared platform specifications and selected target dependencies |

Each fact has one authoritative producer, a scope, consumers, and invalidation
rules. A source type can constrain representation selection without certifying
what an earlier operation produced. A presence proof and the target operation
that reads a narrowed value remain separate. A writable place identifies a
location; converting a value does not preserve a writable location automatically.

Identity, lifetime, and write permission are independent facts. A read-only
view can retain shared storage while forbidding stores through that view.
Wrapping a reference does not by itself establish an independent object.
A place reached through a value-type intermediate can require explicit
writeback. Introducing a temporary is correct only when its storage relationship,
evaluation order, and any writeback preserve the source operation.

Shared fact records retain the scope of the governing rule. A representation
rule for Rust records retains its target scope when its data moves into a
shared module. An unresolved
requirement remains unresolved until its authority is established.

Pure policy queries do not render expressions, allocate temporary identifiers,
or change flow state. Target construction consumes a decision and reports its
actual output representation. Printing cannot recover semantic facts by parsing
its own output. Diagnostic export consumes provenance and never selects a
semantic operation.

## Interface requirements for each policy

The [policy interface decisions](compiler-policy-interfaces.md) record accepted
record distinctions and finite presence rules. Package proposals must satisfy
them before their implementation is assigned.

Before implementation, the task brief supplies:

1. The governing source behavior and exact specification references, including
   accepted forms and existing owner rulings.
2. Typed input distinctions and their authoritative producers. Identify
   declaration facts, expression results, program-point facts, and target
   capabilities separately.
3. A finite decision table or explicit algorithm, valid output states, failure
   behavior, and rule precedence where alternatives overlap.
4. Producer and consumer inventories in all five targets, with concrete entry
   points and explicit unknowns. Inspect alternate statement and return routes.
5. Adapter boundaries for existing code and a list of decisions to remove.
   Intermediate adapters must preserve facts without introducing a second
   semantic authority.
6. A discriminating test matrix, expected unchanged outputs, intended semantic
   changes, warning expectations, and the required integration checks.

Share source facts and decision algorithms where semantics agree. Target
representations can differ through declared capabilities and target-owned
operations. Sharing a policy name does not require all targets to use the same
runtime storage. Conversely, target syntax differences do not justify five
independent definitions of source identity or evaluation order.

## Parallel work packages

The round 2 record (workspace task board: round-2 fact extraction, task t-muso22y0-5hn2) identifies the
active executor assignments, fixed input, and historical review evidence.

The initial packages below are design and migration responsibilities. An
implementation assignment requires an accepted brief and exact file ownership.

| Package | Policy responsibility | Dependencies and expected delivery |
| --- | --- | --- |
| A: Value and declaration representation | Stable declaration/body storage, produced values, destination requirements, conversions and defaults | Existing semantic rulings; shared input/result interfaces, target adapters, removal inventory; includes unfinished Swift array work |
| B: Flow and evaluation | Binding identity, invalidation, branch/loop/exception joins, operand effects, evaluation order | Normalized source identities; scoped fact queries and sequencing plans consumed by A, C, and D |
| C: Identity and writable places | Alias visibility, object sharing, container lifetime, original assignment location through projections | Source identity rules and B's effect facts; explicit place and sharing rules replacing name lists and rendered-path guesses |
| D: Control-flow results | Branch values, return/assignment/discard intent, reachable exits, structured joins | A's representation facts and B's flow facts; target construction that preserves nested scopes without rewriting return text |
| E: Intrinsics and platform integration | Numeric/string domains, selected helper signatures, replacement-call results, imports and module closure | Source operation specifications and A's representation interface; declared operation results and target legality |
| F: Evidence and diagnostics | Occurrence lineage, policy decision records, source mapping, child output retention, layered conformance | Shared identity/result interfaces; observation consumers that expose decisions without participating in selection |

A, B, C, E, and F can begin interface design and inventory concurrently. D's
implementation follows agreed representation and flow interfaces. Package
letters identify responsibility. File assignments separately control write access.
Integration into a particular backend has one assigned writer at a time.

Use separate task worktrees or exact nonoverlapping file ownership. Shared
policy modules also have one writer. Cross-package interface changes return to
the coordinator before dependent implementations change. Independent modules,
fixtures, and target integrations can proceed concurrently after their input
interfaces agree. Heavy compiler and consumer test runs share a measured
resource budget and fixed candidate schedule.

## Cross-review and acceptance

Claude Code reviews Goose deliveries and Goose reviews Claude Code deliveries
where both routes are available. The coordinator resolves disagreements against
source specifications and actual code. Record execution deviations, missing guidance,
ambiguous authority, and insufficient verification separately. Revise the owning
document when the requirement or instruction is deficient.

Each policy migration must show where its facts originate, how every migrated
consumer uses them, which duplicate decisions were removed, and which paths
remain pending. Renamed user declarations and equivalent accepted source forms
must select the same general rule when their semantics are unchanged. Tests
that require new application-name registrations do not prove such a rule.

Validate in layers: pure decisions and invariants; accepted-source and producer
interactions; generated target compilation and behavior; complete Boring checks;
fixed-revision Tiqian regression. A checkpoint may retain explicit failures.
Release acceptance requires the applicable layers and the original semantic
obligations. Expensive consumer tests run after a coherent integration candidate
has passed the earlier layers.

## History and remote review

At task assignment and integration review, record the remote master SHA and
review its changes since the previous observation. Keep the implementation
baseline fixed until an explicit integration decision. Follow parent relations
and timestamps so merged older work is not described as newly authored work.

For older and current fixes, record the symptom, earliest incorrect fact,
current repair, responsible policy, and how that policy would express the rule.
Inspect representative diffs and their consumers. A commit title or count
cannot establish correctness or justify a rewrite. Use recurring mechanisms
to extend the migration inventory; avoid copying each upstream special case
into the architecture branch.

## Programme completion

The earlier first-cycle criteria remain required evidence. The expanded work
also requires accepted policy decisions, a five-target migration inventory,
verified removal of duplicate decisions in each required migration,
cross-platform executor review, and integration regression evidence. Scheduling
an unresolved item records outstanding work. Open items
cannot be declared complete through an empty adapter or a passing original
example. The coordinator records the exact supported scope and unresolved work
at each integration checkpoint.
