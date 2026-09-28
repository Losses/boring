# A: Recurring compiler mechanisms, revision 1

Read common.md in this directory first. Investigate all five targets at the
exported Boring revision. Pay particular attention to the newly merged warning
fixes, because earlier surveys predate that merge.

Deliver `/tmp/boring-architecture-round1/reports/a.md`. You own only that report.
Other files are read-only. Do not delegate further.

Required deliverables:
1. A matrix covering representation/conversion, null/control flow, numeric
   behavior, string units, identity/sharing, evaluation effects, and printing.
   For each target provide an inspected location and explicit status, or mark
   it not inspected. Prioritize depth for the most consequential mechanisms.
2. Three highest-priority mechanism findings with producer/consumer interfaces,
   violated architectural criteria, and counterexamples worth testing.
3. Inspect Swift mutable/read-only array conversion across calls, returns,
   assignments, literals, and optionals. Decide whether it remains a sound
   initial candidate or suggest a better one with evidence and dependencies.
4. Review selected recent fixes across targets. Separate sound corrections
   from code-shaped conditions without the necessary semantic proof.
5. Propose changes to the existing analysis/implementation guidance. Explain
   how a later task could test whether each change improved agent reasoning.

Avoid a list of isolated suspicious lines. Explain common causes and the
smallest explicit requirement that serves the affected family of programs.
Do not invent runtime results or prescribe an architecture solely to shorten
files. Target roughly 200-350 report lines with precise citations.
