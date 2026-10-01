# Collected suite baseline, `ff8d66c2`, six trees present

Measured by the coordinator on `boring-wt-mainline` (a normal mount point, not
`dc-warn`). Recorded because the numbers are read by P09's criterion 2 and by the
collected-suite gate, and because a bare count is meaningless without the tree,
the tree-set, and the failure names.

## What was present

Six of the eight generated trees. `swift/gen` and `swift-f32/gen` cannot be
produced in this environment: the nix `swiftc` is an FHS wrapper and `bwrap`
fails with `bwrap: setting up uid map: Permission denied` (PIT-33/PIT-420).

| tree | files |
|---|---|
| `reference/ts/gen` | 225 |
| `reference/ts/gen-tests` | 251 |
| `reference/kotlin/gen` | 232 |
| `reference/kotlin-f32/gen` | present |
| `reference/rust/gen` | 547 |
| `reference/rust-f32/gen` | present |
| `reference/dart/gen` | present |
| `reference/swift/gen`, `reference/swift-f32/gen` | **absent** |

## An earlier reading on the same tree is NOT usable

An earlier run at `45743ba4` produced `914 pass / 136 fail / 6 errors`. It was
taken **before** the f32 trees existed, and its failures included a run where a
local `.haxelib` directory I had created for an experiment shadowed the dev
shell's registration, so `haxe -lib boring` failed with `Library reflaxe is not
installed` and `var-field-smartcast` failed for that reason alone. The same test
passes standalone and in the six-tree run. That reading is recorded here only so
it is not mistaken for a baseline.

## The six-tree run: five failures, each attributed

| # | Failing test | Cause |
|---|---|---|
| 1 | `archived gap.Gap counterexample generates and its Swift typechecks` | no `swiftc` (bwrap) |
| 2 | `failure-mode probe: the harness detects a broken Swift source` | no `swiftc` |
| 3 | `record printed-member generated trees > four non-native targets synthesize...` | `reference/swift/gen/...` ENOENT |
| 4 | `float precision switch on the Dart target > ... aborts the Dart compile` | dart startup path |
| 5 | `child execution evidence > ... a stderr-only child beyond the capture limit retains its stderr` | **real flake**, see below |

Four of five are environment-bound and disappear when the Swift lane is
available. **The fifth is not.**

## The flake, measured

`tests/bundle-child-evidence` run six times on this tree:

```
run1: 1 fail   run2: 1 fail   run3: 0 fail
run4: 1 fail   run5: 0 fail   run6: 1 fail
-> 4 fail / 2 pass
```

The failing assertion is

```
expect(record.stderrBytes).toBeLessThan(CAPTURE_LIMIT * 50);
```

and it receives exactly `204800` — i.e. the write filled the budget and the
`<` comparison sits on the side where the host's kill timing decides the value.
This is the **same family** as PIT-385/386, and the test itself was added as the
fix for that earlier flake, which is why it is recorded as PIT-424: a criterion
written to remove a race can carry the same race.

Tracked as `t-mupnn62w-tmka` with the failure-rate baseline above as its
criterion 1.

## What this baseline does and does not establish

- **Does**: the failure set at `ff8d66c2` with six trees, each failure named and
  attributed, and one of them shown to be a real intermittent rather than
  environment.
- **Does not**: anything about the Swift lane (unexercised here), and nothing
  about a fixed Boring×Tiqian pair — this is a Boring-side suite reading only,
  not the P09 matrix, and it does not satisfy P09 criteria 2–4.
