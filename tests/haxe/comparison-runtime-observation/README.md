# Comparison observation fixture

Baseline evidence for compositional record ordering, taken before the A3
comparator migration touches any consumer. The fixture observes the comparators
that the five targets emit for `@:dataClass` sorted-table keys, over four field
shapes, and reports which named risks are real generation, target-compile, or
runtime failures.

## What it holds

| Path | Role |
| --- | --- |
| `comparison/ComparisonObserve.hx` | The authored record declarations and the observation functions. The module states no ordering rule; it builds sorted tables and reports the order it observes. |
| `hxml/<target>.hxml` | One focused generation entry per target. The caller supplies the output define, so every attempt writes into its own run directory. |
| `native/main.ts`, `native/Main.kt`, `native/harness.rs`, `native/main.swift`, `native/main.dart` | The per-target invocation harnesses. Each prints the text one generated observation function returns, and each re-implements no comparator. |
| `expected.tsv` | The authored expected observation per case, with the specification rule it comes from. |
| `run.sh` | The durable runner: fresh run directory, lossless argv, separate streams, numeric statuses, hashes, and the case comparison. |

## Cases

1. `int-ordinary` and `int-extremes`: an `Int` field, at ordinary values and at
   the signed 32-bit limits, in both operand orders (spec 16 kind 1).
2. `array-order`: a direct `std.ReadOnlyArray<Int>` field, with unequal
   singletons, equal collections, a proper prefix, and a pair whose later
   element would reverse the stated direction (spec 16 kind 5).
3. `nullable-order`: a `Null<std.ReadOnlyArray<Int>>` field. Every operand is a
   present record whose field is absent where the case needs it, so the outer
   null ordering and the element comparison stay separate observations
   (spec 16 kind 6, over the collection rule of kind 5).
4. `string-order`: a `String` field, with equal strings, ASCII direction, and
   U+10000 against U+E000, whose UTF-16 code-unit order disagrees with
   scalar-value order (spec 16 kind 2, over spec 07).

Each observation records both operand orders through the two insertion orders
of one table, and the equality cases leave one entry holding the last put.
The two extreme-value functions run in their own process, so a crash there
cannot prevent the other cases from being recorded.

## Observation channel

The generated operation is the source sorted-key operation: `std.SortedMap`
binds the resident comparator of its key type at `builder()`, and the table
read states which key sorted first. The observation text encodes the first and
second table values and the entry count, so one line carries direction,
asymmetry, and equality:

    unequal=AB#size2;AB#size2|swapped=BA#size2;BA#size2|equal=size1atB

`A` and `B` are the values put under the two keys; `AB` means the key whose
value is `A` sorted first. The text before the `;` comes from the table built
in one operand order, the text after it from the same pair in the other order.

## Running

    nix develop -c bash tests/haxe/comparison-runtime-observation/run.sh

The runner leaves one directory per attempt under `out/comparison-runtime-observation/runs`
and writes nothing else. `summary.txt` holds the verdict, the findings, the
status rows, and the warnings; `logs/` holds the argv, working directory,
streams, and status of every stage, including the verbose Haxe generation
output with the actual classpaths and parsed module paths.
