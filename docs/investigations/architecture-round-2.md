# Architecture round 2: Policy contracts and parallel migration

## Fixed input and assignments

The owner requested parallel architecture work after preserving the unfinished
Swift implementation. The input checkpoint is
`e5e218543ef12bebe97c7cbe9bb63ef1d9ea8e6e` on
`arch/agent-guided-governance`. It is published with explicit TODOs and no claim
of implementation acceptance. The
[policy architecture](../compiler-policy-architecture.md) defines responsibilities.

| Package | Executor route | Current delivery |
| --- | --- | --- |
| A: Value and declaration representation | Claude Code, BigModel GLM 5.3 Flash | Five-target owners, typed interfaces, adapters, removal list, first implementation batch |
| B: Flow and evaluation | Goose, local Qwen | Fact scope and invalidation, effects, joins, sequencing, consumer query contracts |
| C: Identity and writable places | Claude Code, BigModel GLM 5.3 Flash | Source identity authority, sharing policy, place paths, representation dependencies |
| F: Diagnostics and evidence | Goose, local Qwen | Occurrence and decision evidence, output mapping, child capture, layered acceptance |

Each route has two authorized concurrent workers. Current assignments inspect
source and propose concrete interfaces; compiler writes have not been assigned.
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
