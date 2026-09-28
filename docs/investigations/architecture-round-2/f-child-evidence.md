# F1: Retain child execution evidence

## Purpose and scope

The coordinator has integrated the reviewed F1 delivery and passed focused
integration verification. The [delivery review](f-child-evidence-review.md) records its
evidence and limits. The brief below retains the original assignment.

This is the first independent implementation candidate for package F. The
coordinator inspected `tools/bundle/Driver.hx`: `runCommand` joins stdout and
stderr, while `step` reports only a failure tail and discards successful output.
That prevents the parent invocation's output from proving the absence of
warnings in successful child commands.

Implement structured child evidence independently of compiler semantics and
source mapping. The broader diagnostic requirement remains package F work. No
compiler emitter or Tiqian source change belongs in this batch.

Claude Code reviewed the brief and currently implements the batch. Goose reviews
the delivery. The coordinator assigned an isolated implementation worktree after
the brief review. Source baseline is the published unfinished checkpoint `e5e21854`;
later documentation commits can carry this brief without changing compiler code.

## Ownership

The executor may change `tools/bundle/Driver.hx`, add one responsibility-specific
child execution module under `tools/bundle/`, add tests under
`tests/bundle-child-evidence/`, and document the option in feature 59. Existing
project configuration and target recipes retain their accepted behavior.
No other work package writes these files during F1.

F1 captures commands invoked through `step`. The direct consistency-manager
execution in `actionCompare` remains outside this batch and retains its current
console behavior. Document that exclusion beside the option; an F1 run does
not establish complete evidence for the compare action.

Use named, typed records and typed host API declarations for new logic. Existing
driver typing issues remain explicit surrounding work; they do not authorize
new untyped result records. Keep child execution and evidence serialization
separate from action selection and presentation of failure tails.

## Required behavior

Enable evidence capture through an optional `BORING_CHILD_EVIDENCE_DIR` setting.
When absent, preserve the driver's existing command selection, cwd, environment
overrides, exit behavior, and presentation. When present, allocate a fresh run
directory under that parent and never overwrite an earlier run. Each child
has a unique sequence entry, even when bundle/action/step names repeat.

For every `step` invocation, retain:

- Bundle, action, step, sequence, command, argv as an array, and actual cwd.
- Separate stdout and stderr files, including for successful commands.
- Start/end time, elapsed time, normal exit status, signal, and launch error
  as distinct fields. A signal or missing normal status cannot become success.
- Capture completeness and any capture error. Retain available output on
  launch or buffer errors. Do not mark partial output complete.
- Project configuration path and content identity, and an invocation identifier
  shared by all child records. These identify the driver inputs; they do not
  certify which compiler source a package resolver actually loaded.

Retain child streams without losing bytes through text decoding and re-encoding.
The captured execution must request buffer output from the host process API.
It cannot recover original bytes by wrapping the existing UTF-8 `runCommand`
result. Execute each command once, retain its raw buffers, and decode a copy
only for console presentation. The captured result uses a typed record with
separate status, signal, error, and completeness fields.
Use the repository's standard JSON facilities for the record. Do not serialize
the inherited environment or credentials. Record relevant declared override key
names if needed; effective compiler input provenance remains a separate task.

Capture all child outcomes before the driver exits on a failed step. The
evidence option must never convert a child failure into success. An evidence
write failure under enabled capture must produce a clear failure and incomplete
record where possible. A stale or incomplete record cannot represent a passed
child. Capturing output must not change the child's arguments, working directory,
or environment selection.

The driver can keep its current short console output. The raw retained streams
are the authority for warning inspection. This batch implements no warning
classifier, source map exporter, or policy decision trace, and makes no claim
that a warning-free parent log means warning-free generated code.

## Verification

Use controlled child programs to disprove loss or misattribution of evidence.
Do not run a language platform matrix for this tooling batch's focused checks.

1. A successful child writes different markers to stdout and stderr, including
   a warning-shaped stderr line. Both files must survive despite status zero.
2. A failing child writes both streams and exits nonzero. Keep its exact status,
   both streams, and the driver's existing failure behavior.
3. A missing executable and a signaled child have distinct recorded outcomes.
   Neither is recorded as a normal successful exit.
4. Two runs sharing the configured parent and repeated step names retain
   separate records. A pre-existing output directory or file is never reused
   as fresh evidence. Test the allocator's collision handling.
5. A child observes argv containing spaces, its cwd, and an explicit environment
   override. Captured and uncaptured execution must observe the same inputs.
6. Non-ASCII and non-UTF8 bytes in both streams survive byte comparison. Exercise
   buffer exhaustion with a child that emits beyond the configured capture
   limit. Retain partial streams and the host error, and mark capture incomplete.
7. A forced capture-write failure cannot report complete evidence or return a
   successful driver result under enabled capture.
8. Exercise the actual `Driver.step` integration through a small project or
   dedicated test entry. Testing only the new helper cannot prove successful
   output is retained by the driver or failure exit still occurs.

The focused suite compiles the driver from its checkout in the pinned Nix
environment. It must run in a clean checkout with no existing generated driver.
Use external filesystem conditions to force capture-write failure; production
code needs no test-only failure switch. Host API declarations must preserve
buffers as opaque values and distinguish exclusive directory creation from
recursive directory creation, which cannot establish a fresh run by itself.

Build the driver in the pinned Nix environment, run focused tests, and apply
format, typing, lint, and wording checks relevant to the changed files. Preserve
exact commands, logs, statuses, and changed-source hashes in a fresh run directory.
The coordinator then reviews the diff and Claude Code's independent findings.
Complete Boring/Tiqian integration remains a later fixed-candidate obligation.
