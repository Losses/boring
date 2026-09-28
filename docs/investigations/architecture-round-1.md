# Architecture investigation, round 1

## Baseline and ownership

The owner requested an independent worktree on 2026-09-27. This programme uses
branch `arch/agent-guided-governance` in `boring-wt-architecture`. Its compiler
baseline is `e3b8bab39ac2da0e17e9d04e031f03bd39290274`. This was the remote
`master` head when queried through the GitHub API during baseline selection.
The branch remains based on that commit while other work continues upstream.
Any later baseline change requires an explicit decision and fresh evidence.

The original `boring` worktree belongs to another active task. This programme
does not edit, update, reset, or commit through that worktree. Shared Git object
storage supplies history; source changes and generated outputs belong to the
independent worktree or to separately assigned execution workspaces.

The initial guidance was carried from documentation commit `a432e0d5`, which
adds the work plan on top of analysis-method commit `864c318e`. The carried
changes are Markdown only: `AGENT.md`, the analysis method, the work plan, and
their specification links. Unrelated driver changes from the earlier workspace
are excluded from this baseline.

## Consumer version evidence

The Tiqian remote head was `8504d230228e8206689a2049bbb84b671c1f079a` when
queried. Its `flake.lock` pins Boring
`304ed70c4ba09fe21edadcca4c85f963fd692927`. The inspected local Tiqian worktree
was at `80445d9198b23017bf8c9e32e0eeb0586c0fdc04` with unrelated local changes.
Its `.haxelib/boring/git/.boring-flake-revision` recorded that same Boring pin.
The source exports used for investigation contain the remote commits, excluding
local changes. No Tiqian build has been run for this programme.

The selected Boring baseline includes a warning-fix merge with changes to
TypeScript, Kotlin, Swift, Dart, and shared helpers. Earlier observations from
`378dfdbf` are investigation leads. Each report must establish whether a
finding still exists in the selected baseline.

## Assignments and evidence locations

Three native Luna agents received separate read-only assignments:

| Task | Responsibility | Required report |
| --- | --- | --- |
| A | Compare recurring mechanisms across the five targets and select candidate contracts | Mechanism matrix, evidence, priorities, and guidance findings |
| B | Inspect Boring and Tiqian verification entry points and artifact identity | Required checks, change-to-test matrix, cost evidence, and execution procedure |
| C | Exercise the guidance on two cases and inspect upstream compiler contracts | Reasoning records, pinned primary references, and document revisions |

The runtime evidence directory for this session is
`/tmp/boring-architecture-round1`. Its `boring/` and `tiqian/` directories are
Git archive exports of the selected remote commits. `briefs/` preserves the
initial task instructions, `reports/` receives the investigations, and
`recent-commits.txt` records the Boring history supplied to investigators.
Accepted conclusions and their revision-specific citations will be retained
in this repository; temporary paths alone are insufficient final evidence.
Repository copies of the revision 1 briefs are preserved here; B and C include
editorial wording corrections identified by the documentation checker:
[common context](architecture-round-1/common.md),
[A](architecture-round-1/a.md), [B](architecture-round-1/b.md), and
[C](architecture-round-1/c.md).

Task B was initially prepared for Claude Code with Read, Grep, and Glob tools.
Automatic approval review rejected that call because its configured custom
model service destination had not been verified for source transfer. No source
investigation was started through that channel. The coordinator assigned B to
native Luna and explicitly allowed read-only shell searches and one report
file. The investigation scope and acceptance requirements stayed the same.

## Current status and remaining evidence

The independent baseline and three investigation assignments are established.
Reports are pending review. The independent worktree's `nix develop`
environment reported Haxe 4.3.7, Bun 1.3.13, rustc 1.98.0, kotlinc-jvm 2.4.10
with JRE 21.0.12, Dart 3.13.0, and Swift 6.2.4 on Linux x86_64. The probe used
each tool's version command and retained output in `toolchains.log`; it did
not compile either project. Documentation checks are recorded when complete.
No compiler implementation,
runtime defect reproduction, or platform regression result is claimed here.

