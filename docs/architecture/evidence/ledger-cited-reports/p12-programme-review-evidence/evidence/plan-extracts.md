# Verbatim extracts from docs/architecture-work-plan.md (boring-wt-architecture), captured 2026-09-30T15:25:17Z
SHA256 of the file:
e5093e7b7b832fc4c859bd1839b315c38110ccf6565df1dcbb0b0cb5e7055173  docs/architecture-work-plan.md

## Goal and completion criteria (lines 18-34)
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

## P08-P12 gate list, verbatim (lines 216-226)
- [ ] P08: Delegate reproduction and behavior tests, then implementation.
  Independently review both before accepting a candidate.
- [ ] P09: Run the candidate's required Boring checks and Tiqian checks on fixed
  revisions, preserving logs, generated-output identity, and warning results.
- [ ] P10: Classify review failures, revise the appropriate documents, and
  publish the first round's acceptance and reflection record.
- [x] P11: Give an agent a related extension task using the revised documents.
  Assess its reasoning, implementation, and verification against the same
  standards. Apply required checks to any further code changes.
- [ ] P12: Publish the programme review, accepted revisions, evidence gaps,
  and next scheduled mechanisms. Close the goal only when its criteria hold.

## P11 gate (lines 222-224)
- [x] P11: Give an agent a related extension task using the revised documents.
  Assess its reasoning, implementation, and verification against the same
  standards. Apply required checks to any further code changes.

## Gate dependency text (lines 228-240)
P04's three investigations can run concurrently. P05 depends on all three.
P08 depends on an accepted P07 brief and resolved semantic dependencies.
Heavy platform tests use a measured resource limit even when investigation
capacity is available. Start with one heavy verification candidate at a time.
Schedule the P11 guidance exercise after P08's focused acceptance and before
freezing the final P09 candidate when its dependencies permit. This allows
the follow-up fixture or repair to share the final full verification run.
P10's final reflection and P12 still require that verification evidence.
The [storage-lifetime exercise](investigations/architecture-round-1/x-guidance-evaluation.md)
was assigned to Goose at `db1bb984`, with an initial reasoning review before
fixture implementation. Its focused fixture and guidance evaluation are accepted
after integration replay, with the required coordinator interventions recorded.
Broader J work and P09's full candidate verification remain open.

## Status paragraph on P08-P12 open (line 134) and Tiqian paragraph (lines 173-190)
The fixed Tiqian revision is prepared, but the Tiqian candidate gate has not run.
Full Boring verification attempts have run without producing an accepted full
result. `verify-final3` stopped at the TypeScript test step; the diagnostic
`verify-e315bb79` log records a Dart printed-wrapper `.index` failure and
additional Kotlin failure output after its end marker. The latter log does not
establish single-run provenance and cannot certify a Kotlin pass. Its writer
attribution remains unverified by retained process evidence.

The separate focused attempt `out/ts-platformops-imports/attempt-jRePPdut/`
retains 730 passing Bun tests, zero failing Bun tests, and a failing typecheck
with exit 2 (six TS18047 and three TS2322 diagnostics). These results belong
to that attempt and its input manifest; they are not full-verification results.
The later focused attempt `out/ts-platformops-imports/attempt-LcbBaPyn/`
retains typecheck exit 0 with zero TypeScript diagnostics across 204 generated
modules, and 730 passing Bun tests with zero failures. Its input manifest is
distinct from jRePPdut; the earlier failure record remains valid.
`out/ts-nullable-lowering/attempt-WblNuYRS/` passes generation, generated-code
strict typechecking, checker strict typechecking, and runtime checks under
unchanged before/after input hashes. Spec51 coalescing mix remains unverified.
The scoped Dart ordinal repair is signed off: the five stages in
`out/dart-comparison-consumer/runs/attempt-QzEpW1Ee/` pass, with 22 expected
output lines matching and no analyzer issues. That run records HEAD
`ae73c11e`; ordinal equality does not settle payload equality policy.
These focused results are not full-verification or Tiqian gate results.
The full attempts retain their own input identities. Subsequent runner and
documentation changes must not be attributed to those tested inputs.
P08–P10 and P12 remain open pending accepted fixed-input regression evidence.
The fixed Tiqian input remains `8504d230228e8206689a2049bbb84b671c1f079a`.
The previous validation checkout was absent during the latest environment
check; its loss has no established cause. A new locked checkout at the same
revision contains 248 copied local data inputs with matching source and target
hashes. The data's producing revision remains unknown. Earlier reports retain
their original scope; neither the copied inputs nor the new checkout establish
a fresh regression result. Recreate and review the derived compiler paths and
comparison groups before running the final candidate. Retain all 12 generation
and 11 target-test obligations, including the protocol test-root union.
The existing derived Tiqian files identify an older Boring revision; the
[preparation review](investigations/architecture-round-2/tiqian-preparation-review.md)
records why they must be refreshed after the architecture candidate is fixed.

The current candidate must use `ReadOnlyArray` for J's new runtime view and
all references to it. Existing branded mutable-array and exception types remain
separate migration work with recorded public API dependencies. P09 verifies
this bounded candidate; P12 must retain those naming violations in its remaining
work and must not claim complete runtime naming conformance.

## Delivery table (lines 99-106)
| Package | Reviewable code and current boundary | Next acceptance step |
| --- | --- | --- |
| A: types, values, and representation | The Swift array pilot remains an unfinished checkpoint at `e5e21854`; shared source-container facts are integrated at `f104e3bf`. Finite comparison analysis and its Swift consumer are integrated at `4581308d`. The coordinator's source admission run matched 41 rows, and the A3 procedure completed 19 expected stages, including Swift compilation and execution. | Migrate and verify comparison consumers in TypeScript, Kotlin, Rust, and Dart; retain five-target evidence. |
| B: flow and evaluation | B1's focused observation fixture and B2's 167-row source-local presence analysis are integrated. Kotlin now consumes per-occurrence presence in function lowering at `3fb8c565`. The coordinator's focused procedure passed 28 output assertions, two mutation controls, Kotlin compilation, and JVM execution. | Extend this consumer pattern to remaining flow decisions and targets, then run broader regression checks. |
| C: identity and writable places | Classifier and place observation fixtures are integrated at `5eb3429b`; they do not implement the place migration. | Establish place identity and writeback through target lowering. |
| D: control-flow results | The source/target result specification is documented; the policy migration has not begun. | Start after the A and B interfaces required by branch and return construction are accepted. |
| E: intrinsics and platform integration | Swift ordinary-array runtime dependency correction is integrated at `f3a8955a`; broader numeric, string, and module specifications remain open. | Validate target operation and helper closure across the affected languages. |
| F: evidence and diagnostics | Child execution evidence is integrated at `8a2a9c6a`, shared stage membership verification at `d873da91`, and TypeScript source-occurrence fragments at `8a9a8c49`. The corrected package `tsc` diagnostic path is integrated at `c4787f70`; focused replay covers relative and absolute paths, successful child streams, malformed metadata, and existing outside files. | Extend provenance through more lowering paths and preserve layered verdicts. |

## Acceptance-rule line 415 context (lines 414-418)

Generated-code warnings and suppression markers are acceptance failures under
the current standard. Record any baseline failure separately, including its
revision and reproduction; a baseline finding does not waive the standard.
Cross-target agreement supplements assertions against the specified semantics.
