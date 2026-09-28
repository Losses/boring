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