The full documentation scan found 13 existing source-comment hits in the
selected baseline and four hits in the newly retained brief transcriptions.
The coordinator corrected the four documentation hits. The source-comment
baseline remains separate work for an execution agent. Earlier style results
from the original Boring worktree apply to a different compiler baseline.

Before implementation begins, the coordinator must accept the responsibility
map, identify a mechanism's governing contracts, and write the implementation
brief. Before Tiqian verification, the assigned executor must establish an
isolated consumer workspace and prove which Boring revision its actual
generation command uses.

## First report review

Report A revision 1 identified repeated Swift array conversions and Dart
queries that render expressions while saving and restoring promotion state.
The coordinator confirmed those locations at `SwiftExpr.hx:3185` and
`DartExpr.hx:4777` in their respective target compiler directories.

The report also attributed an independent Swift array snapshot requirement to
feature 18. Review found that `docs/specs/features/18-immutability.md:211`
states Haxe, TypeScript, Kotlin, and Rust rulings and contains no Swift ruling.
`SwiftDecl.hx:1063` comments on the implementation's value-array choice;
that comment does not supply the missing normative requirement.

The coordinator returned A for revision, requesting exact normative citations,
separate implementation observations and inferences, and a complete five-target
comparison for the proposed conversion contract. The original report remains
in the session evidence directory as `reports/a.md`; the revision is requested
as `reports/a-v2.md`.

This failure shows both an incorrect report claim and a guidance opportunity.
The original brief required governing contracts, but did not require checking
whether the cited specification actually covered the named target. The analysis
method now includes that requirement explicitly. Report A revision 2 tests the
immediate correction; a later task must test whether the instruction generalizes
to a different contract without coordinator prompting.

Report B revision 1 correctly distinguished the consumer pin and the current
compiler baseline, and identified discarded successful compiler output in
`tools/bundle/Driver.hx:517`. Its proposed sequence repeated the complete
target matrix through two commands and ended with Tiqian's old compiler pin.
The coordinator requested a single final required run, focused early checks,
and a concrete way to prove that Tiqian uses the candidate compiler. Review
also requested a check of generator cleanup before treating retained output
as an established defect.

Report C revision 1 substituted Boring's own Kotlin and Rust targets for the
requested independent Reflaxe implementations. It disclosed the missing
external commit IDs but incorrectly described the substituted comparison as
meeting the task. The coordinator requested concrete official Haxe backend
contracts and two independent Reflaxe implementations with immutable source
references. The plan now states how partial evidence affects task completion.

## Accepted static findings from revision 2

The coordinator accepted A revision 2 as a bounded conversion investigation.
The general responsibility survey remains assigned separately as task F.
The conversion evidence separates source access restrictions, target storage,
conversion timing, and alias behavior:

| Target | Inspected representation | Boundary consequence |
| --- | --- | --- |
| TypeScript | `TsType.hx:39` uses a readonly array type | A type qualifier alone does not establish runtime freezing or copying. |
| Kotlin | `KotlinType.hx:44` uses `List`; mutable arrays use `MutableList` | Interface compatibility and the decode view path need separate analysis. |
| Rust | `RustType.hx:130` distinguishes parameter slices from owned vectors | Representation depends on the value's use position and borrowing requirements. |
| Dart | `DartType.hx:45` and `:58` both use `List` | Source mutation restrictions do not imply an additional runtime container. |
| Swift | `SwiftType.hx:77` uses a native array; `:91` uses `TiqianArray` for mutable arrays | Calls, returns, assignments, and other positions require explicit conversion decisions. |

These paths are under `packages/compiler/reflaxe/<target>/<target>compiler/`
at the pinned baseline. They establish implementation choices. Feature 18's
general read-only principle applies to the accepted source; its specific
target recipes do not resolve retained mutable aliases or Swift conversion
timing. Task [D](architecture-round-1/d-observation.md) collects observations
before any semantic change is selected.

The coordinator also checked the revision identities and representative
producer/consumer functions in C revision 2. The following upstream contracts
are relevant architectural references:

