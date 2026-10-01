# Programme review — P12 draft

**Date:** 2026-09-30. **Anchor:** Boring coordination worktree `boring-wt-architecture` at
HEAD `e1c6597514634fd347d392709793cc19bd96c9a2`, branch `arch/agent-guided-governance`,
25 dirty entries (all verified by me in this session; `evidence/git-verification.txt`).
Board state as of the `wb_board` snapshot `updatedAt: 2026-09-30T15:18:41.870Z`
(`evidence/board-m-mulwvr32-3jht.md`).

This is a consolidation from retained evidence. I re-read the sources named below; I
re-ran no builds or tests and re-derived no finding. Every claim is labelled:

- **[DOC: <source>]** — a document states it; I quote it, I did not re-verify it.
- **[VERIFIED]** — I checked it myself in this session (read-only: file reads, git reads,
  board queries).
- **[NOT ESTABLISHED]** — I could not establish it; the blocker and what would establish it
  are named.

## The gate (verbatim)

`docs/architecture-work-plan.md:225-226` — unchecked:

> - [ ] P12: Publish the programme review, accepted revisions, evidence gaps,
>   and next scheduled mechanisms. Close the goal only when its criteria hold.

[VERIFIED: the line exists as quoted and is unchecked in the plan file I read.]

---

## 1. Programme review — standing against the four consultations

The four retained consultations, all dated 2026-09-30 against HEAD `e1c65975` and its
dirty working tree (verbatim copies in `evidence/consult/`):

- `SOL2-ARCH-ANSWER.md` (SOL2)
- `ASTRA-ANSWER.md` (ASTRA)
- `CODEX-AUDIT.md` (CODEX-AUDIT, whole-programme progress audit)
- `CODEX-ARCH-ANSWER.md` (CODEX-ARCH, independent architectural judgment)

### 1.1 What the consultations said (cited)

**Common core.**

1. **Keep the ordinary Swift read-only array boundary as the P08 mechanism; reject the
   current candidate for acceptance.**
   - [DOC: SOL2 §1] "The mechanism is well chosen. The present candidate is incomplete."
   - [DOC: ASTRA §1] "'accept a frozen candidate' is premature as the next implementation unit."
   - [DOC: CODEX-AUDIT §2, P08 row] "An independently accepted reproduction/behaviour
     specification and complete implementation candidate have not been established for the
     selected mechanism."
   - [DOC: CODEX-ARCH Part 1 §1] "Partly. The blocker is failure to make the approved fact
     handoffs hold throughout the selected migration."
2. **Order the next work: baseline budget decision first, then repair, then freeze and two
   independent reviews.** [DOC: SOL2 §2] "Choose d → a → b → c: baseline budget and
   restoration, refused-cell disposition, consumption repair, then freeze and both
   reviews." [DOC: ASTRA §2] "The correct acceptance order is (d) → (a) → (c) → (b)."
   [DOC: CODEX-AUDIT §4] "Suspend unrelated additions to that candidate while this
   acceptance cycle runs."
3. **Retain P09's full meaning; fund baseline recovery separately; do not weaken the
   gate.** [DOC: SOL2 §3] "Fund restoration; keep full P09 acceptance. Make P08 the nearer
   delivery milestone." [DOC: ASTRA §3] "I would retain the acceptance standard and fund
   baseline recovery as a separate delivery responsibility." [DOC: CODEX-AUDIT §2] "The
   programme must actually repair the baseline blockers, or the owner must explicitly
   change the governing acceptance contract."
4. **Fix the destination/requirement handoff with a small explicit interface; no universal
   IR.** [DOC: SOL2 §4] "A small explicit interface is sufficient. A universal target IR is
   unnecessary." [DOC: ASTRA §4] "A small explicit interface is sufficient; this does not
   require a universal target IR." [DOC: CODEX-ARCH Part 1 §1] "The concrete defect is an
   interface that accepts representation facts while its callers can still fabricate those
   facts independently of the operation that emitted the value."
5. **P08 acceptance means both independently recorded reviews accepting the same candidate,
   plus generation exit zero, zero-diagnostics native compile, preserved source behaviour,
   and durable collection.** [DOC: SOL2 §4] "Require durable collection as part of this
   candidate's delivery: the focused tests must enter a routine repository command and CI"
   and "Both must be green, and both independent reviews must accept the complete
   contractual and behavioural obligations on the same candidate." [DOC: ASTRA §4] the
   acceptance table, incl. "CI demonstrably collects and executes the named tests, retains
   their results, and fails when a protected obligation is broken." [DOC: CODEX-ARCH Part
   1 §4] "P08 accepts a conforming implementation candidate for subsequent full
   verification. It cannot close through approval of a document alone." [DOC: CODEX-AUDIT
   §4] six conditions, ending "Behaviour/oracle review and implementation review both
   accept the complete inventory and raw evidence."
6. **Cancel work that cannot change this acceptance decision; integrate the validated
   scratch repairs instead of cancelling them; give P09/P10/P12 explicit board ownership
   alongside the new P08 row.** [DOC: SOL2 §6] "Cancel the following categories as
   execution tasks in this delivery tranche. Preserve their findings and evidence
    without maintaining an active row for every observation." [DOC: ASTRA §6] "The validated scratch repairs should be
   integrated and checked, not cancelled. Give P09, P10, and P12 explicit board ownership
   alongside the new P08 row."

