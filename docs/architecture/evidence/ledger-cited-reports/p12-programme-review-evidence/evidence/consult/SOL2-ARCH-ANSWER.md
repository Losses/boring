**SOL2 architectural judgement**

**Decision: keep the ordinary Swift array boundary as the selected mechanism, reject the current candidate for acceptance, and fund baseline restoration separately while preserving P09’s full meaning.** The immediate compiler obligation is to carry the actual destination, including intermediate destinations, through lowering. The blocked fixture already has an approved contractual solution.

This consultation is dated 2026-09-30, against Boring HEAD e1c6597514634fd347d392709793cc19bd96c9a2 and its existing working changes. I read the five requested reports in order, then the repository authorities, relevant specifications, compiler paths, fixtures and CI entry points. I ran no builds or tests. Historical execution results below come from the retained reports; source findings were checked directly. The work plan confirms P11 complete and P08, P09, P10 and P12 open. Your update that a P08 board row now exists supersedes the landing list’s earlier absence finding.

**1. Is the P08 candidate well chosen?**

**The mechanism is well chosen. The present candidate is incomplete. Record the blocked case’s disposition before further implementation.**

The fixture’s source is “values == null ? [] : values”, bound to a required ReadOnlyArray and passed to a typed consumer. It requires a present result because the empty fallback supplies one. It does not require an arbitrary nullable operand to become a required value without extraction or fallback.

The approved J design expressly says that an optional nil-merge operand must not be forced through a required conversion before presence is established. J2 specifies an optional intermediate destination followed by the required fallback join. The policy interfaces state the same rule. Consequently, this is principally **implementation nonconformance with an existing decision**, rather than an unresolved language ruling. [Approved composition rule](/home/losses/Development/tq-workspace/boring-wt-architecture/docs/investigations/architecture-round-1/j-prepared-value-design.md:135), [intermediate destination requirement](/home/losses/Development/tq-workspace/boring-wt-architecture/docs/compiler-policy-interfaces.md:169).

My disposition is precise:

- Keep the planner’s refusal of an unproved, still-optional operand against a required destination.
- Require this accepted source composition to succeed: convert the nullable payload against an optional intermediate requirement, materialize the empty fallback in the selected container representation, then establish the required joined result.
- Where lowering uses an ordinary conditional instead, establish valid branch facts and preserve branch evaluation.
- Preserve shared alias visibility, lifetime and single evaluation throughout.

The current nil-merge lowering passes the final requirement to both operands. That explains why it requests the refused cell. Filling the empty planner case indiscriminately would conceal the incorrect request and introduce an unsound conversion. [Current lowering](/home/losses/Development/tq-workspace/boring-wt-architecture/packages/compiler/reflaxe/swift/swiftcompiler/SwiftExpr.hx:2623).

I therefore differ from the behaviour review’s suggestion that this cell has no governing ruling. Its reproduction is useful; its interpretation overlooks the approved intermediate-requirement rule. I also reject the landing list’s “oracle gap, small” assessment. There is a substantial contract-to-implementation gap, compounded by missing test collection.

Keep the approved eleven producer families as the completion domain, using their valid routes and composition guarantees rather than an indiscriminate Cartesian product. J1/J2 checkpoints may retain explicitly unaccepted J3 work. Such checkpoints cannot stand for acceptance of the complete boundary mechanism. [Phase limits](/home/losses/Development/tq-workspace/boring-wt-architecture/docs/investigations/architecture-round-1/j-prepared-value-design.md:193).

**2. What is the correct order?**

**Choose d → a → b → c.**

1. **Baseline budget decision.** Commit capacity to baseline restoration and retain the current P09 contract. Decide this immediately; do not wait for restoration to finish before progressing P08.
2. **Disposition of the refused cell.** Apply the existing ruling above. Fix the required domain, intermediate requirements and behavioural expectations before implementation. Review the reproduction and test specification at this point, as P08 requires.
3. **Complete the consumption repair.** Establish the necessary prepared-value and destination interfaces, then repair switch/try composition using them. This follows J1/J2 dependencies before J3. Adding planner calls while continuing to supply the enclosing function’s return type would preserve the defect.
4. **Freeze the complete candidate and obtain both independent reviews.** Behaviour and implementation reviewers judge the same compiler, fixtures, required inventory, harness and evidence identities. Every subsequent relevant change invalidates the affected acceptance.

Budget commitment comes first because it determines whether this delivery has a funded route to P09. The cell disposition precedes implementation because it determines which request is legitimate. Implementation precedes final candidate review because reviewers need a completed, stable object.

