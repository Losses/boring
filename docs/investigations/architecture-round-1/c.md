# C: Guidance usability and upstream rules, revision 1 transcription

This repository copy corrects wording from the issued brief. Its task scope
is unchanged; the session evidence directory retains the issued original.

Read common.md in this directory first. You own only
`/tmp/boring-architecture-round1/reports/c.md`; all repository files are read-only.
Do not delegate further or run compilers.

Required deliverables:
1. Apply the existing analysis method to two real mechanisms on different
   targets from the exported Boring tree. Trace source guarantee, current
   decision, fact owner, consumers, and missing evidence. Identify ambiguous
   instructions and state any assumptions needed to apply them.
2. Browse primary source code for the official Haxe compiler and at least two
   Reflaxe transpilers. Pin inspected commit IDs and cite precise source URLs.
   Compare concrete normalization, analysis, conversion, printing, or pass
   rules relevant to your cases. Explain applicability and limits for
   Boring, including Rust's representation/ownership needs.
3. Propose actionable edits to the existing analysis method and implementation
   standard. Distinguish architectural invariants from one project's layout.
4. Design a later task that tests whether agents can generalize those edits
   without new source-name or rendered-text special cases.

Prefer a few thoroughly evidenced mechanisms over a directory tour. State
what is a fact, inference, recommendation, and unverified runtime claim.
If a source is inaccessible, record that and continue independent work.
