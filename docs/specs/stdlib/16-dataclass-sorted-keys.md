# Spec 16: dataClass keys for sorted keyed tables

## Scope

The ported tiqian engine declares sorted tables whose keys are record objects. A
count over the Kotlin sources returns 44 sites keyed by three record types:

```
grep -rn "Map<TextRange,\|Map<RubySpan,\|Map<QuotePair," engine/src/commonMain/kotlin/org/tiqian
```

The three key shapes are `TextRange(start: Int, end: Int)`,
`RubySpan(baseRange: TextRange, text: String, ... font fields)`, and
`QuotePair(openIndex: Int, closeIndex: Int, quoteType: QuoteType)`. Each shape
uses only the comparable field kinds defined below, so one ruling covers all 44
sites.

`HashMap<Long, EdgeState>` at `ParagraphDpLineBreaker.kt:466` stays outside this
spec because its key is Int64 and TypeScript number precision governs it; that
case is tracked as a separate probe.

## Ruling

A class annotated `@:dataClass` (features/27 rule 4) is a legal key type for
`std.SortedMap` and `std.SortedSet` on every target.

Ordering is field lexicographic over the record fields in declaration order.
The compiler generates one resident comparator per record type from the typed
AST, following the structure-key comparator generation of spec 07 and the
type-directed helper rules of features/19. Anonymous structures keep their
spec 07 structure-key path; this spec adds named `@:dataClass` classes.

A field is comparable when its type is one of:

1. `Int`, compared as integer values.
2. `String`, compared in UTF-16 code unit order, matching spec 07.
3. An enum type, compared by constructor declaration order, matching features/28. This order applies equally to parameterized constructors after target-specific lowering.
4. A nested `@:dataClass` record, compared by this rule recursively.

A field of any other type (`Float`, `Bool`, collections, plain class references)
makes the record unusable as a key. The compiler rejects it with an error that
names the record, the field, and the field type. A `Null<T>` field is rejected
by the same rule because this spec defines no order between null and a value.

A `(get, never)` computed property is not a stored field and does not participate in key ordering. The key gate must apply the same stored-field filter at the top-level traversal and during nested dataClass validation. This is the validation-side counterpart to the rule that the comparator reads only the declared fields.

Ordering must be consistent with the structural equality that features/27
generates for `@:dataClass`: two records compare equal exactly when their
generated `equals` returns true. The comparator reads only the declared fields;
generated members such as `toString` take no part in comparison.

A comparator is generated only for records whose fields are all comparable; a record with an unsupported field has no comparator, and using it as a sorted key is rejected at the key type gate.

## Gate

The key domain gate lives in `classifyKey` in every target type module. The
command `grep -rn "sorted keyed tables support" src/reflaxe` lists each carrier;
this spec extends every carrier listed there. The gate accepts `TInst` whose
class carries `@:dataClass` metadata and routes it to the generated comparator.
The nested validation performed by every target carrier must apply the same stored-field filter used by the top-level `classifyKey` traversal.
The rejection message becomes:

```
sorted keyed tables support Int, String, structure, and dataClass keys in this implementation
```

## Samples and tests

Add `samples/boring/SortedDataClassKeysOps.hx` exercising the domain: a flat
two-field record (`TextRange` shape), a nested record (`RubySpan` shape), and an
enum-field record (`QuotePair` shape), each used as a `std.SortedMap` key with
insertions out of order and reads in key order.

Add `tests/ts/sorted-dataclass-keys.test.ts` mirroring the existing generated
tree tests: it reads the generated file for each target under `reference/` and
asserts the emitted comparator and table reads. Mutation evidence, following
features/19:

1. Swapping two field values between two keys changes the iteration order read
   by the test on every target.
2. Renaming one field of the keyed record changes the generated comparator text
   on every target.
3. Reordering two fields of the keyed record changes which of two keys sorts
   first, with key values chosen so the two orders disagree.
4. Adding a `Float` field to a keyed record makes compilation fail with the
   error naming the record and the field.

## Bans restated

One resident comparator per record type; call sites never inline comparator
code. No target may back these tables with a hash-ordered container. The
`std.SortedMap` and `std.SortedSet` runtime behavior ruled by spec 07 is
unchanged; this spec widens the key domain only.
