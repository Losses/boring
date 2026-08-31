# Feature spec 36: Small array static initializers

## Scope

This specification extends the feature 30 initializer language for
`static final` fields whose initializer is a non-empty array literal. The
ported engine source is the consumer: `ClreqProfile` declares
`DefaultCoalesceRepeatablePunctuation:ReadOnlyArray<Int> =
[0x2014, 0x2026, 0x22EF]`, and `ClreqPunctuationPolicies` declares eleven
unit tables of two to twelve Int literals each. A generation run of the
port stops at the first of these fields with the feature 30 initializer
error, so none of the forms below render on any target today. Feature 20
keeps the compile-time table lane for `Array<Int>` literals above the
threshold with Int-only elements and stays untouched; feature 35 keeps the
construction lane and its argument grammar, which this ruling reuses at
the top level.

## Current state

`StaticFieldHelper.isSanctioned` admits an array literal only when it has
no elements, so all five targets share one defect: a non-empty array
literal at the root of a `static final` initializer stops generation with
`static field initializers accept null, literal, and empty array forms
only` (the final-field variant names construction as the extra lane).
Every target expression emitter already renders a non-empty array literal
in expression position, because feature 35 rule 2 admits array literals
as construction arguments: TypeScript and Swift render
`[e1, e2]`, Dart renders `[e1, e2]`, Rust renders `vec![e1, e2]`, and
Kotlin renders `mutableListOf<T>(e1, e2)`.

| Form | TypeScript | Kotlin | Swift | Dart | Rust |
| --- | --- | --- | --- | --- | --- |
| `static final` field initialized by a non-empty array literal | generation error | generation error | generation error | generation error | generation error |

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Kotlin: `listOf` for read-only element residence, existing `mutableListOf<T>` expression rendering for mutable arrays | One allocation per program; the read-only spelling documents that no consumer mutates the value. | The wrapper follows the declared field type, so two array spellings never compete for one field. | Reuses the expression emitter for the mutable case; the read-only wrapper is one name. | The declaration matches a Kotlin `listOf` source. |
| Kotlin: `mutableListOf` for every array literal | Same runtime shape. | A mutable backing for a field whose type promises read-only residence. | None. | The declaration claims mutability the source type does not have. |
| Rust: `#[allow(non_upper_case_globals)] static NAME: LazyLock<Vec<T>> = LazyLock::new(\|\| vec![...])` for general elements | One construction per program; every read borrows without locking. | One representation per array static; matches the feature 35 construction lane. | `LazyLock` is standard-library. | The declaration reads as a lazily built constant. |
| Rust: `static NAME: [T; N] = [...]` for Int-literal elements | Read-only memory, no runtime initialization; the feature 20 table form already rules this shape. | Same spelling as the table lane while the element count is below the threshold, so both sizes read alike. | None; the table lane's element type mapping is reused. | The declaration reads as a constant table. |
| Element grammar: reuse feature 35 rule 2 recursively | Compile-time classification only. | One enumerated grammar for construction arguments and array elements; a rejected element names its category in the feature 35 argument error. | No second expression system. | Each accepted element form is one the emitters already render. |
| Element grammar: Int literals only | Compile-time classification only. | A narrower lane than the argument grammar for no consumer. | Two array grammars to read. | The rejection of a String or enum element names no rule the port violates. |

## Ruling

1. A `static final` field initializer may be a non-empty array literal
   whose every element is an admitted argument under feature 35 rule 2,
   evaluated recursively. A `static var` field with a non-empty array
   initializer stops generation with the feature 30 text `static field
   initializers accept null, literal, and empty array forms only`. A
   final field whose initializer is an array literal with an element
   outside feature 35 rule 2 stops generation with the feature 35
   argument text `constructed static field arguments accept literal,
   enum, array, construction, static field, and static function forms
   only`. The feature 35 final-field text becomes `static field
   initializers accept null, literal, array, and construction forms
   only`, and every test that pins the previous text updates with it.

2. Classification order per field: the feature 20 table lane applies
   first (an `Array<Int>` literal with more than `DataTableHelper`
   threshold elements and Int-only elements stays a table); this
   specification's array lane applies next; the feature 35 construction
   lane and the feature 30 lanes follow unchanged.

3. Lowering per target:

   | Target | Declaration | Read |
   | --- | --- | --- |
   | TypeScript | `public static readonly name: T = [e1, e2];` | `Class.name` direct reference |
   | Kotlin | `val name: T = listOf(e1, e2)` in the object or companion object when the declared type maps to a read-only list; the existing `mutableListOf<T>(e1, e2)` expression rendering when it maps to a mutable array | `Class.name` direct reference |
   | Swift | `static let name: T = [e1, e2]` with the existing Int-literal annotation inference | `Class.name` direct reference |
   | Dart | `static final name: T = [e1, e2];`, or a top-level `final` when the declaring class flattens | direct reference, module-scope under flattening |
   | Rust | Int-literal elements: `static NAME: [T; N] = [e1, e2];` at module scope with the feature 20 element type mapping; any other element: `#[allow(non_upper_case_globals)] static NAME: LazyLock<Vec<T>> = LazyLock::new(\|\| vec![e1, e2]);` | the array form reads directly; the `LazyLock` form reads through `&*NAME`, with the existing move adaptation cloning when the consumer takes ownership |

4. Every target constructs the value once per program, on the same
   access discipline feature 35 rule 4 records for construction
   statics.

## Samples and tests

- `samples/boring/ArrayRootStateOps.hx` graduates with the port's
  shapes: a read-only three-element Int table, a mutable two-element
  Int array, a two-element String array, an array mixing an enum
  constructor with a `static final` field read, and a nested array of
  Int literals. Read functions expose lengths and elements for every
  form.
- `samples/tests/ArrayRootTests.hx` asserts the element counts, the
  read-only table's elements, the String pair, the enum element, the
  cross-field element, and the nested array's shape.
- Both modules are entered in all eight generation hxml files.
- Tree assertions in `tests/ts/array-root.test.ts`: the TypeScript tree
  carries `static readonly` over the literal; the Kotlin tree carries
  `listOf(` for the read-only field and `mutableListOf` for the mutable
  one; the Swift tree carries `static let`; the Dart tree carries
  `static final`; the Rust tree carries `[u32;` or `[i32;` for the
  Int-literal tables and `LazyLock<Vec<` with `LazyLock::new` for the
  String and enum arrays.
- Mutation checks: a `static var` field with a non-empty array
  initializer stops generation with the feature 30 text; an array
  element holding a local variable read stops generation with the
  feature 35 argument text; a final field whose initializer is a static
  function call at the root stops generation with the rule 1 final-field
  text.
