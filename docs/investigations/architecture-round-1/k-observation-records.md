# K: Preserve complete observation records

## Objective and scope

Make the existing D observation reproducible with durable generation and native
command records. D retained compiler output but omitted generation logs and
stored exit statuses only in tool responses. Correct that evidence gap before
using the same observations to review an implementation.

Work in the owned `boring-wt-architecture` checkout. The recorded candidate is
`d01298f3`; its executable baseline remains `e3b8bab39ac2d`. Read `AGENT.md`,
the analysis method, D revision 2, and the existing authored probe files.
The coordinator keeps tracked compiler inputs fixed during this task.

The executor may author a small runner and accompanying metadata under
`out/architecture-readonly-probe/recording/`. It may read the existing D source
and HXML files and use new output directories under that recording directory.
Preserve earlier probe source and output. Do not edit tracked files, generated
files, existing expectations, source semantics, or the Tiqian checkout. No
commits, full test matrices, or driver changes belong to this task.

## Record contract

Each run gets a new directory. Reject a requested run directory that already
exists. Record the checkout path, full commit, relevant local changes, active
haxelib paths, tool executable paths and versions, and the authored source and
configuration hashes. Use the actual compiler worktree after Nix activation.

For every command preserve arguments, working directory, start/end times,
elapsed duration, exit status, stdout, and stderr. Commands must execute as
argument arrays or correctly quoted fixed shell commands. Preserve a failing
command's output and status without attributing its result to a later command.

Record generation and native compilation as separate steps. Run a generated
program only when its generation and compilation succeeded in this run.
Continue to independent cases after an observed compiler failure, and mark the
dependent runtime step skipped. A successful recorder execution means records
were collected; it does not mean all recorded commands passed.

Hash authored inputs before and after execution. Record generated manifests
after generation, including the configuration that chose their paths. Reject
reuse of preexisting target files or binaries as evidence for this run. Record
compiler input identity before and after so a changed candidate invalidates
the corresponding comparison. Do not collect environment variables or secrets.

## Cases and execution

Use the existing D authored operations without changing their behavior:

1. Haxe oracle for the exact scalar, producer, return, and nullable operations.
2. Swift scalar/producer/return generation, compilation, and observation.
3. Swift plain-to-optional generation, compilation, and observation.
4. Swift optional-to-optional generation and compilation; execute only if it
   compiles, without adopting the result as a normative expectation.
5. Swift guarded optional-to-required generation and compilation under the
   same rule.

Adapt only output-path defines into new HXML configurations. Retain the
interception macro and normal runtime generation. A native harness exposes
generated operations and does not implement their conversion. The empty test
callback remains runtime scaffolding with no conformance claim.

Use the pinned Nix environment, one compiler process at a time. One complete
recording is required. A repeat is justified only by a recorder defect or a
concrete missing record. Source semantics remain pending; do not compare Haxe
and Swift observations to a selected expected value.

## Acceptance and delivery

The coordinator must be able to inspect each command's result using the saved
files alone. Include at least one successful native operation and the observed
native compile failures. Verify that failed compilations have no runtime result
from an older binary. Preserve successful compiler output, including warnings.

Deliver the runner path and command, evidence directory, output manifest,
recording summary, any unsupported recording guarantees, and the task report at
`/tmp/boring-architecture-round1/reports/k.md`. State how to distinguish recorder
failure, observed compiler failure, skipped execution, and runtime observations.
The runner is investigation tooling; promoting it to repository test tooling
requires a separate review of its interface and coverage.
