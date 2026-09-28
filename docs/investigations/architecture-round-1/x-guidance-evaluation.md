# X: Evaluate the revised guidance on storage lifetime

## Status and prerequisites

This is a planned follow-up to J. Begin implementation only after the
coordinator accepts J's focused delivery and assigns fixture ownership.
Record that candidate's revision and relevant file hashes before work. The
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

The initial permitted implementation is a focused fixture extension under
`tests/swift-readonly-boundary/`, with exact file ownership assigned after J.
Use J's existing registration and evidence capture where applicable. Outputs
remain under its ignored output tree in a separate run directory. Do not edit
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
