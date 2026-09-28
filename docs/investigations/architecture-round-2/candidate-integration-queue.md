# Comparison, local presence, and TypeScript diagnostic integration queue

This queue applies to the three isolated candidate checkouts inspected on
2026-09-28. Each writer owns only its existing checkout. The coordinator owns
the Boring integration checkout and copies accepted files selectively after
independent review. The original Boring checkout remains outside this work.

On 2026-09-28, the coordinator started three native Codex writer tasks in
separate checkouts. A follow-up sent while they were active caused all three
turns to fail with `codex_tool_results_incomplete` before any edits. Resuming
those threads failed with the same tool-delivery error. The coordinator then
started fresh tasks: comparison thread
`01a0ea33-cdc8-74c0-bae8-d75c5cb7a9af`, Kotlin local presence thread
`01a0ea33-f338-75d1-809d-2f6a4b17ab14`, and TypeScript diagnostic thread
`01a0ea34-1804-7472-8b8d-f35565a451dd`. Check live status and delivered
work before acceptance. The writers run focused checks; the coordinator owns
serial target compilation.

On coordinator revision `3fb8c565`, the corrected Kotlin local presence
consumer joined the TypeScript diagnostic batch and the finite comparison
analysis with its Swift consumer. Their focused evidence is recorded in the
[repair review](candidate-repair-review.md). The remaining comparison
consumers have separate active native tasks: TypeScript
`01a0ea54-2e13-7050-a331-09b0538cfe1a`, Kotlin
`01a0ea54-67b1-7f50-b146-33918a4ec839`, and Rust
`01a0ea54-79f7-7a13-a349-6ebe6c8aa996`. Each task owns a separate
checkout and must supply target compilation and runtime evidence before
integration. Dart remains unassigned until an execution slot is free.

The three active checkouts each edit the `ComparatorPlan` row in
`SemanticPassRegistry.hx`; integration must combine that row from actual
remaining callers. The registry currently searches entire Haxe file contents
for a module name. Swift's only remaining `ComparatorPlan` text is a comment
in `SwiftComparisonPlan.hx`, yet the registry still lists Swift. Thus this
check can pass without a real consumer. Before accepting the four remaining
target migrations, review actual imports and calls, remove targets that no
longer consume the legacy module, and add a discriminator that fails when a
listed target contains the name only in comments.

An earlier attempt to launch the TypeScript writer through Claude Code was
rejected by the outer approval review because the configured BigModel service
would receive private source without authorization recognized in this session.
That command was not retried. The native tasks above do not use that route.

| Writer assignment | Immediate repair | Required focused evidence | Independent reviewer |
| --- | --- | --- | --- |
| Comparison analysis and Swift consumer | Replace the raw type-string expectation in the generic schema probe with binder owner, slot, and selected-operation assertions. Preserve finite admission of recursive aliases. | Full admission and A3 procedures with input hashes, negative controls, Swift generation, compilation, and execution. | TypeScript diagnostic reviewer checks the macro and target stage verdicts. |
| Kotlin local presence consumer | Enter the nested literal's own source facts while rendering its body. Restore outer emitter state and keep guarded local reads direct. | Generation, 21 output assertions, mutation control, Kotlin compilation and execution, warning inspection, and occurrence checks through transformations. | Comparison reviewer checks source occurrence identity and Kotlin output. |
| Nested TypeScript diagnostics | Correct relative stage paths, retain successful child command evidence, and reject malformed or escaping sidecar ranges. | Real tsc cases for absolute and relative output roots, successful output streams, mapped and unmapped failures, malformed metadata, and retained child status. | Kotlin local presence reviewer checks path safety and raw child evidence. |

The current [A probe review](a3-probe-review.md),
[B consumer review](b-kotlin-consumer-qa.md), and
[F diagnostic review](f-tsc-diagnostic-qa.md) give the exact observed failures.
The [first repair review](candidate-repair-review.md) records the later
focused results, independent objections, and corrective assignments.
Writers must preserve those failing assertions until the production behavior
passes them. A passing fixture procedure with declared target failures
remains an observation and cannot serve as target conformance evidence.

Each writer renames its remaining generic fixture paths and references before
integration. The coordinator reruns the terminology scan and the affected
fixture after copying. Reviewers read the finished writer bytes and retained
outputs, then record objections in their own review report. A writer does not
approve its own batch. The coordinator resolves disagreements against source
specifications, target compiler results, and raw captured streams.

Static inspection and documentation review can proceed in parallel. Heavy
target compilations run one candidate at a time in the coordinator's
verification interval, with no concurrent writer changes to that candidate.
For each run, record the exact command, selected input hashes before and
after, separate stdout and stderr, numeric status, and dependent stages that
were not reached. Check a live process handle when a session is quiet; do not
infer progress from an open terminal alone.

After the three focused batches are accepted, the coordinator selects one
Boring revision, reruns the affected Boring checks, refreshes the fixed
Tiqian checkout's derived inputs, and completes its twelve generation and
eleven target-test obligations. P08, P09, P10, and P12 remain open until that
evidence and the programme review are complete.