This order separates **deciding to restore the baseline** from **achieving a green baseline**. Focused P08 acceptance can precede the latter. P09 then verifies the combined candidate on fixed Boring/Tiqian inputs. Relevant focused evidence may be reused only when its consumed inputs still match; boundary-affecting integration changes require renewed review. The plan explicitly places focused acceptance before final verification. [Gate dependencies](/home/losses/Development/tq-workspace/boring-wt-architecture/docs/architecture-work-plan.md:228).

**3. What baseline decision would I make?**

**Fund restoration; keep full P09 acceptance. Make P08 the nearer delivery milestone.**

The programme already has a legitimate bounded milestone. Weakening P09 to obtain another local milestone would spend the meaning of the existing integration gate unnecessarily. The governing rule explicitly makes baseline failures binding. [Acceptance rule](/home/losses/Development/tq-workspace/boring-wt-architecture/docs/architecture-work-plan.md:415).

Allocate a separate baseline restoration assignment that integrates the validated timeout and string-expectation repairs, establishes trustworthy execution inputs, resolves the remaining required failures and f32 comparison defects, and obtains the pinned Tiqian evidence. Each repair still requires review appropriate to its claim. Increasing a timeout improves observation; changing an expectation requires an independent specification justification.

Do not add the scratch improvements together to predict a combined result. They used different input states. Obtain one fresh combined measurement at the integration checkpoint. The remaining assertions, seven reported suite errors, warning failures and previously unreached stages still require accounting.

There is also a state distinction in your “three places” description: the original Swift compile error and the 166 divergences are successive Stage-3 observations on different inputs. The double-wrap repair is present in the inspected working file; its retained run reaches comparison and fails there. Budget the integrated candidate’s actual residual defects, preserving the earlier failure as historical evidence. [Swift repair results](/home/losses/Development/tq-workspace/dc-warn/out/swift-arrayboundary-fix/REPORT.md).

**Restoring the test stub in try/finally is insufficient for acceptance integrity.** The helper temporarily replaces assertion-bearing tracked source while the compiler runs. Successful restoration cannot establish that generation consumed authoritative source, and cleanup cannot protect every process interruption or concurrent reader. Fund removal of that substitution from the acceptance procedure, with isolated execution inputs and the relevant emitter correction where required. [Mutating helper](/home/losses/Development/tq-workspace/boring-wt-architecture/tests/ts/package-artifacts.test.ts:58).

I cannot responsibly price complete restoration from the supplied counts. Before committing a completion date or a fixed total budget, the owner needs:

- **A combined residual baseline:** exact candidate inputs, remaining failure identities, suite errors, warnings and unreached obligations after the validated repairs.
- **A bounded account of the 166 divergences:** comparison groups and test membership, applicable numeric rulings, representative source witnesses and raw values, grouping by cause, and a repair estimate per cause. Attribution alone cannot pass a required consistency check.
- **A feasible Tiqian execution route:** the current checkout at 8504d230228e8206689a2049bbb84b671c1f079a, its boring.json and recursively included HXML files, actual candidate compiler routing, required local data, toolchain and authorization. The preparation runbook is the starting file; preparation is not execution evidence.
- **A finite expanded-programme completion inventory:** which migrations remain required for P12, distinct from optional findings and future work.

These are specific planning inputs, not a reason to commission another general audit. Use one integration checkpoint and one bounded divergence/consumer feasibility determination. If restoration cannot be funded, stop promising full programme closure after P08 and leave P09–P12 open. A narrower programme would require an explicit owner revision of its authorities.

**4. Are “two axes” sufficient?**

**No. Generation exit zero and empty swiftc diagnostics are necessary observations, but they cannot certify the mechanism.**

They distinguish two observed failure modes. They do not establish that the operands and destination supplied to the planner were authoritative. They also cannot distinguish a correct shared view from a type-correct copy, detect every reordered effect, or prove that a return reaches its intended destination.

The refused-cell reproduction is an additional counterexample within the existing composition contract. Counting it as a third independent axis adds little. Both it and switch/try demonstrate that the enclosing use’s requirement is missing or misapplied.

The destination needs explicit ownership:

- Declaration selection owns the stable requirement for a binding or field.
- Callable signature selection owns argument and return requirements.
- The enclosing composition owns intermediate requirements and result intent: yield, bind, assign, return or discard.
- Boundary selection consumes those requirements together with the selected operation’s actual produced facts.

A small explicit interface is sufficient. A universal target IR is unnecessary.

I also qualify “no producer at all” and “six producers proves the one-producer rule false.” Callers do compute destination Types today; what is missing is an enforced account of which requirement applies at each handoff. Multiple operations may legitimately establish storage or presence for different occurrences. The requirement is **one authoritative account of each fact at its occurrence**, rather than one constructor function for an entire fact kind. Stable binding storage remaining unchanged on assignment is itself required by J; stale per-use presence would be a different defect.

Accept P08 against three obligations:

