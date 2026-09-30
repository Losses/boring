# Variable-bound counted-while audit

## Scope and source admission

The two measured inputs are hand-written `while` loops, not typer-promoted
`range-for`: `localBound` reads a local bound expression on every condition
check and performs a local reassignment; `growingLength` reads `values.length`
and grows the array once during the loop. `doubleControl` has two source
bound reads and is the instrument sensitivity control.

## Oracle (measured)

Command (cwd: repository root; exit status read directly):

```
/nix/store/98pb92k7pi6g5cifmg872jn18kghaxw5-haxe-4.3.7/bin/haxe \
  tests/haxe/variable-bound-loop-eval/oracle.hxml > /tmp/vble-audit/gen.out 2>&1; rc=$?; echo "haxe rc=$rc"
/nix/store/vd788darzi6n1k2zrj5x3kqgg03kbz93-nodejs-official-22.23.3/bin/node \
  /tmp/vble-oracle.js > /tmp/vble-audit/oracle.out 2>&1; rc=$?; echo "node rc=$rc"
```

Raw output:

```
haxe rc=0
node rc=0
tests/haxe/variable-bound-loop-eval/vble/Probe.hx:53: local=4 length=3 control=4
```

Thus the Haxe 4.3.7 oracle empirically establishes **per-iteration evaluation** for both
conditions: the local-bound expression is read 4 times (three true checks and
the terminating false check), while the growing-length expression is read 3
times (the growth changes the second check's bound). The authored source hash
for this run is `508851eb833b88441fe9cdbc2e78ef85c4352a8903859c090dcc0769cdc06843`.

## Five-target reachability

The committed driver is `run.sh`; it records generation/compile/run stages and
input hash. Running it produced `/tmp/variable-bound-loop-eval/`. Haxe oracle
was reached; the target generation attempt was not reached beyond tool loading:
all five target generation commands returned the raw error
`Error: /bin/sh: line 1: haxelib: command not found` (exit 1). Therefore each
dependent target is explicitly **not-reached** for generation, compilation,
and execution; no target count is guessed:

```
target=ts generation=not-reached reason=haxelib not found in current environment; compile=not-reached; run=not-reached
target=kotlin generation=not-reached reason=haxelib not found in current environment; compile=not-reached; run=not-reached
target=rust generation=not-reached reason=haxelib not found in current environment; compile=not-reached; run=not-reached
target=swift generation=not-reached reason=haxelib not found in current environment; compile=not-reached; run=not-reached
target=dart generation=not-reached reason=haxelib not found in current environment; compile=not-reached; run=not-reached
```

The target result is therefore an environment reachability result, not a static
code inference.

## Probe discrimination

The same Haxe run printed `control=4`, while `doubleControl` contains two
counted bound expressions. This is an independent positive count above 1 and
shows the counter is not a constant “one” instrument. The oracle's two distinct
shapes also produced 4 and 3, respectively.

## Committed support

`vble/Probe.hx`, `oracle.hxml`, `run.sh`, `README.md`, and this report are the
reproducibility-bearing fixture/driver and are committed with this audit.
Generated trees and `/tmp` evidence are not committed. No compiler code was
changed.
