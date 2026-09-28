# Round 1 investigation context, revision 1

The user asks the coordinator to manage and improve Boring's internal guidance.
Execution agents perform code changes; this round is read-only investigation.
No implementation, tests, generation, dependency installation, git mutation,
or expensive build is authorized by this brief. Report evidence and unknowns.

Read-only source exports:
- Boring: `/tmp/boring-architecture-round1/boring`, exact commit
  `e3b8bab39ac2da0e17e9d04e031f03bd39290274`.
- Tiqian: `/tmp/boring-architecture-round1/tiqian`, exact commit
  `8504d230228e8206689a2049bbb84b671c1f079a`.
- Tiqian's flake still pins Boring `304ed70c4ba09fe21edadcca4c85f963fd692927`.
  These are different baselines. Do not attribute Boring-head behavior to Tiqian.
- Recent Boring history: `/tmp/boring-architecture-round1/recent-commits.txt`.
- Original Boring object database for read-only git show:
  `/home/losses/Development/tq-workspace/boring`.

The coordinator owns the independent worktree
`/home/losses/Development/tq-workspace/boring-wt-architecture`, branch
`arch/agent-guided-governance`, based on the exact exported Boring revision.
The original Boring worktree belongs to another active task. Never write there.

Required guidance, carried from documentation branch commit `a432e0d5`:
- `/home/losses/Development/tq-workspace/boring-wt-architecture/AGENT.md`
- `/home/losses/Development/tq-workspace/boring-wt-architecture/docs/compiler-problem-analysis.md`
- `/home/losses/Development/tq-workspace/boring-wt-architecture/docs/architecture-work-plan.md`
- The exported Boring implementation standard:
  `docs/specs/style/02-translator-implementation-standard.md`.
Read relevant feature specifications. Tiqian investigation also reads its
`AGENTS.md`. Repository instructions apply; this task's read-only scope means
there is no implementation or commit to perform.

Use rg and bounded file reads. Source exports have no .git or dependencies.
Builds, if assigned in a later brief, must use nix develop and isolated output.
Do not start them now. Do not inspect credentials or private model settings.
Do not assume conversation history. Ask the coordinator for missing evidence.

Reports use English and distinguish observed code, inferred risk, reproduced
failure, proposed design, and missing evidence. Every finding names the exact
file and line, governing source-language rule or architecture decision, fact owner, consumers, and test that could
disprove the explanation. Do not report static inspection as a runtime failure.
Separate target syntax from shared semantics and target representation.

For every task, include: documents actually read, commands actually executed,
confidence limits, and specific guidance changes that would have helped you.
The coordinator accepts findings only after checking their cited evidence.
