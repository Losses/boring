# Enum comparison fixtures

Diagnostic fixtures for one bounded question: is a `@:dataClass` record whose
stored field holds a payload enum accepted as a sorted key, and do the
generated comparison and the generated structural equality then answer the
same question about two values? The fixtures observe the pinned tools. They
assert no source ruling, decide no payload ordering, and change no compiler,
specification, or dependency file.

## Reproduction

One invocation allocates one fresh run directory and records every stage in
it. Run from the repository root:

```
nix develop -c bash tests/haxe/enum-comparison/run.sh
```

The runner uses the shared stage membership checker at
`tests/support/stage-check.sh`; its hash is included in the selected input
digests recorded for each attempt.

The printed run directory under `out/enum-comparison/runs/` holds,
per stage: `commands/<stage>.argv` (lossless NUL-separated arguments),
`commands/<stage>.argv.text` (the same arguments shell quoted),
`commands/<stage>.cwd`, `commands/<stage>.stdout`, `commands/<stage>.stderr`,
and `commands/<stage>.status` (one decimal number). `values.txt` holds one
observed `key=value` row per read. `diagnostics.txt` holds the rejection
probe's diagnostic check. `identity.txt` holds the loaded toolchain versions,
the generator revision, and the fixed input digests. `input-hashes-before.txt`
and `input-hashes-after.txt` hold the same digest list taken at the first and
the last stage; a disagreement is a harness defect. Earlier run directories
are never rewritten.

A stage runs only when its producer stage exited zero in the same attempt; the
dependent stages of a failed producer are recorded as `not-reached` naming that
producer.

## Authored files

`enumcomparison/EnumComparisonSubject.hx` is one module with three types:

- `Tag`, an enum with the payload constructor `Value(v:Int)` and the
  parameterless constructor `Blank`.
- `TagKey`, a `@:dataClass` record whose one stored field holds a `Tag`.
- `EnumComparisonSubject`, the statics the harnesses call: four accessors that
  construct the keys, three table reads through `std.SortedMap`, and three
  equality reads through `std.RecordEq`.

Every value the harnesses read is constructed in the source module. The
harnesses construct nothing and hold no expectation.

`enumcomparison/rejected/RejectPayloadEnumKey.hx` names a payload enum directly
as a `SortedMap` key type. The compilation must stop with the payload-key
diagnostic. That rejection is the direct-key domain observation of
specification 07: it states where the direct key domain stops. Whether a
record field of the same enum type must be excluded the same way is an open
reading question, and this fixture records the admission without deciding it.

## Runtime claims

The TypeScript and the Rust stage execute the generated code. The Kotlin,
Swift, and Dart stages generate their trees for inspection only: no stage
compiles or executes them, so this fixture makes no runtime claim about those
three targets.

`harness/observe.ts` loads the generated TypeScript tree named on its command
line, calls the generated accessors, table reads, equality reads, and the
generated comparator, and prints one line per read.
`harness/harness.rs` does the same against the generated Rust crate compiled
as `enumgen`.

## Findings and the rules they bear on

The runner derives its mechanical expectations from one rule, the
specification 16 declaration-order rule: the comparator returns zero for two
values of one constructor, a negative value for the constructor declared
first, two table slots for two distinct constructor tags, and unequal records
for distinct tags. Everything else is recorded as an observation. From the
observations the runner writes findings. A finding names the rule it bears on
when a rule states the case, and states that no rule is cited when none does;
general payload-enum equality is one of the cases no rule states. A finding is
a recorded disagreement that awaits a ruling; the governing specification
decides what the comparison and the equality of a payload-enum field must be.

## Semantic limits

- The generated TypeScript equality read is a `===` over the field value, so
  the TypeScript numbers say nothing about a payload comparison. The Rust
  numbers do, because the generated Rust field comparison is the derived
  `PartialEq` of the enum.
- The Kotlin, Swift, and Dart trees are inspection evidence only.
- The `std.SortedMap` table reads expose the comparison through the resident's
  duplicate-key rule and its lookup, so a size of one is direct evidence that
  the comparator reported those two keys as equivalent. The size says nothing
  about whether the two keys must be distinct; that is the ruling this
  fixture awaits.
- No generated file is edited to pass; a blocked stage is reported as blocked
  through its `not-reached` rows.
