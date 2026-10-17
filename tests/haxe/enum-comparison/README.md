# Enum comparison fixtures

Diagnostic fixtures for one bounded question: does a `@:dataClass` record whose
stored field holds a parameterless enum compare its keys by constructor
declaration order, and do the generated comparison and the generated structural
equality then agree on two values? A payload-enum field is not comparable, so
specification 16 kind 3 is narrowed to parameterless enums and a record with a
payload-enum field is rejected at the key-type gate before any comparison. The
fixtures observe the pinned tools. They decide no payload ordering and change no
compiler, specification, or dependency file.

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
probes' diagnostic checks. `identity.txt` holds the loaded toolchain versions,
the generator revision, and the fixed input digests. `input-hashes-before.txt`
and `input-hashes-after.txt` hold the same digest list taken at the first and
the last stage; a disagreement is a harness defect. Earlier run directories
are never rewritten.

A stage runs only when its producer stage exited zero in the same attempt; the
dependent stages of a failed producer are recorded as `not-reached` naming that
producer.

## Authored files

`enumcomparison/EnumComparisonSubject.hx` is one module with three types:

- `Rank`, a parameterless enum with the constructors `First` and `Second`, in
  that declaration order.
- `RankKey`, a `@:dataClass` record whose one stored field holds a `Rank`.
- `EnumComparisonSubject`, the statics the harnesses call: three accessors that
  construct the keys, one table read through `std.SortedMap`, one equality read
  through `std.RecordEq`, and the comparator entry points.

Every value the harnesses read is constructed in the source module. The
harnesses construct nothing and hold no expectation.

Two rejected forms each stop compilation with their own gate diagnostic:

- `enumcomparison/rejected/RejectPayloadEnumKey.hx` names a payload enum
  directly as a `SortedMap` key type. The compilation must stop with the
  payload-key diagnostic, `enums with payloads are not keys`.
- `enumcomparison/rejected/RejectPayloadEnumField.hx` names a `@:dataClass`
  record whose stored field holds a payload enum. The compilation must stop
  with the record-field diagnostic, `dataClass key TagKey field tag unsupported
  type TEnum(enumcomparison.rejected.Tag,[])`.

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
specification 16 declaration-order rule as narrowed: for a parameterless enum
field, two values of one constructor compare equal and the constructor declared
first compares before the one declared after it, and that order agrees with the
generated record equality. The payload-enum forms are exercised by the
rejection stages and never reach a value row. The runner asserts no payload
ordering and no general payload-enum equality.

## Semantic limits

- The Kotlin, Swift, and Dart trees are inspection evidence only.
- The `std.SortedMap` table reads expose the comparison through the resident's
  duplicate-key rule and its lookup: a size of two reports the two keys as
  distinct, and the value order exposes the constructor declaration order.
- No generated file is edited to pass; a blocked stage is reported as blocked
  through its `not-reached` rows.
