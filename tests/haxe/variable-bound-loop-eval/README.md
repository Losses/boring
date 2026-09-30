# Variable-bound counted-while evaluation audit

This fixture contains only hand-written `while` loops (no range-for). `localBound`
reads a local bound each condition check; `growingLength` reads an array length,
which grows once during execution. `doubleControl` intentionally has two source
bound reads and is the instrument sensitivity control.

The runner/report for this audit records the Haxe 4.3.7 JS oracle first, then
per-target generation, native compilation, execution, stdout, input SHA-256 and
explicit `not-reached` stages. Evidence is observational; no compiler code is
changed.