| Obligation | Evidence that can reject the candidate |
| --- | --- |
| Correct fact and requirement handoffs | Implementation review covers the approved families, actual destinations, intermediate requirements, valid presence and retained facts; in-scope reconstruction is removed. |
| Legal generated output | Both focused fixtures generate successfully; native compilation succeeds with zero diagnostics on those same candidate inputs. |
| Preserved source behaviour | Typed downstream uses and execution distinguish both branches, null/default outcomes, shared alias mutation, retained lifetime, single evaluation, lazy effects and control exits. |

For the switch assignment discriminator, vary the enclosing function’s unrelated return type while keeping the local destination fixed. For the refused composition, test both absent and present inputs and the planner’s legitimate refusal of an unproved direct optional-to-required request. For control-flow repairs, observe the actual returned result and effects, beyond warning counts.

Require durable collection as part of this candidate’s delivery: the focused tests must enter a routine repository command and CI, with their expected membership demonstrated. Today the existing harness aborts before native checks, CI omits its collecting command, and the gap fixture has no repository collector. A passing scratch run would leave that protection absent. [Focused harness](/home/losses/Development/tq-workspace/boring-wt-architecture/tests/swift-readonly-boundary/readonly-boundary.test.ts:57), [CI commands](/home/losses/Development/tq-workspace/boring-wt-architecture/.github/workflows/ci.yml:35).

I therefore reject the behaviour review’s sentence that the class closes when O-A and O-B are green. Both must be green, and both independent reviews must accept the complete contractual and behavioural obligations on the same candidate.

**5. What is the single most important thing you still have not understood?**

**Completion has to constrain what you authorize next.**

You understand the criticisms well enough to repeat them. The unresolved operational decision is to make one fixed acceptance contract govern assignments, capacity and closure. Finding another defect must return work to that unit’s owner. It must not automatically create another independent initiative, shrink the denominator or trigger another general consultation.

This particular case illustrates the problem clearly: an accepted rule already explains why the planner’s request is wrong. More review cannot supply the missing intermediate destination. Someone must own completing that handoff, and you must withhold acceptance until it is complete.

The five failed attempts to reach another model are evidence that review procurement has consumed the programme’s attention. They do not establish that the architectural question requires that model. Stop retrying that route. Assign an available independent reviewer under the existing review rules; if none is available, record a capacity blocker. Preserve the two-review requirement while continuing useful work on the fixed unit. Record setup failure as setup failure.

**6. What should be explicitly abandoned?**

Cancel the following categories as execution tasks in this delivery tranche. Preserve their findings and evidence without maintaining an active row for every observation.

| Category to cancel | Disposition |
| --- | --- |
| Further general consultations, repeated RECORD rewrites and audit-of-audit tasks | Retain one authoritative contract and review the actual frozen candidate. Correct an owning rule only when a substantive gap is demonstrated. |
| Further attempts to obtain the same unavailable review provider | Use available independent capacity; do not spend a sixth round on the route. |
| Duplicate runner-identity, provenance, loader and sealing initiatives | Replace overlapping rows with one acceptance-critical execution-integrity delivery. Preserve required checks and useful completed controls. |
| Speculative guard hardening and infrastructure extensions without a demonstrated acceptance dependency | Cancel this tranche’s roots-guard defeat campaign and rejected F3 approach. Retain only corrections needed for trustworthy candidate execution. |
| Repository hygiene and artifact housekeeping | Cancel duplicate-HXML cleanup, worktree tidying and attempt pruning as gate prerequisites. Preserve evidence required for acceptance. |
| Unrelated observational probes and broad new migrations | Cancel current assignments for additional string-unit, loop, filesystem, comparison, naming or cross-target expansion work unless a required regression or the selected handoff depends on them. Retain a compact future-work inventory. |

Keep the Swift boundary delivery, its two reviews and durable tests, baseline restoration, required consumer verification, and P10’s final reflection. P11 needs no repeat merely to demonstrate more activity.

Cancellation of tasks cannot silently remove binding obligations. The expanded policy architecture remains authoritative: the owner must explicitly settle its finite completion scope before P12 can close. Known required defects remain recorded until repaired or legitimately rescheduled under a revised programme scope. Seventy-plus open rows across several milestones are not seventy-plus prerequisites for this candidate. [Expanded completion criteria](/home/losses/Development/tq-workspace/boring-wt-architecture/docs/compiler-policy-architecture.md:151).

**Limits of this judgement.** I verified the relevant compiler paths and their agreement with the behaviour review’s source hashes. I did not independently execute its witnesses, measure a combined repaired baseline, establish current Tiqian availability or inspect a newer f32 investigation result. Those require the specific evidence identified above. This report grants no gate acceptance and changes no repository authority.

