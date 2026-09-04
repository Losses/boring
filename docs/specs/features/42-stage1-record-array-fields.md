# Feature spec 42: Stage-1 record array fields

This specification amends
[33-record-collection-fields.md](33-record-collection-fields.md).

## Scope

A `@:dataClass` field typed `Array<T>` or `std.ReadOnlyArray<T>` prints the
ruled `", "` join on the five generated targets (feature spec 33 rulings 1
and 5) but the native `,` join with no space on stage 1, which feature
spec 33 ruling 6 sanctions and diverts through the `boring_oracle`
conditional. Feature spec 40 already removed this kind of divergence for
the neighboring field shapes: ruling 2 prints the sorted table fields
through their resident `toString` members on stage 1, and ruling 4 prints
the payload enum fields through the labeled constructor form on stage 1.
The array field is the one record field shape whose stage-1 text still
differs from the generated targets.

The engine port is the consumer. The port trace runner
(`engine-haxe/src/org/tiqian/test/trace/TestTraceRender.hx`) records a
message longer than 240 characters as the first 240 characters, `~`, the
full length, `#`, and a hash of the raw full text (`cap`, line 72). The
port compares its traces against Kotlin goldens generated on the JVM,
where a collection field prints the `List` text with the `", "` join; the
port's compare tolerance normalizes the separator difference in the
visible text only, and no tolerance can reach a hash of the raw text.
Five golden trace lines of the port's `AsciiPointMarkKinsokuTest`
comparison carry the `notes:ReadOnlyArray<String>` and
`repairCandidates:ReadOnlyArray<LineRepairCandidateInfo>` fields of
`LineDecisionInfo`
(`engine-haxe/src/org/tiqian/core/LineDecisionInfo.hx`, lines 12 and 13)
with two or more elements inside messages longer than 240 characters. The
port reconstructed those five full texts and verified that spacing the
separators to `", "` reproduces the golden lengths and hashes on all five
lines, so the separator is the only difference. Ruling the stage-1 form
removes the divergence class; exempting the separator inside the hash
comparison instead would blind every capped line to separator changes.

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Stage 1 renders the array field through the ruled loop | The loop is the one the stage-1 argument form of feature spec 34 ruling 3 already lowers: one `StringBuf`, one index loop, zero per-element closures. | The separator, the brackets, and the element forms are ruled in one place; stage 1 and the five targets print one text. | The compiler keeps one stage-1 array loop, the one `EnumText` already holds; the member body source stays `Std.string(field)`. | The sample rows assert the ruled literal with no conditional. |
| Keep the divergence and exempt the separator inside the hash comparison | No compiler work. | The exemption must know which bytes of the raw text are separators, which the hash erases. | A second normalization beside the visible-text tolerance. | The compare tool carries a rule no reader can check against a hash. |
| Keep the divergence and the conditional | No compiler work. | The port consumer cannot reach parity on capped lines at all. | One divergence record per future collection-bearing sample. | The sample header explains a difference the ruled form removes. |

## Ruling

1. On stage 1, a record field typed `Array<T>` or `std.ReadOnlyArray<T>`
   renders through the array argument form of feature spec 34 ruling 3,
   the loop `samples/std/EnumText.hx` lowers (`arrayForm`): `[`, an index
   loop that appends `", "` before every element except the first, each
   element through the operand form of that function, and `]`. The
   substitution sits in the assembly of `samples/std/RecordShape.hx`
   beside the stage-1 enum field form of feature spec 40 ruling 4
   (`stage1EnumFieldValue`) and runs only in the `boring_oracle`
   compilation.
2. The element forms at the stage-1 field position are the operand forms
   the loop already lowers: a scalar through `Std.string`, a
   parameterless enum value through its constructor-name read, a payload
   enum element through the labeled renderer, a record element through
   its member call, whose own collection fields render through this rule
   recursively, a nested array recursively, and a sorted table element
   through its resident `toString` member. The element domain is the one
   feature spec 33 ruling 2 states, joined by feature spec 40 ruling 1.
3. Every generated-target compilation keeps feature spec 33 ruling 1
   unchanged: the assembly still emits `Std.string(<field read>)`, the
   five targets lower the builders of stdlib spec 12 ruling 6, and no
   tree text changes. The stage-1 sentence of feature spec 33 ruling 6
   is replaced by this rule for the array field shapes. The replacement
   touches no other divergence: a plain `Std.string(array)` operand
   outside a record field stays native on stage 1 and keeps the
   divergence stdlib spec 12 records, and the array-separator row of
   `samples/tests/PrintedEnumTests.hx` keeps the conditional feature
   spec 40 ruling 4 granted it.
4. A nullable array field stops the compilation before any field-position
   rule runs (feature spec 33 ruling 4); this rule adds no nullable form.

## Samples and tests

- `samples/tests/PrintedCollectionTests.hx`: the collection rows assert
  the ruled literal unconditionally for both `v.toString()` and
  `RecordStr.str(v)`; the `boring_oracle` conditional and the sample
  header divergence note are removed.
- No generation hxml changes and no tree assertion changes: the four
  trees carry the same member text as before this specification, and the
  mutation checks of feature spec 33 keep their behavior.
