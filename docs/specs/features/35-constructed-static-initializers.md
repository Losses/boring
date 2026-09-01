# Feature spec 35: Constructed static initializers

## Scope

This specification extends feature 30 ruling 2 for `static final` fields
whose initializer constructs a value. The ported engine source is the
consumer: `BuiltInLayoutProfiles.ClreqHorizontal` constructs another class
from a string literal, `ClreqProfile.MainlandHorizontal` constructs its own
class from arguments that mix literals, parameterless enums, an enum with
payload arguments, an array literal, another class's constructed static, a
static function call, and nested constructions, and `AutoSpacePolicy`
constructs its own class from null, Float, and enum arguments. A
generation run of the port stops at the first of these fields with the
feature 30 initializer error, so none of the forms below render on any
target today. Feature 32's self-construction static covers the separate
zero-argument same-class singleton form and stays untouched.

## Current state

`StaticFieldHelper.validatedInitializer` rejects every construction
initializer before a target emitter runs, so all five targets share one
defect: generation stops with `static field initializers accept null,
literal, and empty array forms only`. The port carries four fields of the
cross-class form and six of the same-class form; the same-class arguments
reach every expression category the ruling below admits.

| Form | TypeScript | Kotlin | Swift | Dart | Rust |
| --- | --- | --- | --- | --- | --- |
| `static final` field initialized by `new C(args...)`, another class | generation error | generation error | generation error | generation error | generation error |
| `static final` field initialized by `new Self(args...)` | generation error | generation error | generation error | generation error | generation error |

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Rust: `LazyLock` static over the construction closure | One construction per program; the lock checks an atomic the target runtime already provides; every read borrows or clones without locking. | One representation per constructed static; the declared field maps to one Rust item. | No new dependency; `LazyLock` is standard-library. | The declaration reads as a lazily built constant. |
| Rust: `Mutex` static as in feature 30 rule 3 | One construction plus one lock acquisition per access; the source field is final, so the lock guards a value that never changes. | Shares the mutable-static representation, so two different shapes of static read alike. | The lock is state the source never mutates. | Readers weigh locking the emitter did not need. |
| Rust: `pub const` with the construction inline | No runtime cost; the construction arguments include function calls and cross-class reads, which const evaluation rejects at the Rust compile. | Same spelling as the const form while the value is not a const expression. | None. | The declaration claims a guarantee the target rejects. |
| Argument grammar: closed recursive language over literals, enums, arrays, constructions, static field reads, static function calls | Compile-time classification only. | One enumerated grammar; a rejected argument names its category in the error. | No second expression system; the categories reuse the coalescing grammar's shape. | Each accepted argument form is one the emitters already render at call sites. |
| Argument grammar: any expression the emitters render | Compile-time delegation to five renderers. | Acceptance depends on five renderer implementations agreeing; a partial renderer agreement produces a per-target generation failure, and the failure names no rule. | No classifier to maintain. | No enumerated language to read; the error for a rejected form is the renderer's own. |
| Sanction the construction form for `static var` too | Same runtime shape on four targets. | Rust needs `LazyLock<Mutex<T>>` for re-assignment after construction, a shape no port field uses. | A compound wrapper for zero consumers. | The mutable grammar keeps the simpler feature 30 language. |

## Ruling

1. A `static final` field initializer may be a construction
   `new C(args...)` where `C` is a compiled class of the compilation unit
   set. Abstract statics keep their existing classifications and do not enter this
   ruling.

2. Each construction argument is one of the following, recursively:

   - `null`, Bool, Int, and Float literals, and String literals;
   - an enum constructor read, with each payload argument itself an
     admitted argument;
   - an array literal whose elements are admitted arguments;
   - a nested construction `new D(args...)` under rule 1;
   - a read of a `static final` field of any admitted initializer form,
     qualified by the declaring class when it differs from the field's
     own class;
   - a call of a static function of a compiled class whose arguments are
     admitted arguments.

3. The construction form requires a final field. A `static var` field
   with a construction initializer stops generation with the feature 30
   text `static field initializers accept null, literal, and empty array
   forms only`. A final field with an initializer outside rule 1 of this
   specification and outside the feature 30 initializer rules stops generation with
   `static field initializers accept null, literal, empty array, and
   construction forms only`. A construction argument outside rule 2 stops
   generation with `constructed static field arguments accept literal,
   enum, array, construction, static field, and static function forms
   only`.

4. Lowering per target:

   | Target | Declaration | Read |
   | --- | --- | --- |
   | TypeScript | `public static readonly name: T = new C(args);` | `Class.name` direct reference |
   | Kotlin | `val name: T = C(args)` in the object or companion object | `Class.name` direct reference |
   | Swift | `static let name: T = C(args...)` | `Class.name` direct reference |
   | Dart | `static final name: T = C(args);`, or a top-level `final` when the declaring class flattens | direct reference, module-scope under flattening |
   | Rust | `#[allow(non_upper_case_globals)] static NAME: LazyLock<T> = LazyLock::new(\|\| <construction form call sites render>);` at module scope | the dereference `&*NAME`, module-qualified from another class, with the existing move adaptation cloning when the consumer takes ownership |

   The Rust item derives nothing new: classes already carry
   `#[derive(Debug, Clone, PartialEq)]`, so the clone arm of the move
   adaptation applies. Every target constructs the value once per
   program: the TypeScript class field initializer runs once at class
   definition, the Kotlin object and companion initialize on first
   access, Swift `static let` and Dart `static final` initialize on first
   access, and `LazyLock` initializes on first dereference.

5. A construction argument that reads a `static final` field of another
   class establishes an initialization dependency between the two
   declarations. On TypeScript the generated file of the declaring class
   already imports the read class for the type reference, and the import
   executes the read class first, so the dependency holds without a new
   ordering rule. The samples pin this dependency with a test.

## Samples and tests

- `samples/boring/ConstructedStateOps.hx` graduates with the port's
  shapes: an id-like class constructed from a string literal by another
  class's static, and a policy-like class whose same-class constructed
  statics mix a payload enum reading a Float constant, a parameterless
  enum, a two-element array literal, an empty array literal, another
  class's constructed static, and a static function call returning a
  construction. Read functions expose observable results for every form.
- `samples/tests/ConstructedStateTests.hx` asserts the labels, the enum
  payload constant, both array lengths, the cross-class static text, and
  the static-function-sourced label.
- Both modules are entered in all eight generation hxml files.
- Tree assertions in `tests/ts/constructed-state.test.ts`: the
  TypeScript tree carries `static readonly` over the construction; the
  Kotlin tree carries `val name: FramePolicy = FramePolicy(`; the Swift
  tree carries `static let`; the Dart tree carries `static final`; the
  Rust tree carries `LazyLock<`, `LazyLock::new`, and the
  `#[allow(non_upper_case_globals)]` attribute, with reads rendering
  `&*`.
- Mutation checks: a `static var` field with a construction initializer
  stops generation with the feature 30 text; a final field with a static
  function call at the root stops generation with the rule 3 final-field
  text; a construction argument holding a local variable read stops
  generation with the rule 3 argument text.
