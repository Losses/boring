# G: Establish the isolated consumer environment, revision 1

## Objective and context

Prove which compiler and driver an isolated Tiqian generation command will use.
This is environment preparation for later regression checks. It does not run
the full matrix or establish compiler/runtime compatibility.

The coordinator created Tiqian worktree
`/home/losses/Development/tq-workspace/tiqian-wt-boring-architecture`, branch
`arch/boring-validation`, at `8504d230228e8206689a2049bbb84b671c1f079a`.
Its flake pins Boring `304ed70c4ba09fe21edadcca4c85f963fd692927`.
The candidate compiler worktree is
`/home/losses/Development/tq-workspace/boring-wt-architecture`, branch
`arch/agent-guided-governance`, based on
`e3b8bab39ac2da0e17e9d04e031f03bd39290274`. Current changes above that baseline
are documentation and source-comment wording; record the actual revision and
local diff when preparing the environment.

Read both repositories' agent instructions, Boring's compiler analysis method,
the work plan, and report B revision 2 in the session evidence directory.
Treat that report's recipes as proposals. Verify the actual shell hook and
driver configuration before relying on them.

## Scope and execution

You may initialize only the new Tiqian worktree's local development environment
and retain logs or preparation scripts under its `out/architecture-preflight/`.
Write the delivery report to `/tmp/boring-architecture-round1/reports/g.md`.
Do not edit tracked source, lock files, compiler files, original worktrees, or
global configuration. If a shell hook regenerates a tracked roots list, record
the resulting diff and ask the coordinator to review it; do not commit it.
Do not delegate or perform Git mutations.

Use Tiqian's `nix develop` environment. After its shell hook has registered
the pinned package, set the worktree-local `haxelib dev boring` mapping to the
actual candidate worktree. In that same activated shell, record the effective
`haxelib config`, `haxelib path boring`, `haxelib path reflaxe`, driver path,
and supported command syntax. Distinguish an old copied revision-marker file
from the active haxelib mapping.

Inspect the consumer's prerequisite data paths and source roots. Report missing
golden data, Unicode data, package dependencies, or platform tools without
launching a full build. Do not download large data or compile platform suites
in this task. The concurrent observational task D owns the compiler slot.

Design a repeatable preparation command for later generation that retains the
override after the shell hook. A second independent `nix develop` may reset
the mapping; account for this explicitly. Preserve failure exit codes and
avoid a success statement that depends only on the last command in a sequence.

## Acceptance

Deliver raw identity observations, executed commands and exit statuses,
worktree diffs, prerequisite gaps, and the exact unexecuted focused command
that should next establish driver/compiler compatibility. No generated-code,
warning, performance, or Tiqian regression claim is accepted from preflight
alone. State which guidance prevented a version mistake and what remained
ambiguous.
