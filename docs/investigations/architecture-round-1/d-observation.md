# D: Observe read-only array boundaries, revision 1

## Objective and authority

Establish what accepted Haxe input and the current Swift translation do when
a mutable array remains accessible after a read-only conversion. This task
collects observations for a semantic decision. It does not select a required
aliasing or snapshot behavior and does not change compiler implementation.

Read `AGENT.md`, `docs/compiler-problem-analysis.md`, the architecture work
plan, feature 18, and the relevant array specifications in this worktree.
The compiler baseline is `e3b8bab39ac2da0e17e9d04e031f03bd39290274` on branch
`arch/agent-guided-governance`; documentation commit `ad6bed45` adds guidance.
Read the accepted corrections in investigation A revision 2 when supplied.
The original Boring and Tiqian worktrees belong to other tasks.

## File and execution ownership

Use `/home/losses/Development/tq-workspace/boring-wt-architecture` as the
working directory. You may create probe source, harnesses, and artifacts only
under `out/architecture-readonly-probe/`. Keep authored probe source separate
from generated target files. Write the delivery report to
`/tmp/boring-architecture-round1/reports/d.md`. Do not edit production source,
existing fixtures, expectations, specifications, or generated files by hand.
Do not commit, change branches, or delegate another task.

Run tools through `nix develop -c`. Confirm the effective haxelib compiler path
before generation. Use the repository's pinned Haxe and Swift toolchains and
the existing generator entry conventions. All generated paths must remain in
the assigned directory. One compiler job may run at a time. Do not run the
whole Boring or Tiqian test matrix for this observation task.

## Required observations

Construct the smallest accepted cases that distinguish these questions:

1. A mutable scalar-element array reaches a `ReadOnlyArray` local, parameter,
   or return. A write through the original mutable array occurs before a later
   read through the read-only value. Record the observed element and length.
2. A conversion uses an effectful producer. Record its invocation count and
   order relative to a later read or write. Observational logging must preserve
   the number of evaluations.
3. An optional mutable array reaches an optional read-only destination for
   both absent and present input. Record whether the target compiles and what
   the program returns. Include a non-optional boundary for comparison.

Prioritize one complete end-to-end case before expanding the matrix. If the
interception pass rejects a case, record its exact diagnostic and source
contract. Do not bypass the rejection and call the bypassed form accepted.
If an element-alias probe requires an unsettled record or class contract,
record that dependency separately from scalar-element container observations.

Run the same authored Haxe operation through the Haxe oracle route and Swift
generation. A native harness may expose the generated operation's result; it
must not implement or repair the tested conversion. Record raw observations
independently. Equality or disagreement supplies evidence for a later ruling.

## Delivery and acceptance

Supply exact commands, exit statuses, compiler paths and versions, authored
source paths, generated output locations, and runtime observations. For each
compile failure collect the source construct, emitting function and line,
generated text, and target diagnostic. Preserve successful compiler warnings
as well as errors. Classify infrastructure failures separately.

Provide a table of the tested positions and observations with missing cells
explicitly marked. Identify which competing semantic policies the experiment
distinguishes, without declaring one policy authoritative. Cite specification
clauses that actually apply and name unresolved behavior.

The coordinator reviews the probe and observations before any implementation
assignment or owner-ruling request. Report instructions that were missing,
misleading, or unnecessarily broad, and propose one concrete guidance change.