**Named concrete defects** (cited): the W1 swallowed-`return` in `switchExplicitReturn`
[two `swiftc` warnings at `Gap.swift:113/115`; DOC: p08-implementation-review/REPORT.md §6.1
and its §0; the behaviour-review claim ledger]; the nil-merge optional-intermediate
refused cell (SW04; [DOC: ASTRA §1]); the switch/try destination handoff —
`currentReturnType` is member-scoped and `sw.t`-derived destinations are re-derived from
AST ([DOC: p08-implementation-review/REPORT.md §6.2-6.3; CODEX-ARCH Part 2 (a)]); the
tracked-source-mutating test helper ([DOC: CODEX-ARCH Part 1 §1] "`runHaxe` writes the
stub at line 75 and restores it only after the awaited subprocess completes, at line 85";
[DOC: SOL2 §3] "Fund removal of that substitution from the acceptance procedure"); the
stale expectation at `tests/swift-readonly-boundary/readonly-boundary.test.ts:55`
([DOC: p08-implementation-review/REPORT.md §4.6]); the CI collection gap
([DOC: SOL2 §4] "CI omits its collecting command"; [DOC: ASTRA §4] "`ci.yml` invokes
neither that root suite nor the focused test").

### 1.2 What was acted on (status as of this review)

| Consultation recommendation | Status | Evidence |
| --- | --- | --- |
| (a) Freeze candidate, fixtures, record, configuration, input identities together | **Done, then independently confirmed — but the freeze is not an acceptance** | [VERIFIED: `dc-warn/out/p08-candidate-freeze/FREEZE.md` exists, "Frozen at: 2026-09-30T03:55:40-04:00"; its status line reads "the *acceptance* is **not complete**"; it "does **not** accept the candidate" (its §0).] [VERIFIED: `dc-warn/out/freeze-xcheck/REPORT.md` §8 verdict: "**CONFIRMED** — the record's substantive claims are independently reproduced: identity (rows 1–29), reproduction (all direct exit codes), the W1 two-warning disclosure with correct warning/error distinction, the honest 'obligation 2 fails literal zero diagnostics' statement"; "The verdict carries three named findings: **F1** (one non-reproducible hash, on a document the record itself disclaims), **F2** (two-line citation slip), **F3** (lazy effects unmeasured but implied). None of these affects the frozen object." Findings reproduced verbatim in §3.1.] |
| (b) Two separately recorded independent reviews accepting the same candidate | **Not done** | The behaviour review exists ([DOC: p08-behaviour-review/REPORT.md]; at its measurement both discriminating observables were red — generation rc=1; `swiftc` 12 errors / 2 warnings; its claim ledger records both). The implementation review exists and its verdict is **REJECT** with four open conditions ([DOC: p08-implementation-review/REPORT.md §6], read in full by me). The P08 board row `t-munq08t2-rgxp` is still `todo`, 0/3 SOP evidence, unclaimed [VERIFIED: wb_task_show]. [DOC: SOL2 §1] "Such checkpoints cannot stand for acceptance of the complete boundary mechanism." |
| (c) Baseline budget decision (owner + funded recovery, acceptance standard retained) | **Not established** | No owner decision is recorded in the plan, the round-2 queue, or the board snapshot. P09 preparation work advanced on the board (done: `prep/option-c-identity-derive`, `prep/p09-coord-state-inputs`, `prep/p09-driver-from-e1c65975`, `prep/p09-execution-root-e1c65975`, `prep/p09-e1c65975-inputs`; doing: `prep/option-c-plan-cwd-fix` ready for sign-off, `audit/e1c65975-driver-provenance` (P09 B2), `audit/swift-systempackage-provenance` (P09 B3)) [VERIFIED: board snapshot], but none of these is the budget decision [DOC: ASTRA §2 (d)] "Assign an owner and funded recovery work for P09 while retaining the existing acceptance standard." |
| (d) Refused-cell disposition (optional intermediate requirement) before implementation | **Not done in the retained evidence** | The acceptance fixture is still blocked at the optional→required refusal cell at the behaviour review's measurement ([DOC: p08-behaviour-review/REPORT.md Q3.5, Q5: O-A rc=1]); no accepted fix for it appears in the board's done rows or in the coordination tree history [VERIFIED: git log; board snapshot]. |
| (e) W1 (swallowed `return`) repair | **Board-accepted; integration into the frozen candidate NOT ESTABLISHED** | [VERIFIED: board row `t-munu29i9-70b7` is `done`; its confirm record (timeline seq 6, coordinator) states two of the three SOP criteria were independently reproduced by the coordinator (regenerated Gap fixture; `swiftc -typecheck` 0 diagnostics; `.two` returns the correct value on execution).] The frozen P08 candidate (frozen 03:55) predates the W1 acceptance (15:16) and still carries the W1 defect [VERIFIED: freeze-xcheck row 72 — the candidate's gap typecheck is "0 errors, 2 warnings @113,115"; the freeze record discloses "2 warnings (Gap.swift:113, 115 — the known W1 `switchExplicitReturn` swallowed-`return`; unchanged by the patch)" (FREEZE.md §5.2, quoted at freeze-xcheck line 109), and FREEZE.md §7 item 9: "Confirmed unchanged by the patch: the whole function is byte-identical base vs candidate"]. No W1 commit appears in the coordination tree history (top commit `e1c65975`, 2026-09-29) [VERIFIED: git log]. The build-phase `will never be executed` warning was explicitly excluded from the W1 acceptance and is now open ruling row `t-muo92xms-s28t` [VERIFIED: wb_task_show]. |
| (f) Destination/routing repair for all value-producing routes | **Not done beyond (e)** | [DOC: p08-implementation-review/REPORT.md §6.2-6.3] conditions 2-3 (lambda return contract; `sw.t`-derived destinations) remain open against the frozen candidate; the W1 fix is a different defect (statement-arm return emission). |
| (g) Remove the tracked-source-mutating helper | **Not done** | No repair record in the retained evidence I read. [DOC: SOL2 §3] required "Fund removal of that substitution"; [DOC: freeze-xcheck/REPORT.md §7] only verified the guard file (`MathNaNTestSupport.hx`, five `Test.equals`) intact before/after its own runs. |
| (h) Durable collection (focused tests into routine command and CI) | **Not done** | [VERIFIED: `.github/workflows/ci.yml` both jobs (line 35 linux, line 135 macOS) chain only `gen:*`, `test:stage1:*`, `test:haxe/kotlin/rust/swift/swift-f32/dart/kotlin-f32/rust-f32`, `test:consistency`, `check:*` — the bare `test` script (`"test": "bun test tests/ packages/registry/tests/"`, `package.json:9`) is absent; grep for `bun run test ` returns no match (`evidence/ci-and-scripts.txt`)]. [DOC: p08-implementation-review/REPORT.md §4.6] "`bun test tests/swift-readonly-boundary/` in my copy: **rc=1 at `readonly-boundary.test.ts:55`** — the oracle-step expectation — before generation, before `swiftc`, before the runtime comparison"; [VERIFIED: freeze-xcheck row 78 — the scoped bun suite exits 1 at `readonly-boundary.test.ts:55`, tagged "pre-existing", the record's claim "disclosed, reproduced", verdict MATCH.] |
| (i) Cancel non-contributing work / retire superseded preparations | **Not acted on the board as of the snapshot** | [DOC: SOL2 §6] categories: "Further general consultations, repeated RECORD rewrites and audit-of-audit tasks", "Further attempts to obtain the same unavailable review provider", "Duplicate runner-identity, provenance, loader and sealing initiatives", "Cancel this tranche's roots-guard defeat campaign and rejected F3 approach", "Cancel duplicate-HXML cleanup, worktree tidying and attempt pruning as gate prerequisites", and "additional string-unit, loop, filesystem, comparison, naming or cross-target expansion work". [DOC: ASTRA §6] categories: "Duplicate audits and recurring rewrites of the same ownership record", "Preparations, manifests, and reviews tied exclusively to superseded candidates", "Broad exploratory surveys without a named gate dependency" (filesystem, string, default, loop, place work), "General evidence-tooling expansion beyond what this candidate needs" (speculative hardening, universal tracing/source-map work), "Repository hygiene and unrelated public-name migration" (defer "duplicate-root cleanup, artifact housekeeping, and existing branded-runtime renaming"), "Additional cross-target architecture migrations unrelated to the selected mechanism or a funded P09 blocker" — while "Keep SW04, destination/routing completion, the focused CI guard, necessary runtime compatibility, funded baseline repairs, P09 execution, and P10/P12 acceptance records". As of the snapshot the corresponding rows are still active on the board (full transcription in `evidence/board-m-mulwvr32-3jht.md`): `fix/roots-guard-defeat-classes` (todo), `fix/roots-guard-hardening` (doing, 3/3, ready for sign-off), `chore/dedupe-hxml-roots`, `chore/archive-xs-fixture-family`, `chore/option-c-attempt-prune` (todo), `fix/rust-string-expectation-family` (todo), `fix/rust-module-keyed-read-sites` (todo), `fix/test-timeout-budget` (todo), the runner-identity/provenance rows `fix/runner-identity-and-provenance`, `fix/runner-compiler-provenance`, `fix/tsc-runner-identity` (doing), and the exploratory observation rows (e.g. the Swift default-argument string-length row, the mutable-bounds loop row, the container-alias row) [VERIFIED: wb_board re-query, same snapshot `updatedAt: 2026-09-30T15:18:41.870Z`. The nuance that "The validated scratch repairs should be integrated and checked, not cancelled" [DOC: ASTRA §6] was also not carried out: [DOC: CODEX-AUDIT §1] the string-family, timeout-budget, rust-modkey and roots-guard patches remain in scratch trees with repository assertions unchanged or uncollected. |
| (j) Explicit board ownership for the P08/P09/P10/P12 gates | **Partially done** | The P08 gate row exists (`t-munq08t2-rgxp`, created 2026-09-30T06:24:43) [VERIFIED]. P09 has sub-work rows but no gate row owning "run P09's fixed-pair verification"; P10 and P12 have no rows at all [VERIFIED: board snapshot]. The plan's gate list (`architecture-work-plan.md:216-226`) remains the only place P09–P12 exist. |
| (k) Keep P07/J phase limits (J1/J2 checkpoints are not acceptance of the complete mechanism) | **Held** | [VERIFIED: the P08 board row is open and the plan's P08 gate is unchecked] [DOC: SOL2 §1] "J1/J2 checkpoints may retain explicitly unaccepted J3 work. Such checkpoints cannot stand for acceptance of the complete boundary mechanism." |

### 1.3 What was not acted on (summary)

As of this review: no independent review accepts the P08 candidate; no baseline budget
decision is recorded; the destination-handoff repair (conditions 2-3 of the
implementation review), the helper removal, and the CI collection wiring are all still
open; the stale focused-test expectation is still red; the scratch repairs are still in
scratch; the cancellation recommendations are not reflected on the board; and no board
row owns the P09/P10/P12 gates. [Each item is evidenced in §1.2; nothing here re-derives
a new gap.]

### 1.4 Positions that were rejected or contested (with the rejecting source)

- **SOL's (first consultation) recommendation to make acceptance of a new boundary policy
  record the next milestone** — rejected: [DOC: CODEX-ARCH Part 1 §2] "I differ from SOL's
  recommendation to make acceptance of a new boundary policy record the next milestone."
  (SOL-ANSWER.md itself was not re-read by me; it is not one of the four named sources —
  the rejection is documented in CODEX-ARCH.)
- **The requester's framing "no mechanism has a defined producer"** — qualified by all
  four: [DOC: CODEX-ARCH Part 1 §1] "overstates the evidence"; [DOC: ASTRA §4] "I also
  qualify 'the destination requirement has no producer at all'"; [DOC: SOL2 §4] "I also
  qualify 'no producer at all' and 'six producers proves the one-producer rule false'."
- **The latest boundary record's proposed acceptance** (calling absence of known
  re-derivations "unachievable as written", proposing to eliminate or individually rule on
  them) — rejected: [DOC: CODEX-AUDIT §2] "A ruling cannot simply relabel an
  implementation violation as accepted"; [DOC: CODEX-ARCH Part 2 (a)] "Yes. Keep
  NOT-ACCEPTABLE for an acceptance-ready record."
- **The behaviour review's sentence that the defect class closes when O-A and O-B are
  green** — rejected: [DOC: SOL2 §4] "I therefore reject the behaviour review's sentence
  that the class closes when O-A and O-B are green."
- **The gap-fixture-archive README's claim that "the repo's CI … runs `bun test tests/`"**
  — falsified: [DOC: p08-behaviour-review/REPORT.md Q5 table] "the archive's opposite
  claim … is contradicted by the CI file"; [VERIFIED: the CI file does not invoke the
  bare `test` script — `evidence/ci-and-scripts.txt`].
- **The localisation report's attribution of the recorded invocation's refusal to the
  veto at `SwiftArrayBoundary.hx:225-231`** — corrected: [DOC: ASTRA §1] "The retained
  instrumented trace reports `OptionalOperand` and `NoPresenceProof`. The veto at lines
  225–231 requires `RequiredOperand`, so it cannot be the rejecting condition … The
  applicable refusal is the optional operand with a required destination at line 203."
- **"166 numeric divergences"** — corrected: [DOC: ASTRA §3] "the independently checked
  166 divergences comprise **160 missing test IDs and six extra IDs**, not 166 numerical
  disagreements … 166 is a historical baseline observation, not a certified current
  count."
- **The timeout report's "150x" budget arithmetic** — corrected: [DOC: CODEX-AUDIT §3]
  "the ratio is about 5.6".
- **The roots-guard F3 model** — falsified: [DOC: CODEX-AUDIT §3] "The F3 model is wrong,
  and its claimed compiler agreement is not trustworthy."
- **The "48 are pre-existing" attribution as full change attribution** — limited:
  [DOC: CODEX-AUDIT §3] "Its stronger suggestion that identical names settle all change
  attribution is unsafe."
- **GLM's endorsement of the one-producer table and Qwen's "no correction needed"
  statement** — [DOC: CODEX-ARCH Part 2 (a)] "The review was too lenient in some positive
  conclusions … go beyond what their own findings establish."
- **"Already converted means never convert again"** — [DOC: CODEX-ARCH Part 2 (a)]
  "independently wrong."
- **ASTRA's own partial correction of the CI claim** (repository scripts *do* collect the
  test because `verify` invokes `bun run test`) — the scripts part stands
  [VERIFIED: `package.json:9` defines the `test` script collecting `tests/`], but the
  collection gap stands: the driver short-circuits that command [DOC: ASTRA §4] and CI
  never invokes it [VERIFIED: `evidence/ci-and-scripts.txt`].

---

## 2. Accepted revisions

Strict test applied: a patch existing in a scratch worktree is **not** an accepted
revision. Acceptance here means either (a) a board row with status `done` under
milestone `m-mulwvr32-3jht` (whose sign-off, per board convention, is a `confirm=`
written by the captain or a human), or (b) a revision formally accepted in repository
documentation.

### 2.1 Board rows accepted (status `done`)

33 done rows at the snapshot (full transcription in `evidence/board-m-mulwvr32-3jht.md`).
By kind:

**Six compiler-fix rows** (the only accepted *compiler* revisions among the rows):

| handle | branch | what was accepted (row title / SOP evidence) |
| --- | --- | --- |
| `t-munu29i9-70b7` | `fix/swift-switch-explicit-return` | W1: Swift `switchExplicitReturn` no longer drops each arm's value and unconditionally returns `sourceFirst()`; each statement arm keeps `return <value>`; Gap fixture `swiftc -typecheck` 0 error / 0 warning; `.two` returns the correct value on execution. Confirm record (read by me): coordinator accepted with two criteria independently reproduced; the build-phase `will never be executed` warning is **explicitly out of scope** of this acceptance. |
| `t-mun8mco9-f8e2` | `fix/rust-fault-variant-regression` | Rust fault-variant registration regression (PIT-248) repaired. |
| `t-mun5d99p-op76` | `fix/swift-generated-tree-runtime` | Swift generated-tree compile failure from missing `Runtime/BoringException` repaired. |
| `t-mun3ejy5-16zz` | `fix/dart-fallthrough-nullguard` | Dart fall-through null-guard local non-null promotion repaired. |
| `t-mumupdbv-j6m0` | `fix/rust-readonly-alias-emitter` | Rust read-only view return and mutable binding repaired. |
| `t-mumupzh0-k12r` | `fix/rust-typedef-signed-key` | Rust typedef signed-key comparison repaired. |

**Six arch/ rows:** re-reviews of the four target comparison-consumer candidates
(`t-mulwwerf-dq5b` Rust, `t-mulwweou-8zqh` TypeScript, `t-mulwwesk-5iq1` Dart,
`t-mulwweq3-a5vi` Kotlin — acceptance of the *review* work), plus `t-mum85x1t-9wej`
(TS nullable-call/constructor-argument normalization repair) and `t-mum8255v-pti4`
(Dart payload-enum-comparison representation-regression repair).

**Eight prep/ rows:** P09 / Option-C preparation (`prep/coord-state-sync-1433`,
`prep/option-c-identity-derive`, `prep/p09-coord-state-inputs`,
`prep/p09-execution-root-e1c65975`, `prep/option-c-freeze-apply`, `prep/option-c-selftest-33`,
`prep/p09-driver-from-e1c65975`, `prep/p09-e1c65975-inputs`) — accepted *preparation* work,
not a run of P09.

**Thirteen audit/ rows:** observations and audits (`audit/dc-ts-sourcemap-extend`,
`audit/dc-enum-switch-gen`, `audit/dc-place-ts-swift`, `audit/dc-parameter-identity`,
`audit/dc-kotlin-manifest-version`, `audit/rust-fix-candidate-integration`,
`audit/worktree-archive-inventory`, `audit/candidate-freeze-merge-review`,
`audit/p09-fixed-matrix-preparation`, `audit/signed-int-key-composition`,
`audit/readonly-alias-evidence`, `audit/kotlin-staticfn-publication-evidence`, `audit/registry-consumer-negative-control`). Note
`audit/p09-fixed-matrix-preparation` is titled "固定版本 Boring 与 Tiqian 全矩阵验收" but its
branch is the *preparation* audit; [DOC:
docs/investigations/architecture-round-2/candidate-integration-queue.md:75-78] the
round-2 queue states the remaining work is "the coordinator selects one Boring revision,
reruns the affected Boring checks, refreshes the fixed Tiqian checkout's derived inputs,
and completes its twelve generation and eleven target-test obligations. P08, P09, P10, and
P12 remain open until that evidence and the programme review are complete." I did not read
that row's full confirm record; what exactly its acceptance covered beyond its title is
[NOT ESTABLISHED] — the confirm record would establish it.

**Evidence quality:** I read the full sign-off record (confirm text, SOP evidence lines,
timeline) of `t-munu29i9-70b7` only. For the other 32 rows, "accepted" rests on the board's
`done` status at the snapshot plus the transcribed titles/SOP text; I did not re-read each
timeline. The board's `branches.mode` was `noop` (`spawnSync but ENOENT`), so the board
itself establishes nothing about branch state [VERIFIED: snapshot field].

**Integration into the coordination tree (my verification):** the two Rust fix rows
correspond to the two most recent integrated commits — `0701762d` "fix(rust): slice return
clone via to_vec and indexed field-root mut binding" merged by `e1c65975` (HEAD), and
`741a2acd` "fix(rust): order typedef structure key Int fields as signed values" merged by
`1e5daa33` [VERIFIED: git log, `evidence/git-verification.txt`]. The W1 row's acceptance was
verified in the `w1-wt` worktree per its confirm record; its integration into the
coordination tree or the frozen P08 candidate is [NOT ESTABLISHED] — no W1 commit appears in
the tree history (top commit `e1c65975` is 2026-09-29, before the 2026-09-30 acceptance), and
a commit or a new freeze record would establish it. For the remaining four fix rows I did
not map row to commit either way; row-by-row mapping is [NOT ESTABLISHED].

### 2.2 Revisions formally accepted in repository documentation

- [DOC: docs/architecture-work-plan.md:99-106 delivery table, plus :160] records ten
  accepted integrations: `f104e3bf` (A2 source-container facts), `4581308d`
  (A3 finite comparison with Swift consumer), `3fb8c565` (B2 Kotlin local-presence
  consumer), `5eb3429b` (A/C diagnostic fixtures), `f3a8955a` (E Swift ordinary-array
  runtime dependency closure), `8a2a9c6a` (F1 child execution evidence), `d873da91`
  (F2 shared stage-membership verification), `8a9a8c49` (F TS source occurrences through
  emitted fragments), `c4787f70` (F tsc diagnostic path correction), `cde5e97c` (enum
  comparison fixture, "with its source ruling still pending", plan:160). The same
  delivery table lists `e5e21854` as an *unfinished checkpoint*, not an integration.
  All ten accepted integrations are present in the coordination tree's git history
  [VERIFIED: `evidence/git-verification.txt`].
- [DOC: CODEX-AUDIT §1] "commit `2159c657` and the current callers show those consumers
  integrated" — i.e., the four comparison-consumer migrations the plan's table still lists
  as a next acceptance step. `2159c657` "refactor(compiler): migrate target comparison
  policy consumers" is present in the tree history [VERIFIED]. Whether the four done
  re-review rows' accepted bytes equal that commit's bytes is [NOT ESTABLISHED].
- **P11 (the guidance exercise):** [DOC: plan:222-224] P11 is marked `[x]`; [DOC:
  docs/investigations/architecture-round-1/x-guidance-evaluation.md:95] "The coordinator
  accepts the eight-file fixture after exact-file integration…" A formally accepted
  guidance exercise — with the caveat [DOC: CODEX-AUDIT §1] "P11 is a completed guided
  exercise … Reliable unaided agent execution, exhaustive lifetime correctness, and
  complete J migration were not established."
- **Not an acceptance:** `e5e21854` — [DOC: plan delivery table] "The Swift array pilot
  remains an unfinished checkpoint at e5e21854"; it is retained as an unfinished
  checkpoint, not accepted.

### 2.3 What is NOT accepted (stated plainly)

- **The P08 frozen candidate is not accepted.** [DOC: FREEZE.md status line] "the
  *acceptance* is **not complete**"; [DOC: p08-implementation-review/REPORT.md §6] verdict
  REJECT, four open conditions; [VERIFIED: board P08 row `todo` 0/3].
- **No scratch worktree patch is an accepted revision.** [DOC: CODEX-AUDIT §1] string-family
  fix: "The patch is in scratch, and inspected repository assertions remain unchanged"
  (48→35, seven errors remain); test-timeout-budget: "The patch is not integrated into the
  inspected repository tests" (48→25); rust-modkey: "The class-keyed machinery is absent
  from the inspected integration tree, and the fixture is not collected by a runner";
  roots-guard-f2: "The repository still has the original guard". I did not re-verify these
  scratch states myself (this review consolidates; re-inspection would establish the
  current state).
- **No accepted P09 full-matrix run.** [DOC: plan:108] "The fixed Tiqian revision is
  prepared, but the Tiqian candidate gate has not run." [DOC: plan:109-114] the recorded
  Boring verification attempts "failed to produce an accepted full result" (`verify-final3`
  stopped at the TS test step; `verify-e315bb79` recorded a Dart failure and a Kotlin
  output without single-run provenance).

### 2.4 The plain count

The accepted compiler revisions are **few**: six board-accepted fix rows (two verified by
me as merged into the coordination tree; one — W1 — accepted but integration not
established), plus the ten plan-recorded integrated commits (focused integrations of the
A/B/E/F policy packages, each with its recorded focused acceptance) plus one P11 guidance
fixture. The programme's central deliverables — an **accepted P08 candidate** and an
**accepted P09 fixed-pair regression** — **do not exist**. That is the honest count; the
33 done rows are mostly audit/preparation/observation work, not accepted compiler
revisions.

---

## 3. Evidence gaps

Consolidated from the retained reviews and cross-checks. Nothing below is newly derived;
each gap is quoted from its source.

### 3.1 What the freeze cross-check listed as unverified

[DOC: dc-warn/out/freeze-xcheck/REPORT.md §6 "What I could not determine", verbatim:]

1. "Why the worktree REPORT.md hash does not match (F1): live mtime 03:20:48 predates the
   freeze (03:55:40), so a stat at freeze time should have seen 03:20:48 — the record's
   03:04:57 either comes from a pre-03:20 measurement, a copied value, or stale fuse
   attribute reporting. Unresolvable from here without the author's raw stat."
2. "Earlier RECORD.md revisions (131/186/279/362/367-line): the drift chain is quoted
   from the consult/review reports (which I hash-verified); the old contents no longer
   exist, so only the 390-line live state is verifiable."
3. "Full `bun test tests/`: not run (the known guard-file trap in
   `package-artifacts.test.ts`); scoped suite only, in the /tmp copy; guard file intact
   (5)."
4. "`/tmp/p08ir` persistence: verified while present (row 15); it is transient /tmp and
   correctly excluded from the bundle."

[DOC: freeze-xcheck/REPORT.md §7 Findings, verbatim:] **F1 — one stated hash
irreproducible**: `swc-try-fix-wt/REPORT.md` (record: `cd95e27f…`, mtime 03:04:57; live:
`1778a60d…`, mtime 03:20:48, 7433 B) — "The record itself marks this file 'NOT the
record that accepts this candidate' and excludes it from the bundle; no effect on the
frozen object." **F2 — line-citation slip**: the OtherArrayStorage REFUSED row is cited
as `RECORD.md:58`; it is at line **56** (the quoted text itself verbatim accurate).
**F3 — lazy-effect conflation**: "single evaluation / lazy effect" mapped to one counter
line; single evaluation is measured, lazy effects are not. "Everything else — all
freeze-load-bearing hashes, both reproduction pipelines, gap before/after, route fixtures,
the bundle, counts, and quotes — is independently reproduced byte-for-byte."

And the freeze record's own honest remainder [DOC: FREEZE.md §7 "Not verified / open /
stale — the honest remainder"]: full `bun test tests/` "never run by anyone quoted
here"; `bun test tests/swift-readonly-boundary/` "not run by me, and it cannot pass as it
stands"; the route-fixture negative controls not re-run; other targets not rebuilt; "The
gap fixture is never executed — only typechecked"; at freeze time "Second independent
review (implementation) — not delivered … Until it lands, the two-review requirement
cannot be met" (it has since landed: the REJECT cited in §3.2); open defects: W1
unchanged, the REFUSED-cell contradiction (§4.3), reconstruction not removed,
`RECORD.md` drifted past the first review, the archive `swiftc-version.log` "is a failed
invocation, not a version", no retained artifact of the candidate-generated `Gap.swift`,
the 29-vs-30 runtime line-count mismatch; and the stale expectation "adjudicated, fix
supplied as `CANDIDATE.diff` in the ruling directory, not applied".

### 3.2 What the implementation review named as open conditions

[DOC: p08-implementation-review/REPORT.md §6 — heading "Verdict — **REJECT** the
candidate for P08 acceptance"; "REJECT, with these exact conditions" — four numbered
conditions, verbatim, ellipses mark my truncations:]

1. **Obligation 2 (legal generated output — zero diagnostics).** "On the candidate's own
   gap-fixture input, `swiftc -typecheck` prints **2 diagnostics**, and the same two
   sites are a wrong control exit (`switchExplicitReturn(.two)` → `2`, oracle `1`). Fix
   or obtain a written gate ruling: … or have the gate owner record an explicit warning
   allowlist for the two `[#no-usage]` diagnostics, in writing, as the archive's
   `README.md:181-182` asks. A reviewer cannot waive an obligation; only the owner can."
2. **Obligation 1 (correct fact-and-requirement handoffs — actual destinations;
   in-scope reconstruction removed), lambda return.** "`currentReturnType` is the
   **member's** return type, written once at `:544` and not rebound by
   `functionLiteral` `:2338-2345`. … Required change: carry the **actual return
   contract** (seeded from `f.t` for a literal, saved/restored around
   `functionLiteralInner`) and use it at `:810`, `:5296`, `:5310`, `:5675`."
3. **Obligation 1 (remove in-scope reconstruction), switch/try.** "`switchExpression`
   `:5559` / `switchBindingLines` `:5514-5517` … still derive both the closure result
   type and the arm destination from the switch's own AST type, and the emitted local
   carries no annotation. Required change: give `switchExpression` an explicit
   destination parameter supplied by the owning contract …" — with the reviewer's own
   caveat that they "observed **no divergence** in 11 instrumented generations
   (§4.2)"; the condition "rests on obligation 1's 'in-scope reconstruction is removed'
   wording, not on a demonstrated failure".
4. **Not a condition on the patch, but on the delivery.** "the repo's own collector
   (`tests/swift-readonly-boundary/readonly-boundary.test.ts:55`) is red on a **stale
   expectation** in both trees, so no repo command currently exercises the candidate's
   generation/`swiftc`/runtime claims; the gap fixture has no collector at all. … the
   two focused observations need to enter a routine command before the delivery can
   claim 'durable collection'".

Plus [DOC: p08-implementation-review/REPORT.md §7 "What I could NOT verify", five
items]: (1) "`LiteralProvenPresent` on a non-literal static read-only initializer — not
verified" (the policy rejects every non-sanctioned form before it runs; "I cannot say
the over-claim is sound if the policy is widened"); (2) "Double conversion /
repeated-render corruption in `destinationValueText` — not verified as impossible";
(3) "Whether `sw.t` can ever differ from the declared binding type — not falsified, not
proven impossible. 11 instrumented generations show none"; (4) "The gap fixture's
runtime behaviour as a whole — not verified. I executed the W1 function only; the
fixture ships no oracle or test runner"; (5) "CI collection of either focused fixture
— not verified. I confirmed the repo test is red and read the CI finding second-hand; I
did not run CI".

### 3.3 The known collection gap

**CI never runs the command that would collect `tests/**`.**

- [VERIFIED (my own read):] `package.json:9` defines the root collector
  `"test": "bun test tests/ packages/registry/tests/"`, which collects
  `tests/swift-readonly-boundary/readonly-boundary.test.ts` and the other `tests/` suites.
  Both CI jobs — linux (`ci.yml:35`) and macOS (`ci.yml:135`) — chain only `gen:*`,
  `test:stage1:*`, the per-target `test:*` scripts, `test:consistency` and the four
  `check:*` scripts. A grep for the bare `test` invocation (`bun run test `) in `ci.yml`
  returns no match (`evidence/ci-and-scripts.txt`). Nothing in CI collects `tests/**`.
- The same gap, named by the sources: [DOC: SOL2 §4] "Today the existing harness aborts
  before native checks, CI omits its collecting command, and the gap fixture has no
  repository collector." [DOC: ASTRA §4] "`ci.yml` invokes neither that root suite nor the
  focused test." [DOC: p08-behaviour-review/REPORT.md Q5 table] "Not collected by CI:
  `.github/workflows/ci.yml` invokes only `test:*` scripts … never `bun run test`"; the
  gap fixture O-B is "not run anywhere; no collector, no CI step". [DOC:
  p08-implementation-review/REPORT.md §4.6/§6.4] as in §3.2. [DOC:
  dc-warn/out/gap-fixture-archive/README.md:163-167] "This gap fixture is collected by
  nothing" — and that README's claim that CI runs `bun test tests/` is false per my
  verification and per the behaviour review's Q5 table.
- Compounding (not new): the local collector is "red on a **stale expectation** in both
  trees, so no repo command currently exercises the candidate's
  generation/`swiftc`/runtime claims" [DOC: p08-implementation-review/REPORT.md §6.4],
  and the focused harness "cannot generate the candidate's own obligation-2 evidence" —
  "rc=1 at `readonly-boundary.test.ts:55` — the oracle-step expectation — before
  generation, before `swiftc`, before the runtime comparison" [DOC:
  p08-implementation-review/REPORT.md §4.6].

