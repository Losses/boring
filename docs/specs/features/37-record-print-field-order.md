# Feature spec 37: Record print field order

## Scope

This specification amends the field order of the record print and
comparison expansions for class records. The ported engine source is the
consumer: `BreakOpportunity` declares its defaulted `penalty` parameter
third in the Kotlin primary constructor, before a non-defaulted `reason`;
Haxe optional parameters must trail, so the port declares the constructor
as `(index, kind, reason, ?penalty)`. Feature 31's synthesized member
follows constructor parameter order, so the port prints `reason` before
`penalty` while the original Kotlin engine prints `penalty` before
`reason`. The port carries a handwritten member for exactly this class to
keep the traces aligned; this specification removes the need for it.

## Current state

`RecordShape.local` lists the constructor parameters in constructor
parameter order, and spec 31 ruling 3 fixes that order for the
synthesized member, `RecordStr.str`, and `RecordEq.eq`. Spec 27 ruling 1
fixes `RecordCopy.copy` arguments to constructor parameter order, which
must not change: the copy expansion emits a constructor call, and the
constructor's own parameter order is what the call must follow. The
Kotlin target emits no member for a `@:dataClass` class and relies on
the native `data class` print, whose order is the generated primary
constructor's parameter order, so a reordered port class also prints in
constructor order on Kotlin.

| Form | TypeScript | Kotlin | Swift | Dart | Rust | stage 1 |
| --- | --- | --- | --- | --- | --- | --- |
| `@:dataClass` whose constructor order differs from field declaration order | prints in constructor order | prints in constructor order | prints in constructor order | prints in constructor order | prints in constructor order | prints in constructor order |

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Order by the declaration position of the field holding each constructor parameter | Compile-time sort of a name list; no runtime cost. | One order for the class record set, computed the way the anonymous branch already computes it. | Reuses `Context.getPosInfos` position ordering from `anonymousShape`. | The print follows the order the fields are declared in, the order a reader of the class sees. |
| Keep constructor parameter order and let ports reorder fields to match | None. | Every port class must declare fields in constructor order even when the constructor trails optionals, an ordering the Haxe type checker does not require. | One rule kept, many sources constrained. | Field declarations lose the order of the original Kotlin properties. |
| Kotlin: emit the synthesized member explicitly when the two orders differ | One extra method per reordered class; no classes in the ordinary case. | The member overrides the native print, so the same text rule as the other four targets holds. | The body is the same `RecordShape.assemble` expansion the other targets render. | The declaration reads as a data class with an explicit print, a legal Kotlin shape. |
| Kotlin: keep native synthesis for reordered classes | None. | The Kotlin print disagrees with the other four targets and with stage 1, breaking spec 31's text identity. | None. | Two print orders for one class across targets. |
| Reorder `RecordCopy.copy` arguments to declaration order too | None. | The copy expansion would pass arguments in an order the constructor does not accept. | None. | The expansion no longer reads as a constructor call. |

## Ruling

1. For a class record, the field set is still exactly the constructor
   parameters held by fields, but `RecordShape` lists them ordered by
   the source position of the field holding each parameter, the same
   ordering the anonymous branch applies through
   `Context.getPosInfos(...).min`. The membership errors are unchanged.

2. The order change applies to every consumer of the shape's field
   order: `RecordStr.str`, the feature 31 synthesized member, and
   `RecordEq.eq`. `RecordCopy.copy` keeps constructor parameter order
   for its constructor call arguments, so spec 27 ruling 1's copy
   sentence stands and its eq and str sentences read with this
   specification's order from here on. Spec 31 ruling 3's phrase "in
   constructor parameter order" reads "in field declaration order".

3. The Kotlin target keeps native `data class` synthesis, and emits no
   member, while the two orders agree. When a `@:dataClass` class's
   constructor parameter order differs from its field declaration order,
   the Kotlin target emits the synthesized member explicitly, overriding
   the native print, so the class prints the same text as the other four
   targets and stage 1. The emission-time detection uses the same
   declaration-position comparison as rule 1.

4. A class whose constructor parameters are all held by fields in the
   same order as they are declared produces byte-identical output on
   every target and in stage 1; the existing tests of specs 27 and 31
   keep their text.

## Samples and tests

- `samples/boring/RecordOrderOps.hx` graduates with the port's shapes: a
  `@:dataClass` whose defaulted constructor parameter sits before a
  non-defaulted one in field declaration order (fields `a`, `b`, `c`
  declared in that order, constructor `(a, c, ?b)`), a second class
  whose orders already agree, and read functions returning the printed
  forms and an equality check.
- `samples/tests/RecordOrderTests.hx` asserts the reordered class prints
  `name(a=..., b=..., c=...)` in declaration order, the aligned class
  prints as before, `RecordEq.eq` accepts equal values of the reordered
  class, and `copy` round-trips both classes.
- Both modules are entered in all eight generation hxml files.
- Tree assertions in `tests/ts/record-order.test.ts`: the Kotlin tree
  carries an explicit `override fun toString` for the reordered class
  and none for the aligned class; the TypeScript, Swift, Dart, and Rust
  trees carry the synthesized member for both classes with the
  declaration-order concatenation.
- Mutation checks: a class record whose constructor parameter is not
  held by a field stops the compilation with the existing macro error;
  removing the reorder makes the Kotlin explicit member disappear from
  the tree.
