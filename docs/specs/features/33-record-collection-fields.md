# Feature spec 33: Record collection fields

Status: Planned. This specification amends the Contract element sentence
and the rejection sentence of
[12-std-string.md](../stdlib/12-std-string.md), and adds one sentence to
ruling 4 of [31-record-tostring-member.md](31-record-tostring-member.md).

## Scope

This specification rules the printed form of collection-typed fields in the
record member synthesis of feature spec 31: a `@:dataClass` field typed
`Array<T>` or `ReadOnlyArray<T>`. It also states the element domain of the
array rendering of stdlib spec 12, which the five targets already implement
through the shared operand-form function.

The engine port is the consumer. Four ported records keep explicit
`toString` members because of their collection fields (`BopomofoReading`,
`ClreqProfile`, `TiqianTextContent`, `RubySpan` under
`engine-haxe/src/org/tiqian/`): the Kotlin `List.toString` text joins
elements with `", "`, and the member synthesis had no ruled form for a
collection field. `TiqianTextContent` prints arrays of record elements
(`ReadOnlyArray<TextSpan>`, `ReadOnlyArray<TextRange>`), so the element
domain must include records. Every shaping and layout record with a
collection field would add another explicit member by hand.

This specification rules all five source targets (ts, kotlin, swift, dart,
rust) together; the f32 configurations inherit the rules and differ only in float
width.

## Current state

The assembly routine of spec 31 (`samples/std/RecordShape.hx`, `assemble`)
renders a record-typed field through the member call and every other field
as the bare field read inside the concatenation:

| Field shape | TypeScript | Kotlin | Swift | Dart | Rust |
| --- | --- | --- | --- | --- | --- |
| `Array<T>` or `ReadOnlyArray<T>` field, bare read in `+` | the array text joins with `,` and no space | the `List` field text joins with `", "` | the array text joins with `,` and no space | the list text joins with `,` | the operand has no `Display` implementation and the tree does not compile |

The array operand of `Std.string` already renders through the ruled
single-pass builders of stdlib spec 12 ruling 6 on every target, and the
element rendering recurses through the same operand-form function, so an
array of records renders each element through its member call on every
target today. The Contract of stdlib spec 12 restricts elements to the
operand list that names no record, so the implemented recursion is
unruled. The gap is the field routing: the synthesis never sends a
collection field through that lowering.

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| The assembly routes a collection field through `Std.string` | The field renders through the builder of stdlib 12 ruling 6: one growable accumulator, one index loop, zero per-element closures. | The separator, the brackets, and the element forms are ruled in one place; no target renders its native array text. | The builder and the element forms are the ones `Std.string` already lowers; the compiler keeps one array renderer. | The member body reads as the source reads: `Std.string(field)`. |
| The assembly builds its own loop per field | The same loop cost. | A second builder beside ruling 6 can diverge in separator or shape. | Two array renderers in the compiler. | The member body hides a loop the macro generated. |
| Kotlin relies on the native `List` text, the other targets build (the outcome of the chosen candidate on Kotlin) | The native text costs no builder; Kotlin emits no member at all (spec 31 ruling 1). | The native text and the ruled builder print the identical string. | Zero Kotlin-side code. | The Kotlin declaration reads as a plain `data class`. |
| The port keeps explicit members | No compiler work. | Every consumer re-decides the separator and the brackets. | Four members today, one more per collection-bearing record. | The port source repeats a loop per record. |

## Ruling

1. In the assembly routine of spec 31 ruling 4, a field whose type is
   `Array<T>` or `std.ReadOnlyArray<T>` renders its operand as
   `Std.string(<field read>)`. The operand domain check, the element
   forms, and the single-pass builders of stdlib spec 12 rulings 4 and 6
   apply unchanged, in the concatenation position of the member body and
   at the `RecordStr.str` call site.
2. The element domain of the array rendering of stdlib spec 12 is the
   operand domain of its Contract: scalars, parameterless enum values
   through their constructor-name reads, `@:dataClass` records through
   their member calls (the member synthesis of feature spec 31), and
   nested arrays recursively. This states the behavior the five targets
   implement through the shared operand-form function; the Contract
   sentence of stdlib spec 12 gains the record element clause, and its
   rejection sentence admits a `@:dataClass` receiver through the member
   call, which feature spec 31 admitted.
3. The rejection sentence of stdlib spec 12, second paragraph, names the
   error `Std.string accepts scalars, parameterless enum values, records,
   and arrays of them only`. The probes of
   `samples/tests/StdStringProbes.hx` assert the new text; an array whose
   element type is a class instance without the `@:dataClass` marker and
   a structure element stop the compilation with it, and the sanctioned
   path stays the explicit `toString` member in the source.
4. A nullable collection field (`Null<Array<T>>`,
   `Null<ReadOnlyArray<T>>`) renders through the same `Std.string`
   operand and stops the compilation with the named error; the class
   keeps an explicit member. The null comparison form of spec 31 ruling 4
   stays confined to record-typed fields.
5. Kotlin emits no member for a `@:dataClass` class (spec 31 ruling 1);
   the native synthesis prints an `Array` field through its `List` field
   type, whose text `[a, b]` is the string the ruled builders print. The
   other four targets and stage 1 print the builder through the
   synthesized member.
6. Stage 1 renders the `Std.string` operand natively and joins with `,`
   and no space; the sample rows with collection fields assert through
   the `boring_oracle` conditional, and the sample header records the
   divergence, the array-row pattern of stdlib spec 12.

## Samples and tests

- `samples/boring/PrintedCollection.hx`: a `@:dataClass` class with
  `names:ReadOnlyArray<String>`, `counts:Array<Int>`,
  `points:ReadOnlyArray<PrintedPoint>` (a `@:dataClass` declared in the
  same module), `matrix:Array<Array<Int>>`, and `none:Array<String>`; the
  constructor holds every field.
- `samples/tests/PrintedCollectionTests.hx`: the member text of one value
  with every field populated, compared with the ruled literal
  `PrintedCollection(names=[alpha, beta], counts=[1, 2],
  points=[PrintedPoint(x=1, y=2)], matrix=[[1, 2], [3]], none=[])` in
  constructor parameter order; one `RecordStr.str` equality row; the
  collection rows assert through the `boring_oracle` conditional on the
  Haxe target, with the divergence recorded in the sample header.
- Both modules are entered in all eight generation hxml files.
- Tree assertions in `tests/ts/printed-collection.test.ts`: the
  TypeScript, Swift, Dart, and Rust trees carry the synthesized member
  with the builder shapes of stdlib spec 12 ruling 6 (the
  immediately-invoked closure, the `StringBuilder` loop, the `StringBuffer`
  loop, the `String::new` with `write!` loop) inside the member; the
  Kotlin tree emits no member; no tree renders `.map(`, `join(`,
  `joinToString(`, or `joined(` for the collection fields.
- Mutation checks: a field typed `Array<PlainInstance>`, a class without
  the marker, stops generation with the named error of ruling 3; removing
  the `@:dataClass` marker from `PrintedCollection` drops the member from
  the four trees.