| Source | Inspected contract | Application and limit |
| --- | --- | --- |
| [Haxe default argument pass](https://github.com/HaxeFoundation/haxe/blob/e0b355c6be312c1b17382603f018cf52522ec651/src/filters/defaultArguments.ml#L45) and [C# overload generation](https://github.com/HaxeFoundation/haxe/blob/e0b355c6be312c1b17382603f018cf52522ec651/src/generators/gencs.ml#L156) | A scheduled typed-expression pass prepares nullable arguments and entry defaults; the backend separately constructs optional-argument overloads. | Separate source adaptation from target calling conventions. Kotlin can use different target syntax while retaining explicit source decisions. |
| [Reflaxe/C++ conversion entry](https://github.com/SomeRanDev/reflaxe.CPP/blob/e07ab05a32ab9d2e2717ad9bc7d1c4e18f88927b/src/cxxcompiler/subcompilers/Expressions.hx#L528) | Conversion receives both the actual expression and expected destination type before selecting memory-representation changes. | A destination-aware boundary is useful precedent. Its pointer and optional policies do not determine Boring semantics. |
| [Reflaxe Rust representation decision](https://github.com/fullofcaffeine/reflaxe.rust/blob/b4975cb3bc0039cfabf498e455cbab4e36de58de/src/reflaxe/rust/analyze/RepresentationPlan.hx#L688) and [output iterator](https://github.com/fullofcaffeine/reflaxe.rust/blob/b4975cb3bc0039cfabf498e455cbab4e36de58de/src/reflaxe/rust/RustOutputIterator.hx#L34) | The planner constructs immutable representation decisions; later code transforms target nodes and then prints them. | Explicit facts can serve several consumers. The other compiler's ownership policies and runtime requirements need independent review before reuse. |

These are source observations at immutable revisions, with no upstream build
or correctness evaluation. They support contracts between responsibilities;
they do not prescribe a whole-compiler rewrite or establish that each upstream
implementation satisfies every architectural criterion.

B revision 2 supplies a verification design with these acceptance conditions:

- Schedule focused feedback before one complete required verification run for
  a fixed candidate; expand composite commands to avoid duplicate matrices.
- In a disposable Tiqian worktree, activate its pinned environment first, then
  bind `haxelib dev boring` to the actual candidate compiler worktree. Confirm
  the effective path, revision, configuration, and driver identity in the same
  process that performs generation. The original investigation export is a
  baseline, so it cannot represent later compiler changes.
- Establish compatibility between the candidate compiler and Tiqian's pinned
  driver before starting the full consumer matrix. Source inspection alone
  does not establish that compatibility.
- Capture tool output before the driver discards successful child output, or
  add tested per-step log retention. Redirecting the outer driver is
  insufficient warning evidence.
- Preserve generated-output identity and the implementation standard's required
  equality comparisons. A particular manifest implementation is a design
  choice; the required comparison is already normative.

The execution recipes remain unexecuted proposals. Generation cleanup is also
unresolved: inspection of the driver's directory creation alone cannot prove
the behavior of Reflaxe's output writer. The next execution brief must resolve
that question or use newly created output directories with recorded ownership.

## Parallel follow-up assignments

Task D owns only `out/architecture-readonly-probe/` and its external report.
It may author and execute focused observation code. Task E owns wording-only
repairs in the six source files with the 13 baseline style hits; it may not
change executable tokens. Task F performs the remaining systemic survey and
owns only its report. The coordinator owns the documentation files. These
assignments keep simultaneous writers out of the same compiler files.

Task E completed all 13 baseline wording repairs in the assigned six files.
The coordinator reviewed the exact diff and confirmed that every changed line
is comment text. The executor also reported identical non-comment token streams
and a passing targeted style check. No compiler or runtime test was required
for those wording changes. The coordinator corrected the outdated verification
summary in `AGENT.md` after checking the actual `package.json` command.

## Responsibility map and implementation dependencies

Task F extends the conversion survey with representative paths across all five
targets. This remains a sampled architecture survey, with runtime behavior and
uninspected forms explicitly unresolved. The coordinator checked the shared
predicate implementation, the string-unit contract, and Rust argument-order
classification against the cited code.

| Mechanism | Facts that must have a defined producer | Target responsibility | Next useful evidence |
| --- | --- | --- | --- |
| Numeric conversions | Source width, configured precision, signed domain, required result type, conversion already applied | Legal primitive operations, storage, and target conversion syntax | Mixed arithmetic, branch results, arguments, and returns at the supported precisions |
| String operations | Code-unit, code-point, grapheme, or byte domain; bounds and null behavior; operand evaluation requirements | Native storage and runtime helper selection | Supplementary characters, individual surrogate code units, bounds, and effectful operands |
| Null flow | Binding identity, program point, branch facts, invalidating writes, joins, and exceptional paths | Optional storage, extraction, and target compiler promotion | Branch, loop, mutation, closure, and catch interactions |
| Evaluation | Whether an operand may be evaluated again or moved across another operation | Temporaries and target borrowing restrictions | Counters, writes, exceptions, and ordered argument observations |
| Identity and sharing | Source identity requirements, alias visibility, and boundary lifetime | References, value storage, borrowing, cloning, and container conversions | Alias mutation before and after the boundary, with an established expectation |
| Output structure | Result use, branch exits, evaluation order, and completed value decisions | Target syntax, precedence, declaration forms, and formatting | Nested non-associative operations, value branches, and early exits |

Existing shared modules cover parts of this map. `FloatPrecision.hx:16` owns
the precision configuration; `ExpressionPredicates.hx:59` scans syntactic local
writes. Neither supplies a complete value-boundary or effect model. In Rust,
`RustExpr.hx:15834` classifies order-neutral arguments before a borrowing
transformation. That predicate is one local decision with specific consumers;
it does not establish a general proof that a read can move across writes.

The coordinator also found a concrete ownership mismatch while checking F:
`ExpressionPredicates.hx:85` constructs target call text in a shared module,
although the implementation standard says shared decision modules do not emit
target text. This is a static standards finding with no reproduced failure.
It belongs in the shared-module audit; moving that helper alone would not
complete any of the mechanism changes above.

The resulting work order is:

1. Establish explicit boundary decisions and their source/target distinctions.
   Swift array conversion remains the first investigation, with task D supplying
   legality, effect, and alias observations. Resolve any semantic decision
   required by the selected change before implementing it.
2. Prepare numeric conversion and operand-evaluation contracts independently.
   Their facts also support later string and null-flow work. Parallel reading
   and test design are possible, while each backend retains one writer.
3. Apply established evaluation facts to string operations and null proofs.
   Source domains and invalidation rules must precede helper consolidation.
4. Carry branch result and exit intent into target structure after the relevant
   flow and evaluation contracts exist. Keep target precedence policies local.

The coordinator has accepted the initial responsibility map and verification
design for planning. It has not accepted an implementation, a new semantic
ruling, or a full runtime coverage claim.

## Follow-up review and environment recovery

In task D, the coordinator found an observation harness that asserted the Haxe
result as the expected result before the alias contract had been decided.
The brief already prohibited that choice. The coordinator classified it as an
execution deviation and required independent observations, without adding a
duplicate prohibition to the method. Review also required fresh output after
removing earlier harness dependencies, so retained generated files could not
silently supply the corrected experiment.

Task G observed the candidate haxelib mapping and a separately pinned driver,
then its Tiqian worktree disappeared from both the filesystem and Git worktree
list. The cause is unknown. The coordinator recreated the same branch and
revision under `architecture-workspaces/tiqian-validation`, then locked that
worktree and the Boring architecture worktree with task-ownership reasons.
Task G2 repeats identity checks and preserves raw logs outside the consumer
worktree. Earlier observations remain historical evidence. Reusing the
environment requires new availability checks.

## Boundary observations and remaining decisions

Task D generated fresh Swift output from accepted Haxe probe source under
`out/architecture-readonly-probe/`. The coordinator reran `oracle.hxml` and
the generated `clean-success-probe` executable in the pinned Nix environment.
Both routes invoke the same authored `ReadOnlyAliasSuccessProbe` operations.

| Operation | Haxe observation | Swift observation |
| --- | --- | --- |
| Convert a mutable array, then change its element and append through the original reference | Read-only access sees element 7 and length 2 | Read-only access sees element 1 and length 1 |
| Invoke a producer, convert its array, then change the original element | One producer call; read-only access sees element 8 | One producer call; read-only access sees element 1 |
| Pass a mutable array and return a read-only array | Returned length 1 | Returned length 1 |

These scalar-element observations establish an alias visibility difference.
They do not determine element-object identity or the required semantics of
ordinary read-only conversion. The coordinator submitted the minimal case
and competing policies to the owner under the implementation standard's
behavioral-divergence rule. A ruling is pending. No conformance expectation
or compiler implementation may select a policy before that ruling.

The nullability probes distinguish a separate legality problem. A plain source
assigned to an optional read-only destination compiles. An optional source
assigned to an optional read-only destination generates `Array(source)` and
fails Swift type checking. A guarded optional source assigned to a required
read-only destination generates `Array(source!)!` and fails because the final
unwrap applies to a nonoptional result. The report retains generated source
and native diagnostics. Review requested the missing emitter call paths before
accepting either as a complete diagnosis.

This experiment adds a test-design requirement: vary source nullability,
destination nullability, and established flow facts independently. State source
acceptance, generated legality, runtime observations, and semantic authority
separately. A successful non-asserting runtime host provides observation access;
it does not constitute a passing conformance test.

## Consumer preflight after recovery

Task G2 confirmed a candidate haxelib mapping after a shell-hook override in
the recreated Tiqian checkout at
`8504d230228e8206689a2049bbb84b671c1f079a`. O revision 2 subsequently found
explicit backend and sample paths still selecting the old export. The mapping
alone therefore does not establish the compiler inputs used by generation.
The driver remains the Tiqian flake's `304ed70c` package. Generation compatibility
remains untested.

The executor copied 244 local golden files and four Unicode input files using
Tiqian's setup command. Source and destination SHA-256 manifests match. Their
producing revision and freshness are unknown, so byte identity establishes
input provenance only. The Boring flake supplies Swift 6.2.4 and its linker
environment; the consumer command must retain the separately pinned driver
and repeat the compiler override after entering that shell.

Raw recovery records are retained outside the consumer checkout at
`/tmp/boring-architecture-round1/g2-evidence/`. No consumer generation, native
compilation, or regression suite was part of preflight acceptance.

## Implementation preparation review

D revision 2 supplies the missing local-initializer emitter paths. The
coordinator checked the inline conversion and subsequent unwrap at
`SwiftExpr.hx:759` through `:782`, together with guard fact propagation.
The report also corrects its evidence claim: retained logs contain command
output; exit statuses came from tool results, and generation logs were not
saved. Future verification must preserve those records together.

H provides the conversion consumer inventory used by
[implementation brief J](architecture-round-1/j-boundary-implementation.md).
The coordinator revised its proposed scope to include a focused boundary
module and `SwiftDecl` consumers. Keeping every decision inside `SwiftExpr`
or deferring static fields would leave the ownership problem partly intact.
Runtime effect checks replace operand spelling counts as the primary evidence
for evaluation count and order. The brief awaits the owner semantic ruling.

Automatic review rejected task I's focused Tiqian generation twice before
process creation. It retained the earlier preflight-only authorization limit
despite the subsequent generation assignment. The coordinator requested
explicit authorization for the bounded generation command. No generation
result or consumer regression evidence exists from those attempts.

## Independent task-brief review

Task M reviewed brief J against actual Swift paths. The coordinator confirmed
that `argTexts` prepares ordinary arguments, `callArgTexts` may render again
for defaults, and `enumConstruct` directly renders enum payloads. The latter
was absent from H's consumer inventory. It is a static coverage gap; source
acceptance and a generated failure for that family remain untested.

J now names enum payloads, preparation timing and invalidation, separate query
and runtime-effect checks, a concrete successful-output capture requirement,
and an accepted reference-element case. Existing source/target type distinctions
and query-purity rules already prohibited several related mistakes, so review
did not duplicate those rules. A new preparation environment may require a new
plan; immutable data alone does not justify reusing stale facts.

Task L assessed the pending alias policy across five targets. A shared-view
contract would require attention to Swift value storage and Rust owned versus
borrowed positions. A snapshot contract would require explicit ordinary
conversion behavior in targets whose representations currently admit sharing.
Rejecting writes through retained aliases requires source alias and effect
analysis beyond a local conversion decision. These are static design impacts,
with no measured cost or additional target-runtime observations. The coordinator
corrected a conclusion that conflated shared semantics with shared machinery:
one source contract can require different target implementations.

Task K implements a bounded recorder for the existing probes. Early coordinator
review found missing enforcement of recorded identity, incomplete input hashing,
and failure to invalidate results when inputs change. Those requirements were
already explicit in its brief; the executor is correcting the implementation.
No new general prohibition was added for those deviations.

K's fresh `k-record-01` run now retains command arguments, working directories,
timings, stdout, stderr, exit statuses, source hashes, and four generated-file
manifests under `out/architecture-readonly-probe/recording/runs/`. All four Swift
generations returned zero. The scalar and plain-to-optional programs compiled
and ran; the optional-source and guarded-source cases returned native compiler
status 1 and have skipped runtime records. The coordinator inspected the new
command records and outputs. They agree with the earlier observations and
provide the generation and status records that were previously missing.

Compiler and sample hashes, authored input hashes, HEAD `d01298f3`, compiler
status, and toolchain identity stayed stable. During the recording, the
coordinator edited the analysis-method Markdown file. The recorder therefore
sets `worktree_status_stable` and its aggregate `comparison_valid` to false.
Those fields remain unchanged. The retained commands support the bounded
observations above; they do not constitute acceptance of a fully frozen
candidate. The later full verification must keep the complete candidate unchanged as
the existing work plan requires. No compiler rerun was needed to inspect this
documentation-only difference.

## Successful child diagnostics

Task N prepared an external capture helper under
`out/architecture-child-capture/`. It records child arguments, executable
identity, working directory, timings, statuses, and separate raw output streams.
The coordinator inspected the synthetic records and the unchanged driver's
success and failure records. A successful fake compiler warning is absent from
the driver's transcript and present in the child record. This confirms the
diagnostic loss identified by B and demonstrates a bounded capture route.

Review returned three helper defects to the executor: canonicalizing an
executable path could change dispatch through a symbolic link; stopping a reader
after a forwarding error could leave the child blocked; and re-raising a signal
with the wrapper's handler still installed could prevent termination. The
corrected synthetic checks cover these cases, large concurrent streams, exact
arguments, and interruption. They establish helper behavior within that domain.
They do not establish complete capture for a future platform suite.

The helper does not classify warnings. Future acceptance requires records for
every expected compiler invocation, complete streams, and review of diagnostic
lines that name generated files. Absolute tool paths and package-local command
resolution require separate route checks. The driver's existing output buffer
limit also remains in force. No full verification ran, and the current checkout
still lacks the package-local TypeScript compiler needed by that command.

The existing brief already required argument and status preservation. These
delivery defects called for implementation corrections and discriminating
checks, without adding another general rule to the analysis method. The
proposed full-run recipe was separately corrected to stop on preparation
failure and preserve earlier evidence directories.

## Consumer input identity review

Task O inventories twelve Tiqian bundles at the fixed revision: eight engine
bundles, three protocol test bundles, and the stock-Haxe C-header generator.
Eleven have tests enabled. The driver compares enabled outputs against its
configured baseline, but the engine and protocol test identifier domains have
not yet been shown to match. Full driver verification also excludes optional
packaging and several product build checks. A later candidate must name its
required consumer checks from the affected interfaces and representations.

O revision 2 and coordinator source review found backend, standard-library
shadow, sample, and macro-directory references into `.haxelib/boring/git` in
the HXML include structure. Hashes of the sampled files match the pinned
consumer export; a recursive content comparison was not performed.
The candidate's package parameters do not replace these target class paths.
This finding corrects G2's broader inference from its haxelib observation;
actual module selection still requires a compiler execution record.

The driver derives its working directory from the project file's directory.
Placing a derived project under an output subdirectory would change relative
source paths. Moving all output paths would also affect the C-header generator,
whose source names a fixed destination. [Task P](architecture-round-1/p-consumer-inputs.md)
therefore prepares a project at the owned Tiqian root and preserves its outputs
while replacing compiler input paths in derived HXML files. Preparation is
authorized; generation remains subject to task I's unresolved review rejection.

This was a missing verification requirement in the earlier preflight brief.
The analysis method now requires tracing every compiler input source, preserving
the consumer working directory, and checking actual loaded modules where
available. P will exercise the revised preparation requirement across all twelve
bundles. Static path agreement will remain distinct from observed compiler
module resolution and regression evidence.

P prepared the twelve derived HXML files and the project at the consumer root.
The coordinator inspected every transformation diff: the project changes only
the twelve roots-file values; flattened HXML changes consist of candidate path
substitutions and a leading verbose flag. Output paths, protocol-C commands,
and ordinary consumer arguments remain intact. The retained manifest records
included HXML hashes, candidate source hashes, package mappings, and the pinned
driver executable. Tracked Tiqian changes remain empty. These findings accept
the static configuration preparation only.

The first preparation attempt left provisional files without a complete status
record. The executor preserved their inventory and moved those owned files to
a separate attempt directory before completing the final preparation. Its
earlier termination status remains unknown. Review also returned an incorrect
direct-Haxe launch proposal, an assumption about haxelib output ordering, and
shell assertions that did not stop on failure. The proposed generation recipe
requires separate review; no generation ran. Successful verbose compiler output
must use the child capture route established by N before it can support a
module-origin claim.

## Owner ruling and approved generation

The owner selected ordinary read-only conversion that keeps viewing the same
array: a later write through the mutable alias remains visible. Feature 18 now
states this source contract separately from its decoded-data protection rules.
The owner also authorized one Tiqian Swift f32 generation and an ordinary Git
push for the independent branch after GitButler could not support that linked
worktree. Commit `483974d6` was pushed to `arch/agent-guided-governance` without
merging or forcing an update.

Task Q ran that single generation at Boring `483974d6` and Tiqian `8504d230`.
The pinned driver and Haxe child returned zero. The child took about 37.3
seconds and produced 291 Swift implementation files and 124 Swift test files.
The coordinator inspected the child status and verbose parse records for the
candidate `Intercept`, `SwiftType`, `SwiftExpr`, runtime, and sample modules.
The parse log contains no path into the old Boring export. This supports the
bounded generation compatibility claim for this recorded pair.

The capture retained 136 Haxe `NonOptionalNilComparison` warnings at Tiqian
source locations even though driver stderr was empty. No Swift compilation,
native test, packaging, or full consumer suite ran. The generated-Swift warning
gate remains untested. Inputs matched the prepared hashes immediately before
launch; post-run tracked status was unchanged. The record does not contain a
second hash pass over all 709 candidate inputs after generation. An unrelated
extra newline in the observation brief was preserved and recorded.

Task R identified the representation scope required by the ruling. Swift's
ordinary and substituted type mappings, runtime view, declaration consumers,
and expression conversions must agree on shared storage. Brief J now assigns
`SwiftType` and `SwiftRuntime` in addition to the decision module, `SwiftExpr`,
and `SwiftDecl`. Reference-element tests use ordinary class instances whose
identity contract is independently supported. Decode protection and ordinary
view construction remain separate responsibilities.

The revised brief also requires matching fixture inputs when comparing
baseline and candidate output. New shared fixtures can expose another target's
existing semantic gap; a Swift-focused check cannot establish all-target
conformance. Rust's ordinary alias behavior remains a separate unverified
requirement. These limits are carried into implementation acceptance.
