# Architecture round 2: Policy contracts and parallel migration

## Fixed input and assignments

The owner requested parallel architecture work after preserving the unfinished
Swift implementation. The input checkpoint is
`e5e218543ef12bebe97c7cbe9bb63ef1d9ea8e6e` on
`arch/agent-guided-governance`. It is published with explicit TODOs and no claim
of implementation acceptance. The
[policy architecture](../compiler-policy-architecture.md) defines responsibilities.

| Package | Initial executor route | Requested delivery |
| --- | --- | --- |
| A: Value and declaration representation | Claude Code, BigModel GLM 5.3 Flash | Five-target owners, typed interfaces, adapters, removal list, first implementation batch |
| B: Flow and evaluation | Goose, local Qwen | Fact scope and invalidation, effects, joins, sequencing, consumer query contracts |
| C: Identity and writable places | Claude Code, BigModel GLM 5.3 Flash | Source identity authority, sharing policy, place paths, representation dependencies |
| F: Diagnostics and evidence | Goose, local Qwen | Occurrence and decision evidence, output mapping, child capture, layered acceptance |

Each route has two authorized concurrent workers. The initial assignments inspected
source and proposed concrete interfaces before compiler writes were assigned.
The coordinator accepts shared interfaces before issuing exact file ownership.
Cross-review pairs workers from different platforms. Packages D and E follow
their dependencies and remain in the programme.

## Historical extraction evidence

The coordinator inspected the actual diffs below, together with their current
owners. The observations are static architectural evidence; no runtime failure
was reproduced in this review.

| Revision | Change and current result | Consequence for policy design |
| --- | --- | --- |
| `3cbb20c7632d7b9b7f4ea7b71f0d932c230ee839`, 2026-09-05 | Adds shared literal tests and `ExpressionPredicates.isVarAssigned`, which scans syntactic local writes. | A useful shared syntactic query has a bounded guarantee. It does not supply a program-point non-null proof, dominance, alias invalidation, or effect analysis. Package B must name the additional fact owners. |
| `5db75f321e75489ae09bbcf5675638ffe9532ddb`, 2026-09-06 | Adds `asciiFoldCallText` to `ExpressionPredicates`, accepting rendered receiver text and producing a target call string. | The shared module now combines analysis with text construction. Record the placement violation and assign operation selection and target construction to their respective owners. Moving this helper alone cannot satisfy the broader policy migration. |
| `5d53294258acf5537646c7e4e289e30ea0fadd48`, 2026-09-06 | Adds `AssignTargetPlan.assignTarget`, dispatching AST forms through rendering callbacks that return strings. | Shared dispatch removes repeated syntax matching. Its interface still carries no proof that the rendered path denotes the original writable location. Package C must establish that contract before treating assignment planning as complete. |
| `e0aa16a5`, `f1609ccf`, 2026-09-27 upstream history | Adds and refines checks for conversion fragments in rendered assignment paths. | These later repairs identify the need for place identity through projections and reader operations. They provide cases for the explicit place model and its tests. They are not integrated into the fixed checkpoint by this review. |

The useful distinction is between sharing a dispatch algorithm and establishing
the semantics of the decision it selects. A policy delivery needs both the
appropriate algorithm and authoritative input/output facts. File extraction
or a reduced branch count alone cannot establish that agreement.

## Review questions

For each worker proposal, the coordinator checks:

- Which producer establishes each input, and which existing consumer will use
  the result? Unused result records do not complete a migration.
- Which facts remain stable across writes, which depend on a flow point, and
  which describe one selected target operation?
- Which old decision disappears from each migrated path? A new policy and an
  independent fallback predictor create competing semantic authorities.
- What source behavior is already ruled, and what needs a new decision?
  A target storage choice or implementation comment alone cannot settle source
  alias behavior.
- Which observations can reject the proposed abstraction, including renamed
  declarations, intermediate typed consumers, effects, and writable paths?

