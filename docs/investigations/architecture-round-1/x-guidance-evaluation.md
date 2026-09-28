# X: Evaluate the revised guidance on storage lifetime

## Status and prerequisites

The coordinator assigned this exercise to Goose at `db1bb984` after accepting
the ordinary shared-view runtime observations. The expanded architecture work
allows this investigation to proceed while J's full prepared-value migration
remains open. The exercise establishes no prior acceptance of that migration.
Record the candidate's revision and relevant file hashes before work. The
coordinator owns this brief; a different executor from J owns the follow-up.

Read the analysis method, implementation standard, feature 18, the revised J
brief, and its review record. The purpose is to assess whether those documents
help an agent derive a related case without reproducing J's implementation
mistakes. Record coordinator interventions separately from independent reasoning.

## Question and contract

Investigate an ordinary read-only view when the mutable source binding is
later assigned a different array and when the original local scope ends.
Determine which storage the view must observe using feature 18 and an accepted
Haxe oracle. Distinguish a variable binding, a container, and its elements.
Identify the representation decision that must preserve the original storage's
lifetime. No new semantic ruling is delegated to this task.

Before editing, provide the source-contract argument, the producer and consumers
of the relevant storage fact, the applicable target comparison, and a test
that could disprove the proposed explanation. Identify what copying slots,
sharing the container, or following a reassigned binding would each produce.
State any source construct whose acceptance remains unverified.

## Scope and evidence

The assigned implementation is a new focused fixture under
`tests/haxe/view-lifetime-contract/` in its independent task checkout.
Use the existing child-evidence probe and shared stage membership checker.
Outputs belong under `out/view-lifetime-contract/` in separate attempt
directories. The executor submits the source-contract argument and
counterexamples for coordinator review before writing the fixture. Do not edit
compiler code unless the coordinator reviews a demonstrated failure and assigns
the responsible files. No shared sample exclusions or expected-value changes
may conceal a missing target behavior.

Require Haxe source acceptance, an oracle observation, freshly generated Swift
compilation and execution, and recorded commands, input identities and raw
streams. Cover reassignment and escaped lifetime separately before combining
them. The test must distinguish the relevant storage relationships; counting
wrapper constructors or matching generated text is insufficient.

Deliver the reasoning record, changed files, test results, remaining target
gaps, and an account of which guidance helped or failed. The coordinator reviews
both the reasoning and implementation. Any resulting change becomes part of
the final fixed candidate before its full Boring and Tiqian verification.

## Evaluation

Assess whether the executor found the governing contract, kept source binding
and storage identity distinct, traced fact ownership, selected discriminating
observations, and preserved evidence. Classify omissions as missing guidance,
ambiguous authority, execution deviations, or verification failures with
specific evidence. A passing fixture alone does not establish successful use
of the method.

### Interim observations from the assigned exercise

The executor's first reasoning record distinguished binding, container and
element identity and derived the reassignment and escaped-view expectations.
Its initial sharing case mutated the original array before the producer
returned. That case could pass even if the return boundary copied the array.
The coordinator required a retained mutable alias to the original container,
mutation after the producer returned, and a view observation after that
mutation. The authored fixture now includes that sequence. Its runtime result
is still pending.

This omission concerns test discrimination: the test must place the observable
mutation after the boundary whose storage behavior it claims to establish.
The oracle verifies expectations derived from the source contract; agreement
between two observed outputs alone cannot determine those expectations.

The first proposed runner also violated existing execution requirements. It
resolved the repository root to `tests`, parsed structured probe JSON with
spacing-dependent text patterns, omitted stage identities from unreached rows,
and recorded some failed checks without making them affect its verdict. The
coordinator cancelled that write before execution and supplied a correction
brief using the existing probe and stage-check contracts.

These runner failures are execution deviations from documented requirements.
Additional general instructions would not establish compliance. Acceptance requires
the corrected runner's actual paths, parsed child outcomes, required stage
membership, authored expected values and failure propagation. Record those
results before judging the guidance effective or completing P11.
