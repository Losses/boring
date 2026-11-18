# Attribution bisect

This tool finds the first commit in a failure window. It takes a last-green
commit and a red commit, verifies that they form a valid first-parent range,
and probes the commits between them.

## Usage

Local mode is the default. It checks out each candidate in a temporary
directory and runs one repro command. The exit code decides the probe.

    bun tools/attribution/cli.ts \
      --repo /path/to/repo \
      --last-green <sha> \
      --red <sha> \
      --command "bun run test" \
      --step "Compile and test" \
      --json report.json

CI mode pushes each candidate to a temporary branch, dispatches one workflow
run, waits for the selected job, and deletes the branch.

    bun tools/attribution/cli.ts \
      --repo /path/to/repo \
      --last-green <sha> \
      --red <sha> \
      --mode ci \
      --workflow ci.yml \
      --job linux \
      --json report.json

## Local checkouts

The default `worktree` mode runs `git worktree add --detach` for each
candidate. It keeps git metadata available to the repro command.

The `export` mode reads the commit through `git ls-tree` and
`git cat-file` and writes the tracked files to a temporary directory. It
makes no git worktree and suits environments that forbid version-control
writes. Commands that read git metadata need worktree mode.

Neither mode changes the tested commit. Every temporary directory is removed
after the probe unless `--keep-checkout` is set.

## Probe classification

- Exit code 0 is a pass.
- A non-zero exit code is a fail.
- A timeout, a signal, or a checkout error is an error. An error stops the
  run with exit code 3. The tool does not treat an error as a pass.

The last-green boundary must pass and the red boundary must fail. If red
passes, the tool refuses to attribute a commit and exits 3.

## Range rules

The range must satisfy all of these conditions:

1. Both arguments resolve to commits.
2. The last-green commit is an ancestor of the red commit.
3. The last-green commit is on the red commit's first-parent chain.
4. The range contains at least one commit between the two boundaries.

A reversed range, an unrelated pair, or a side-branch last-green is rejected
with exit code 2 before any probe runs. The tool never guesses a range.

## Report

Each probe records the commit, command, exit code, duration, and the last
lines of its output. The report contains:

- the first bad commit and its parent in the chain,
- the failing step (the `--step` label in local mode, the failed job step in
  CI mode),
- the log excerpt from the first bad probe,
- the number of bisect steps and the complete probe trace,
- a `reproduce` object with the exact tool command, a checkout command, and
  the repro command.

The JSON report is stable enough to attach to a task record.

## CI cleanup

Every temporary branch is deleted in a `finally` block after its probe. The
cleanup runs again at the end of the run and on SIGINT and SIGTERM. A branch
that cannot be deleted is listed in `cleanup.failures` and the run exits 4.
Use `--keep-branches` only for diagnosis.

Requests run one at a time. Rate-limit replies from `gh` are retried with a
backoff. The CI mode needs a workflow with `workflow_dispatch` on the
candidate commit.

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Report produced. |
| 2 | Invalid input or invalid range. |
| 3 | A boundary or probe could not decide. |
| 4 | Temporary branch cleanup failed. |
| 1 | Internal error. |

## Tests

    bun test tools/attribution/

The unit tests cover the bisect loop, the boundary refusal paths, the range
checks, the argument parser, and temporary branch cleanup with a fake CI
backend. A live CI dispatch is not part of the unit tests.