Remote master was observed at
`cc9957dd7f624f4deced5e722d2a57b45e0c2d36` during assignment. Later observations
will record a new revision and the inspected delta without changing the task
baseline implicitly. Pending migration items remain outstanding work; assigning
them to a later batch does not establish their completion.

## First package A review

The first Claude Code report supplied concrete source locations and a proposed
interface. The coordinator rejected it for implementation and requested a
bounded revision. The original report and corrective brief are retained as
`claude-a-report.md` and `claude-a-revision.md` with the round's external evidence.

| Finding | Review decision |
| --- | --- |
| Source-classified `ContainerFacts` was reused as a prepared value's produced representation, with target storage derived from those facts. | Separate source classification, actual selected target operation/storage, and destination requirements. A new record cannot certify a fact that its producer does not establish. |
| The conversion table proposed null preservation and contextual empty materialization without distinct corresponding inputs. | Make the finite input states sufficient to select every operation. Missing distinctions cannot be recovered from emitted text. |
| Presence was proposed as `at(expression)` returning a proof-kind enum. | Require the relevant flow environment, read occurrence, and dependency/invalidation context. An expression alone cannot establish that an earlier proof remains valid. |
| Native default placement was described as making body storage required. | Retain signature, default placement, normalization, and actual body optionality separately. Existing Swift parameter planning already documents this requirement. |
| Helper branch differences were treated as source rejection, and zero warnings were attributed to an unmeasured baseline. | Trace actual callers and accepted source before claiming a domain difference. Record warning observations from real runs. Static inspection cannot supply either execution result. |
| Missing Dart-specific decode recipe text was treated as absence of the ordinary read-only contract. | Apply feature 18's explicit all-target ordinary conversion rule. Keep decode protection and ordinary alias visibility separate. |

The brief had already required explicit produced facts, stable declarations,
flow ownership, and evidence limits. These failures are primarily deviations
from supplied guidance. The revision request uses concrete counterexamples and
required interface distinctions. A general instruction to add policies would
not correct them. The coordinator will reassess the revised interface before
assigning implementation or requesting new owner rulings.

## First package C review

The first identity/place proposal identified concrete assignment and sharing
owners but did not preserve the necessary distinctions in its proposed types.
The coordinator requested a report revision before any compiler writes:

- The proposal marked ordinary class identity unresolved, then assigned shared
  identity to every class. It also generalized a Rust record rule to all targets.
  The revised facts must preserve the scope and authority of each rule.
- The proposed place roots omitted effectful receivers such as `f().arr[i()]`,
  although the proposed test matrix included them. Interface review must account
  for each accepted form before an implementation can satisfy that matrix.
- A read-only view was called a writable place because it shares storage.
  Identity, access permission, and lifetime require separate facts.
- A generic temporary-store fallback could discard a write to the original
  location. The plan must establish storage relationships and any required
  writeback; source acceptance cannot be reduced to fit the proposed enum.
- Compound-write and target lock planning must preserve receiver/index/read/RHS
  ordering and exceptions. Target lock constraints do not authorize moving
  observable source effects.

The revision brief supplies concrete interface counterexamples and asks for
a first place-policy batch that can proceed independently of unresolved class
identity semantics. Its dependency is the reviewed representation/evaluation
interface, with assigned backend ownership. The unfinished Swift pilot remains
a migration task and does not prevent this design work.

## Earlier intermediate review and execution assignments

The coordinator published the reviewed
[policy interface contracts](../compiler-policy-contracts.md) while the workers
continued bounded observations. The three execution worktrees use `e45c74b7`
as their checkout base; later guidance commits do not change their compiler
input implicitly. No new compiler migration is accepted at this stage.

