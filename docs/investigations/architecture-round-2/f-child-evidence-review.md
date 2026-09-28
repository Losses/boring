# F1 delivery review

## Integration decision

The coordinator reviewed the GLM implementation and copied its twelve delivered
files from `architecture-workspaces/policy-f-child-evidence` into the coordinator
checkout. Every copied file matched the final execution's input hash. The source
checkout base was `e45c74b7`; the final retained run is
`out/f1-child-evidence/run-20260928-054416-2x6M1o` in that checkout.
The coordinator made no implementation edits. A documentation correction aligns
feature 59's allocation description with the tested collision-suffix behavior.

The retained final run uses Haxe 4.3.7 and Bun 1.3.13. Its focused suite reports
19 passing tests and 220 assertions. Focused TypeScript checking, repository
lint, documentation style and argument round-trip checks all have numeric
status zero. The coordinator independently checked the twelve input hashes,
the five identity statuses, the five check statuses and the NUL-separated
argument records, including empty, multiline and repeated-space arguments.
The coordinator then ran the durable entry in its integration checkout:
`out/f1-child-evidence/run-20260928-054744-U2wr9e`. All five checks returned zero,
including 19 passing tests and 220 assertions. This run includes the corrected
feature 59 documentation and records the integration checkout's inputs.

## Required corrections and review findings

| Finding | Required reasoning and delivered correction |
| --- | --- |
| An absent host stream was represented by a filename for a file that did not exist. | File presence, buffer availability and capture completeness are separate facts. The record now names only written files and distinguishes unavailable streams. |
| A collision retry changed the allocated directory without changing the invocation identifier. | Identity comes from the successful exclusive allocation. Repeated explicit allocator identities now produce distinct retained runs and identifiers. |
| A returned host error and a thrown host value had different capture paths. | Both need truthful retained outcomes. Tests exercise a real invalid-command throw and the production conversion of native errors, primitives and a foreign object with a numeric code. |
| A destination type annotation was used as evidence of a foreign value's shape. | The conversion validates object shape and exported text fields at the host boundary. The internal error record receives validated fields. |
| Runner command records lost argument boundaries or reused prior output. | Each attempt retains its own output, numeric statuses and lossless argument records. Identity capture failures affect the runner result. |
| The independent frozen-snapshot review accepted assertions that repeated an implementation defect. | Acceptance checks the governing requirement and actual retained files. A passing assertion cannot establish that a named file exists. |

Earlier briefs already required typed boundaries, truthful record claims and
preserved attempts. Several corrections address ignored requirements. The next
verification-tool assignment should demonstrate the same properties for a
different stage, including a failed identity command and changed compiler inputs.
This evaluates transfer of the reasoning to another case.

## Evidence limits

The first executor session deleted its earlier evidence directories. That gap
is disclosed in the retained external reports and cannot be reconstructed.
Later runs preserve failed attempts; they do not recover the missing history.
The final argument report also overstates what a zero child status alone proves:
the coordinator relied on decoded records and the runner's argument-array
comparison for the argument-preservation claim.

F1 covers recipe commands invoked through `Driver.step`. The direct consistency
manager execution remains outside capture. F1 implements neither source maps
nor compiler decision provenance. Full Boring verification and the fixed-version
Tiqian matrix remain programme requirements. Passing this focused delivery does
not establish the compiler changes' semantic correctness or complete package F.
