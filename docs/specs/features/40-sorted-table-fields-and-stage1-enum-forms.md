# Feature spec 40: Sorted table record fields and stage-1 payload enum forms

This specification amends
[33-record-collection-fields.md](33-record-collection-fields.md) and
[34-enum-constructor-printed-forms.md](34-enum-constructor-printed-forms.md).

## Scope

Two field shapes print unruled forms today and block the engine port's trace
parity. A `@:dataClass` field typed `std.SortedSet<T>` or `std.SortedMap<K,
V>` renders through no ruled form on any target: stage 1 prints the raw
receiver text, and the five generated targets never route the field through
a collection rendering. A payload enum operand prints its labeled form on
the five generated targets (feature spec 34) but its native positional form
on stage 1, which feature spec 34 ruling 6 sanctions and diverts through
the `boring_oracle` conditional.

The engine port is the consumer. `LineCandidate`
(`engine-haxe/src/org/tiqian/layout/LineOptimization.hx`) holds
`repair:Null<RepairOption>` (a nullable payload enum), and
`hangingClusterIndices:SortedSet<Int>`; the trace comparison against the
Kotlin goldens reports nine mismatching lines for
`ParagraphDpLineBreakerCoverageTest`, four over the positional enum form
(`repair=PushIn(2,...)` against the golden
`repair=PushIn(penalty=2,reason=...,offenderClusterIndex=2,...)`) and five
over the raw set text (`hangingClusterIndices={\n\tkeys : []\n}` against
the golden `hangingClusterIndices=[]`). The port today keeps interim text
helpers beside the record (`RepairOptions.render`,
`LineCandidates.renderIntSet`) that the ruled forms retire.

This specification rules all five source targets (ts, kotlin, swift, dart,
rust) and stage 1 together; the f32 configurations inherit the rules and
differ only in float width.

## Current state

The stage-1 assembly routine (`samples/std/RecordShape.hx`, `assemble`)
routes a field through `Std.string` when its type is `Array<T>`,
`std.ReadOnlyArray<T>`, or an enum, reads a record-typed field through its
own member, and reads every other field bare. A `std.SortedSet<T>` or
`std.SortedMap<K, V>` field falls into the bare read, so the member prints
the receiver's raw text. Each generated target's assembly carries the same
Array-only collection routing.

Stage 1 lowers no `Std.string` operand over a payload enum: the call passes
to the native Haxe conversion, which prints `Name(arg1,arg2,...)` positionally.
The Kotlin resident `SortedSetTable`
(`reference/kotlin/gen/runtime/SortedTable.kt`) holds a `MutableList` and
overrides no `toString`, so no target prints the ruled set text natively.

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Route sorted fields through one builder per target and render stage-1 payload operands through the labeled branch | One growable accumulator and one index loop per field, the same shape the array builders of stdlib spec 12 ruling 6 hold; one discrimination per payload operand. | The brackets, the separator, the entry form, and the iteration order are ruled in one place; every target prints one text. | The set element and map entry forms reuse the operand-form function the array rendering already recurses through; the labeled branch is the one the five targets already lower. | The member body reads `Std.string(field)` on every target; the operand sites stay unchanged. |
| Print the target-native table text | No builder on targets whose native text matches. | No native text matches: the Kotlin resident prints an identity hash and stage 1 prints the raw receiver fields. | Nothing to implement where a match existed; no such target exists. | Sites print a different text per target. |
| The port keeps its interim helpers | No compiler work. | Every consumer re-decides the brackets and the separator. | One helper per record with a collection or enum field; two today. | The port source drifts from the Kotlin original. |

## Ruling

1. The collection field domain of feature spec 33 ruling 1 gains
   `std.SortedSet<T>` and `std.SortedMap<K, V>`. A `SortedSet<T>` field
   renders `[` + the element forms joined with `", "` + `]`; a
   `SortedMap<K, V>` field renders `{` + the entry forms joined with
   `", "` + `}`, one entry as the key form, `=`, and the value form. The
   iteration order is the table order the sorted containers define; an
   empty set renders `[]` and an empty map renders `{}`. The element, key,
   and value domains are the element domain of feature spec 33 ruling 2,
   which the payload enum operand of feature spec 34 joins.