| Worker | Responsibility at that review | Acceptance state at that review |
| --- | --- | --- |
| Claude Code, GLM, first worker | Implement the bundle driver's child evidence capture, with focused tests. | Candidate implementation and tests exist; review and verification remain open. |
| Claude Code, GLM, second worker | Reproduce paired Haxe JS and Rust place observations with a durable runner. | Manual outcomes are retained with evidence gaps; the replay runner requires correction. |
| Goose, Qwen, first worker | Compare concrete Kotlin and Rust condition producers, callers, and other fact-store writers. | Revised design distinctions are retained; whole-function equivalence is rejected. |
| Goose, Qwen, second worker | Review and repair the classifier observation fixture delivered by GLM. | Snapshot review is recorded; repaired fixture execution and acceptance remain open. |

The review exposed the following distinctions. The contracts and analysis
method own the resulting rules; this table records why they were needed.

| Observed review problem | General distinction and response |
| --- | --- |
| B's revised proposal preserved a sibling field fact because its full access path differed. | Access identity and alias independence differ. Require dependency evidence before preserving facts after a possibly aliasing write. |
| B proposed one equivalent condition table for Kotlin and Rust before comparing their rules and callers. | Sharing overlapping syntax recognition does not establish identical branch facts or target permissions. The next task compares bounded producers and their consumers. |
| C's replay runner reused native output paths across variants and gated execution by file existence. | An artifact's presence does not establish that its producer succeeded for this attempt. Require per-variant outputs and explicit status-dependent execution. |
| C's stage list was populated by the same function that recorded completed stages. | A completion check needs an independent expected case set; it cannot detect work omitted by its own traversal. |
| A's reviewer treated caught helper exceptions as preserved failed run attempts. | An exception within one probe and a failed process attempt have different identities. Review both independently. |
| Several diagnostic runners replaced fixed output files on retries. | A successful later attempt cannot reconstruct an earlier failure. Preserve the gap and obtain fresh evidence with exclusive run allocation. |

The original briefs already required separate streams, attempt retention,
stage identity, and actual consumer integration. Repeating those requirements
alone did not prevent these failures. The next execution tasks name the exact
counterexample and require the durable runner itself to execute before its
results support acceptance. The coordinator also stops report-format revisions
that add no evidence and assigns bounded caller comparisons when a general
design report leaves an implementation assumption unresolved.

An observation fixture establishes only its recorded phase. A macro that reads
types and exits early does not establish normal compilation. A paired native
result requires matching authored input, case defines, successful compilation,
and the resulting artifact. These checks improve diagnosis; they do not replace
the later Boring matrix or the required fixed-revision Tiqian regression.

The next compiler batch is the
[canonical source-container foundation](architecture-round-2/a-source-container-facts.md).
Its worktree is pinned independently while the observation runners finish
review. The brief specifies source identity, alias and outer-null distinctions,
the initial adapters, and the remaining comparator consumer migration.

## Observation handover

The [A and C observation acceptance](architecture-round-2/observation-acceptance.md)
records the accepted diagnostic fixtures, concrete paired outcomes, and retained
evidence gaps. The second GLM worker has handed over C and started the A2
source-container implementation in its separately pinned checkout. F1 remains
in revision and independent snapshot review.

The next consumer design is
[A3 comparator planning](architecture-round-2/a-comparator-migration.md).
It separates source field analysis, sorted-key admission, target comparison
planning and declaration dependencies, with a removal inventory for all five
targets. The independent caller audit precedes exact implementation ownership.


## Earlier execution and consumer preparation

Two GLM workers now own A2 source-container implementation and F1 child evidence
capture. One Goose worker audits the five-target comparator consumers for A3;
the other reviews a frozen F1 snapshot independently. A3 implementation waits
for its input contract and consumer audit. Each changing implementation has one
writer. Earlier assignment tables retain their historical review state.

The coordinator recreated a locked Tiqian checkout at `8504d230` after finding
that the earlier validation checkout was absent. The existing setup script
copied 248 local data files; source hashes before and after the copy agree,
and every target hash matches. The setup evidence is retained in the round's
external evidence under `tiqian-setup-qu2v5_9t`. The original checkout's tracked
files were not modified. The copied data's producing engine revision is unknown.