### 3.4 Other gaps the consultations and reviews named (quoted, not re-derived)

- **Planning inputs before a budget commitment** [DOC: SOL2 §3]: a combined residual
  baseline ("Do not add the scratch improvements together to predict a combined result.
  They used different input states. Obtain one fresh combined measurement at the
  integration checkpoint"); a bounded account of the 166 divergences; a feasible Tiqian
  execution route ("The preparation runbook is the starting file; preparation is not
  execution evidence"); a finite expanded-programme completion inventory.
- **Baseline debt is not enumerated** [DOC: ASTRA §3] "The measured 48 failures are not
  proof that the entire debt has been enumerated: the attribution report identifies an
  execution copy with emptied assertion helpers"; the first funded tranche "should integrate and verify the existing
  timeout and justified string-expectation repairs, integrate the
  Swift runtime-compatibility repair, and establish correct comparison membership"
  [DOC: ASTRA §3].
- **Provenance problems** [DOC: CODEX-AUDIT §3]: the tracked-source-mutating helper
  ("writes an empty-body replacement into tracked `MathNaNTestSupport.hx`, then restores
  it only after a normal asynchronous return"); the "48 are pre-existing" attribution
  limit; the Rust repair compile's **six warnings** ("fails the repository's zero-warning
  acceptance standard"); the falsified roots-guard F3 model; the manifest's "19 supported
  cells and 14 unsupported cells out of 33" with prose understating the unsupported count.
- **P09 minimum evidence** [DOC: CODEX-ARCH Part 1 §5]: candidate+input identity; the full
  root verification with all ten declared configurations; Tiqian's twelve generation and
  eleven target-test obligations at pinned `8504d230228e8206689a2049bbb84b671c1f079a`;
  actual routing; retained outcomes. "The current root `verify` script extends well beyond
  the driver comparison. Its required checks must be expanded before scheduling … If
  Tiqian is absent locally, P09 remains pending consumer evidence … I have not checked
  current Tiqian availability … so I make no availability or pass claim."
- **Uncertain or unestablished (audit's own list, verbatim)** [DOC: CODEX-AUDIT §6]
  "Uncertain or unestablished: that the four gates have *never* closed historically;
  current Tiqian/toolchain availability and protocol-C authorization; whether later,
  uncited runs supply missing regression evidence; all source-language reachability
  conditions in the static Swift attacks; the cause of lost worktrees/artifacts; the
  precise interrupted execution that hollowed the source; and the semantic
  acceptability of the Rust error-propagation change." The same audit (line 7) states
  "The documents support P08, P09, P10 and P12 being open now; I did not establish
  that none ever closed temporarily".
- **Behaviour review's could-not-determine list** [DOC: p08-behaviour-review/REPORT.md §8]:
  `@:native`/intrinsic exclusions; the double-wrap cell; `SwiftDecl.hx:597`; the runtime
  oracle's reachability while O-A is red; full package build/runtime of the gap fixture;
  the quoted RECORD.md revision ("`e20cf625…` — not reproducible … the file I measured is
  367 lines … and it changed mid-session"); classifier disagreement on a
  typedef/`Null` corner case. Plus the Q5 table row: "A plan-level assertion for the
  optional→required sub-cell: nowhere … absent."
- **The naming violations P12 must carry** [DOC: plan:186-190] "P09 verifies this bounded
  candidate; P12 must retain those naming violations in its remaining work and must not
  claim complete runtime naming conformance." — this review therefore records the
  `ReadOnlyArray`/branded-runtime naming violations as remaining work and claims no
  complete runtime naming conformance.
- **Expanded-programme completion scope** [DOC: CODEX-AUDIT §2] "The inspected status
  material does not provide a sufficiently current, finite list of the migrations whose
  completion would finish that expanded milestone"; [DOC: SOL2 §6, citing
  compiler-policy-architecture.md:151] "the owner must explicitly settle its finite
  completion scope before P12 can close."

---

## 4. Next scheduled mechanisms

- **The plan's own statement** [DOC: plan:32-34] "The initial scope ends with that
  evaluated cycle. Further mechanisms remain separate scheduled work. Completion does not
  establish universal compiler correctness or the absence of regressions outside the
  tested domain."
- **The ordered mechanism work list** [DOC:
  docs/investigations/architecture-round-1.md:263-275, "The resulting work order is:"]:
  1. "Establish explicit boundary decisions and their source/target distinctions. Swift
     array conversion remains the first investigation …" — this is the mechanism currently
     under P08 review.
  2. "Prepare numeric conversion and operand-evaluation specifications independently."
  3. "Apply established evaluation facts to string operations and null proofs."
  4. "Carry branch result and exit intent into target structure after the relevant flow
     and evaluation specifications exist."
  Mechanisms **2-4 are the scheduled successors** of the current Swift boundary mechanism.
- **Per-package next acceptance step** [DOC: plan delivery table, lines 99-106]:
  A — "Migrate and verify comparison consumers in TypeScript, Kotlin, Rust, and Dart;
  retain five-target evidence" (note: [DOC: CODEX-AUDIT §1] the migration itself appears
  integrated at `2159c657` [VERIFIED: commit present in history]; the verification and
  acceptance are what remain); B — "Extend this consumer pattern to remaining flow
  decisions and targets, then run broader regression checks."; C — "Establish place
  identity and writeback through target lowering."; D — "Start after the A and B
  interfaces required by branch and return construction are accepted."; E — "Validate
  target operation and helper closure across the affected languages."; F — "Extend
  provenance through more lowering paths and preserve layered verdicts."
- **The J (prepared-value) phased implementation** [DOC: plan P07 gate, lines 206-215]:
  the revised document "must name the phased implementation and acceptance conditions";
  [DOC: SOL2 §1] "J1/J2 checkpoints may retain explicitly unaccepted J3 work. Such
  checkpoints cannot stand for acceptance of the complete boundary mechanism."
- **Board rows that name a next mechanism** [VERIFIED: board snapshot]: the P08 gate row
  `t-munq08t2-rgxp` ("接受一个冻结的 Swift 只读数组边界实现候选（含 11 家族矩阵与两份独立评审）"
  — accept the frozen Swift read-only-array boundary candidate, 11-family matrix plus two
  independently recorded reviews); the W1 residual ruling row `t-muo92xms-s28t` ("裁定
  build 期诊断 … 是否属验收口径" — created immediately after the W1 acceptance, 2026-09-30
  15:18); and the P09 sub-work rows named in §1.2(c).
- **What the plan does not name:** the plan names the ordered work order and the
  per-package next-step column; it does **not** name a single consolidated "next
  mechanism" after the current one beyond work orders 2-4. **No board row names P09, P10
  or P12 as a gate task** — the plan's gate list (plan:216-226) is the only place those
  gates exist [VERIFIED: board snapshot]. The consultations' implied sequence — finish the
  P08 acceptance cycle (destination-handoff repair → freeze → two accepting reviews), then
  P09's fixed-pair verification [DOC: SOL2 §2; ASTRA §2] — is a consultation
  recommendation, not a plan statement. I state that rather than inventing a plan-named
  successor.

---

## 5. The closure question

P12: "Close the goal only when its criteria hold." The criteria are the five completion
conditions at [DOC: plan:18-31]:

1. "A revision-specific survey covers TypeScript, Kotlin, Rust, Swift, and Dart, maps
   recurring failures to compiler responsibilities, and records unknowns."
2. "The repository documents task assignment, architectural review, verification, and
   reflection, with clear ownership for each kind of decision."
3. "Execution agents complete one selected mechanism change through its analysis,
   representation, lowering, and printing consumers as applicable."
4. "The accepted candidate has fresh Boring checks and the required Tiqian platform
   regression evidence from a recorded pair of revisions."
5. "A later agent task exercises the revised guidance on another case. Review records
   whether the agent used the intended reasoning and where guidance still failed.
   Passing tests alone do not establish this condition"

| Criterion | Holds? | Evidence |
| --- | --- | --- |
| 1. Five-target survey mapping failures to responsibilities, unknowns recorded | **First-cycle scope: yes (as the plan records it). Expanded scope: NOT ESTABLISHED.** | [DOC: plan] P04/P05 marked `[x]`; [DOC: architecture-round-1.md:232-279] the responsibility map was accepted "for planning" with unknowns explicitly recorded ("This remains a sampled architecture survey, with runtime behavior and uninspected forms explicitly unresolved"). For the expanded programme: [DOC: CODEX-AUDIT §2] "does not provide a sufficiently current, finite list of the migrations"; [DOC: SOL2 §6, citing compiler-policy-architecture.md:151] "the owner must explicitly settle its finite completion scope before P12 can close". |
| 2. Repository documents assignment, review, verification, reflection with clear ownership | **Yes (as the plan records it)** | [DOC: plan:36-72] "Roles and authority" and "Document responsibilities"; [DOC: plan] P06 `[x]` (guidance updated from findings); the implementation standard is the binding acceptance authority [DOC: plan:63]. No contrary evidence in the sources I read; the CODEX-AUDIT §5 critique ("The coordinator's control of completion is part of the defect") is a quality critique of execution, not a finding that the documentation/ownership structure is absent. |
| 3. One selected mechanism change completed through its consumers | **No** | The selected mechanism (Swift read-only array boundary) has a frozen candidate and two reviews; the implementation review verdict is REJECT with four open conditions [DOC: p08-implementation-review/REPORT.md §6]; the freeze record states acceptance is not complete [DOC: FREEZE.md status line]; the plan's P08 gate is unchecked [VERIFIED: plan:216]; [DOC: CODEX-AUDIT, overall judgement] "no demonstrated, accepted completion of the programme's integration cycle." |
| 4. Accepted candidate with fresh Boring checks and Tiqian regression from a recorded revision pair | **No** | [DOC: plan:108] "the Tiqian candidate gate has not run"; [DOC: plan:109-114] the recorded Boring attempts "failed to produce an accepted full result"; [DOC: plan:134] "P08–P10 and P12 remain open pending accepted fixed-input regression evidence"; Tiqian availability and current routing [NOT ESTABLISHED] [DOC: CODEX-ARCH Part 1 §5; CODEX-AUDIT §6]. |
| 5. Later agent task exercises revised guidance; review records intended reasoning and remaining failures | **Yes, with recorded caveats (as the plan records it)** | [DOC: plan:222-224] P11 `[x]`; [DOC: x-guidance-evaluation.md:95] "The coordinator accepts the eight-file fixture after exact-file integration"; [DOC: CODEX-AUDIT §1] "P11 is a completed guided exercise … Reliable unaided agent execution, exhaustive lifetime correctness, and complete J migration were not established." |

**Conclusion: the criteria do not hold.** Criteria 3 and 4 fail on the programme's own
records, and criterion 1 holds only in the first-cycle reading — the expanded programme's
finite completion scope is unsettled. I found no evidence in the retained sources that the
criteria do hold; the strongest contrary evidence is the programme's own: the unchecked
P08/P09/P10/P12 gates, plan line 134 ("P08–P10 and P12 remain open pending accepted
fixed-input regression evidence"), the freeze record's status line, and the
implementation review's REJECT verdict. **Per P12, the goal must not be closed.**

Publishing this review satisfies the first half of P12's gate text (publication of the
programme review, accepted revisions, evidence gaps, and next scheduled mechanisms). The
gate remains unchecked: its closure is conditioned on criteria that do not hold, and this
review — per plan:186-190 — carries the naming violations forward as remaining work and
claims no complete runtime naming conformance.