2. Every target builds the ruled text through the single-pass builder shape
   of stdlib spec 12 ruling 6, stage 1 included. The resident table types
   (`SortedSetTable` and `SortedMapTable` in `src/runtime/SortedTable.hx`)
   carry the ruled text as a `toString` member: stage 1 prints a sorted
   table field through that member, and the Kotlin data-class text
   concatenates the field texts, so Kotlin keeps the member skip that
   feature spec 33 ruling 5 grants Array fields. The other targets
   synthesize the record member whose field texts go through the
   operand-form function. A field or operand whose type is a type parameter
   renders through the operand-form function's parameter branch, the
   target's own conversion of the value, so a generic record over a sorted
   table field prints.
3. A nullable sorted table field (`Null<SortedSet<T>>`,
   `Null<SortedMap<K, V>>`) follows feature spec 33 ruling 4: it stops the
   compilation with the named error and the class keeps an explicit member.
4. Stage 1 renders a payload enum operand in the labeled constructor form
   of feature spec 34 ruling 1, at the `Std.string` call position and at
   the record-field position of feature spec 34 ruling 4; a parameterless
   constructor keeps its bare name. The branch covers every constructor
   with no catch-all arm, and its argument forms follow feature spec 34
   ruling 3, so an array argument joins its elements with `", "` through
   the ruled array form; the native `,` join does not apply. The stage-1
   sentence of feature spec 34 ruling 6 is replaced by this rule; the
   payload rows of `samples/tests/PrintedEnumTests.hx` and the sample
   header divergence note for payload constructors are removed, while the
   array-separator rows keep their existing `boring_oracle` conditional.
5. A field typed `Null<E>` where `E` is an enum renders `null` as `null`
   and a present value through the forms of feature spec 34 rulings 1 and
   2, the same two states the nullable record field of spec 31 prints; it
   compiles on every target. The nullable-enum sentence of feature spec 34
   ruling 4 is replaced by this rule.
6. The operand domain of stdlib spec 12, as amended by feature specs 33 and
   34, gains the sorted tables: a sorted table operand outside a record
   field prints the ruled text of ruling 1, through the resident member on
   stage 1 and through the operand-form function on the five targets. The
   rejection sentence rules the remaining types only.

## Samples and tests

- `samples/boring/PrintedSortedFields.hx`: a `@:dataClass` class with
  `marks:SortedSet<Int>`, `points:SortedSet<PrintedPoint>` (the
  `@:dataClass` of `PrintedCollection.hx`, imported), `lookup:
  SortedMap<String,Int>`, `emptySet:SortedSet<Int>`, and `emptyMap:
  SortedMap<String,Int>`; a second `@:dataClass` class with
  `mark:Null<PrintedMark>` importing `PrintedMark` from
  `PrintedEnumOps.hx`; the constructors hold every field.
- `samples/tests/PrintedSortedFieldsTests.hx`: the member text of one value
  with every field populated, compared with the ruled literal
  `PrintedSortedFields(marks=[1, 2], points=[PrintedPoint(x=1, y=2)],
  lookup={a=1, b=2}, emptySet=[], emptyMap={})` in constructor parameter
  order; the nullable rows print `mark=null` and
  `mark=Ring(diameter=1.5)`; stage 1 asserts the sorted rows directly, and
  the sample header records the array-element divergence only where an
  array argument row prints through the native `,` join.
- Both modules are entered in all eight generation hxml files.
- Tree assertions in `tests/ts/printed-sorted-fields.test.ts`: the
  TypeScript, Swift, Dart, and Rust trees carry the synthesized member
  with the builder shapes of stdlib spec 12 ruling 6 for the sorted
  fields, and the Kotlin tree carries no synthesized member, its field
  texts coming from the resident table member; the nullable enum field
  prints through the labeled branch with the null comparison; no tree
  renders `.map(`, `join(`, `joinToString(`, `joined(`, or a native table
  `toString()` call for the sorted fields.
- Mutation checks: a field typed `SortedSet<PlainInstance>`, a class
  without the `@:dataClass` marker, stops generation with the named error
  of feature spec 33 ruling 3; a `Null<SortedSet<Int>>` field stops
  generation with the named error; removing the `@:dataClass` marker drops
  the members from the five trees.
