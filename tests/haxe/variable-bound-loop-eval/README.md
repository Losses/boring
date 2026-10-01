# Variable-bound counted-while evaluation audit

This fixture contains only hand-written `while` loops (no range-for). `localBound`
reads a local bound each condition check; `growingLength` reads an array length,
which grows once during execution. `doubleControl` intentionally has two source
bound reads and is the instrument sensitivity control.

`vble/Probe.hx` is compiled unmodified for every target. Its `main()` calls
`trace(...)`, which on the cross targets resolves to the fixture-local no-op
shadow `shadow/haxe/Log.hx` (the store `haxe.Log` does not typecheck against
the per-target std-shadow — see REPORT.md). The shadow changes no counted
expression; the per-target native driver in `native/` is the only printer of
the observation line `local=<a> length=<b> control=<c>`.

The runner `run.sh` records the Haxe 4.3.7 JS oracle first, then per-target
generation, native compilation, execution, stdout, raw exit codes, toolchain
identity, haxelib resolution, input SHA-256, and explicit `not-reached` rows
with their failed producer. Evidence is observational and lands under
`out/variable-bound-loop-eval/runs/<utc-stamp>/` (gitignored); the runner exits
non-zero only on harness defects, never on a target-level failure or a bad
reading. No compiler code is changed.
