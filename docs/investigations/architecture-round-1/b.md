# B: Verification and candidate evidence, revision 1 transcription

This repository copy corrects wording from the issued brief. Its task scope
is unchanged; the session evidence directory retains the issued original.

Read common.md in this directory first. Read the named repository instructions.
Investigate Boring and Tiqian source exports. You have only Read, Grep, and Glob
tools. Return your English report in your final answer; the coordinator retains
the transcript. Do not create files or request shell or write tools.

Required deliverables:
1. Identify actual test entry points and required gates for Boring compiler
   changes. Follow package commands into their implementation.
2. Identify Tiqian's required compiler integration matrix and how it resolves
   its Boring dependency. Distinguish all Haxe target runners from additional
   platform/FFI checks. Identify what must be established before launching them.
3. A semantic-change to test-layer matrix for conversions, flow facts, numbers,
   strings, sharing, and printing. Name existing suites and uncovered requirements.
4. Evidence identity and stale-output risks; what the consistency checker
   actually compares; warning collection; baseline vs candidate comparisons.
5. A concrete staged execution procedure for a Swift array-conversion change
   and for a shared-analysis change. Cite valid entry commands from source,
   describe output directory collisions, and preserve all required gates.
6. Proposed improvements to task guidance and verification documents. Explain
   how to test them in the next round. List timing data only when sourced; mark
   all unmeasured costs unknown. Do not run full builds.

Each finding cites the exported source path and line numbers. Mark
commands proposed from source inspection as unexecuted. A passing consistency
comparison does not independently prove source semantics. Report gaps without
claiming no tests exist based on an incomplete directory search.