The derived configurations from tasks P and W need reconstruction in the new
checkout. Preserve their full generation and test obligations, compiler-path
checks, separate engine and protocol comparisons, and common protocol test
roots. Those earlier preparations were static inputs; a reconstructed mapping
requires its own checks before generation or native execution can establish
regression evidence. The coordinator has not launched the full Tiqian matrix.

## Current execution after F1 integration

F1 is integrated at `8a2a9c6a`; its
[delivery review](architecture-round-2/f-child-evidence-review.md) records the
focused integration checks. Source maps and compiler decision provenance remain
package F work. The coordinator accepted the reconstructed
[Tiqian preparation inputs](architecture-round-2/tiqian-preparation-review.md)
for later fixed-candidate verification; no Tiqian regression pass is claimed.

A2 source analysis has a reviewed implementation and focused evidence from Luna.
Its all-target verification remains under review. After the GLM native-tool
handover, Luna owns the remaining runner corrections, with compiler and authored
source files frozen. A second GLM worker now owns baseline comparison fixtures
in a separate checkout at `8a2a9c6a`, covering integer, read-only collection,
nullable collection and UTF-16 string ordering in all five targets.

Goose reviews shared verification responsibilities against the actual runners.
Repeated omissions in status, stream and input-identity recording motivate that
review. It must identify a bounded common implementation and concrete consumers
before another infrastructure change is assigned. No compiler writer has yet
been assigned the broader A3 comparison-plan migration.

The coordinator's [B1 flow consumer review](architecture-round-2/b-flow-consumer-boundary.md)
identifies Kotlin's source-position evidence and its declaration/body consumers.
It defines a bounded next observation batch. No runtime defect or package B
compiler migration is accepted by that static review.

The coordinator has reviewed the [A2 source-container delivery](architecture-round-2/a-source-container-review.md)
and copied its source foundation and focused fixtures for integration checks.
The review records three passing native targets, two retained native failures,
and the distinct baseline and candidate alias diagnostics. Luna has handed over
A2 and now owns the separate Swift ordinary-runtime dependency correction.

## Review of investigation boundaries

A2 was committed at `f104e3bf` after the coordinator's integration run. The
bounded source foundation is accepted with the limits in its delivery review;
the remaining comparison, representation, and full-consumer work stays open.

The enum comparison fixture at `8a2a9c6a` records a conflict within standard
library specification 16: tag-only comparison returns zero for records holding
`Value(1)` and `Value(2)`, while their `RecordEq.eq` result is false in both
TypeScript and Rust. The recorded map retains one slot after both insertions.
The source ruling remains pending. Direct payload-enum key rejection is a
separate domain observation and does not by itself rule admission of fields
inside record keys.

The coordinator requested corrections to the investigation before acceptance.
The report cited a parameterless-enum amendment as authority for payload enum
equality, and claimed complete attempt retention despite preliminary commands
that reused output paths and truncated combined streams. Its corrected report
must retain the measured divergence, state the unresolved equality domain, and
disclose the capture limits. Historical output remains unchanged.

Two runner reviews also exposed path-depth assumptions. The A3 comparison
runner resolved its root to the checkout's `tests/` directory and then searched
for its failed attempts under the repository root. The coordinator found four
retained attempts at the actual output path and assigned a root-path correction.
The shared membership extraction copied one helper path into callers at
different directory depths; those callers require their own resolved paths.
The analysis method now requires explicit rule-domain and runner-path checks.
These checks address the observed mistakes; their inclusion does not establish
acceptance of the pending fixtures or shared helper delivery.

The coordinator subsequently reviewed and integrated the
[F2 stage membership delivery](architecture-round-2/f-stage-membership-review.md).
Two existing fixtures now consume one implementation and retain their existing
native failures. The report records the focused checks and the limits of this
shared responsibility. B1 flow observation is assigned to GLM in an independent
checkout at `41d67cad`; its child commands use the existing F1 capture caller.
