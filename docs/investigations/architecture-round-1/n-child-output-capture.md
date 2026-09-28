# N: Verify child compiler output capture

## Purpose and boundaries

Prepare the evidence route required before the later full verification. The
current driver captures successful child output and discards it in `step`.
An outer redirect cannot establish the generated-code warning requirement.

Use the owned architecture worktree at `1da1ab83`, with executable compiler
baseline `e3b8bab39ac2d`. Read `AGENT.md`, the implementation standard, the
work plan, and J's successful-output requirement. This task does not depend
on the pending array alias ruling and does not implement a compiler repair.

Author temporary capture tooling, synthetic tool programs, configurations,
and evidence only under `out/architecture-child-capture/`. The delivery report
is `/tmp/boring-architecture-round1/reports/n.md`. Do not edit tracked driver,
compiler, test, package, or configuration files. Do not touch Tiqian, retry its
rejected generation, commit, or run a full verification matrix.

## Capture protocol

Provide a scoped launcher that resolves each selected real executable before
adding its capture wrappers to the child search path. Keep changes local to
the launched process. Each invocation has its own record of executable,
arguments, working directory, timings, exit or signal status, stdout and stderr.
Forward arguments and both output streams without reinterpretation. Preserve
the child result. A successful command's output must survive even when its
driver caller discards it. Avoid recording environment variables or secrets.

State the supported tool routes after inspecting the actual driver and root
verification command. PATH wrappers do not intercept an absolute executable
path, and an inner environment may replace PATH. Identify uncovered commands
and how their output will be captured or why they do not emit compiler
diagnostics. Recording some children does not establish coverage of every gate.

Separate recording failures from compiler failures. Prevent recursive wrapper
resolution and record incomplete captures explicitly. The future acceptance
process must be able to distinguish a zero warning count from absent compiler
output. Raw output retention alone does not implement a warning classifier.

## Bounded checks

First test the launcher with synthetic tools confined to this output tree:

1. A successful tool writes distinct stdout and stderr, including a synthetic
   warning referencing a generated source path. Both retained streams match
   the forwarded streams and the child exits zero.
2. A failing tool writes diagnostics and exits with a specified nonzero code.
   Both streams and the original code survive.
3. Arguments with whitespace and shell metacharacters arrive unchanged, and
   output beyond a pipe buffer completes without deadlock or truncation.

Then compile the unchanged Boring driver to this task's output directory using
the pinned Haxe environment. Run a minimal synthetic project through that
driver with a scoped synthetic Haxe executable. Demonstrate that the driver
discards a successful child's diagnostic while the capture record preserves
it. Demonstrate a nonzero child result and the driver's own failure reporting.
Label this as capture-path verification; it is not target generation or a
semantic compiler test. Keep synthetic executable mappings out of any real
compiler run.

One serial native compiler process at a time. Preserve the exact commands,
statuses, source identities, wrapper configuration and raw evidence. Additional
checks require a concrete remaining risk; do not build a general execution
framework or add target diagnostic parsers in this task.

## Delivery

Provide the launcher and check commands, artifacts, route-coverage table,
observed limitations, and a proposed invocation for the later real Boring
verification. Mark that full invocation unexecuted. The coordinator reviews
the retained success and failure records before accepting this evidence route.
