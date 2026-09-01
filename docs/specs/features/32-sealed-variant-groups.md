# Feature spec 32: Sealed variant groups

## Scope

This specification rules the declaration form the ported engine uses for a
Kotlin sealed hierarchy: a Haxe interface marked `@:sealed`, implemented by
variant classes in the same package, where one variant may be a singleton
declared as a class with no instance fields holding a `static final`
instance of itself, and the other variants are `@:dataClass` records. The
engine source carries two such hierarchies today (`RichTextLinePattern`,
`RichTextBackgroundDrawStyle`), and the layout wave adds a third
(`RepairOption`, whose variants also read shared interface properties).
Declaration structure may be produced by a build macro; the compiler
consumes the post-macro program, so macro-generated interfaces, implements
clauses, and metadata reach the emitters as ordinary declarations.

## Current state

Interface and trait emission already renders on every target: the
`FnValuesOps` sample declares `interface NameResolver` implemented by
`class BuiltInNameResolver`, and its generated trees carry the Kotlin
`interface` with `: NameResolver` on the implementing class, the Rust
`pub trait`, the Swift protocol, the TypeScript interface, and the Dart
abstract class. Three pieces are missing:

| Piece | TypeScript | Kotlin | Swift | Dart | Rust |
| --- | --- | --- | --- | --- | --- |
| `@:sealed` on the interface | unread metadata; the interface renders with no closed marker | unread metadata; the interface renders as an open `interface` | unread metadata | unread metadata | unread metadata |
| `static final instance:Self = new Self()` | stops generation with the spec 30 initializer error | same | same | same | same |
| zero-argument toString of a singleton variant | no synthesis form exists; the port keeps such variants out of the compiler by flattening each hierarchy into one class with a handwritten toString | same | same | same | same |

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Kotlin `sealed interface` for the marker | Identical runtime cost; sealed is a compile-time restriction. | One spelling per interface; the implementing classes are emitted in the same package, which is the same-package restriction Kotlin sealed requires. | No second interface form. | The generated Kotlin states the closed set the source declares. |
| Dart `sealed class` through a library with part files | Identical runtime cost. | Dart admits sealed only inside one library; the target emits one library per module, so the keyword needs a file-structure change across every module. | A part-file structure exists for one keyword. | The restriction arrives with a restructuring the rest of the output never uses. |
| Dart keeps the abstract class emission | Identical runtime cost. | The closed set is not expressible across Dart libraries; the deviation is named once in the ruling. | No new file structure. | The output matches every other interface the target emits. |
| Target-native singleton for the zero-field variant, for example Kotlin `data object` | Identical. | The compiler cannot see which class is the singleton variant without a second marker beside the declaration. | A second marker alongside the self-construction static. | Kotlin readers see `data object`; the other four targets have no such construct, so the uniformity ends at Kotlin. |
| Sanctioned self-construction static lowered per target | One construction per program; reads are direct references on every target. | The static is the single spelling of the singleton on all five targets. | No new marker; the declaration form itself carries the meaning. | Every target names the singleton `instance` inside its declaring type. |
| Bare-name toString keyed on any class with no instance fields | Identical. | A record class with no fields in Kotlin prints `Name()` with parentheses; keying on the field count alone diverges from that behavior. | None. | Two declaration shapes would print differently only by convention. |
| Bare-name toString keyed on the class carrying the self-construction static | Identical. | The singleton form is exactly the classes that carry the static. | No field-count heuristic. | The bare name matches the Kotlin `data object` text the engine goldens carry. |

## Ruling

1. `@:sealed` marks an interface. On Kotlin the interface renders as
   `sealed interface Name`; the implementing classes render unchanged and
   are emitted in the same package, which satisfies the same-package restriction
   of Kotlin sealed. On TypeScript and Swift the interface renders in its
   existing form with no marker. On Dart the abstract class form is
   unchanged; the named deviation: Dart admits `sealed` only inside one
   library, the target emits one library per module, and the closed set is
   not expressible across Dart libraries. On Rust the trait form is
   unchanged. Placing `@:sealed` on a class, an enum, or a typedef stops
   generation with `@:sealed applies to interfaces only`.

2. A `static final` field whose declared type is the declaring class,
   whose initializer is a zero-argument construction of that class, and
   whose declaring class declares no instance fields joins the
   sanctioned initializers of feature spec 30 and lowers through the
   reference-value form of spec 30 rule 1. TypeScript renders
   `public static readonly instance: NoneDrawKind = new NoneDrawKind();`.
   Kotlin renders the companion-object
   `val instance: NoneDrawKind = NoneDrawKind()`. Swift renders
   `static let instance: NoneDrawKind = NoneDrawKind()`. Dart renders
   `static final instance = NoneDrawKind();`. On Rust the field renders
   as a module static carrying `#[allow(non_upper_case_globals)]` and
   initialized by the empty-struct construction the target already emits
   for such a class, read as a direct reference. A zero-argument
   construction of a class that declares instance fields is a constructed
   static initializer of feature spec 35: the
   default-argument completion of feature spec 22 makes the zero-argument
   call legal whenever every constructor parameter holds a default, so
   the argument count alone cannot carry the singleton meaning. Such a
   field lowers per spec 35 rule 4 and its class keeps the printed form
   its marker rules give it. Any other construction form in a static
   initializer keeps the spec 30 error
   `static field initializers accept null, literal, and empty array forms only`.

3. A class carrying the sanctioned self-construction static of rule 2
   gains a synthesized zero-argument `toString` that returns the bare
   simple class name with no parentheses, on every target, in the record
   toString synthesis of feature spec 31. The synthesis keys on the
   static of rule 2, and rule 2 admits that static on a declaring class
   with no instance fields only; the `@:dataClass` marker does not apply
   to the singleton form. Field-carrying variant classes keep the
   spec 31 synthesis unchanged: the labeled `Name(field=value, ...)`
   text in parameter order. A field-carrying class whose constructor
   parameters all hold defaults therefore never takes the bare-name
   form, whatever static it declares; its zero-argument self-construction
   static is a spec 35 initializer and its printed form is the spec 31
   labeled text when it carries `@:dataClass`.

4. An interface without `@:sealed`, an implementing class outside the
   interface package, and variant classes with instance methods or shared
   interface properties keep their existing emission; this specification
   adds no restriction on variant class members beyond rules 2 and 3.

## Samples and tests

- `samples/boring/SealedVariantOps.hx` declares `@:sealed interface
  DrawKind` with three variants: `NoneDrawKind`, a class with no instance
  fields carrying
  `public static final instance:NoneDrawKind = new NoneDrawKind()` and a
  private constructor; `StripeDrawKind`, a `@:dataClass` with
  `strokeWidth` and `gapLength`; and `DotDrawKind`, a `@:dataClass` with
  `dotDiameter` and `gapLength`. `labelOf(kind:DrawKind):String` branches
  with `Std.isOfType` over the three variants and returns a fixed marker
  string per branch; `noneLabel():String` returns
  `Std.string(NoneDrawKind.instance)`.
- `samples/tests/SealedVariantTests.hx` asserts
  `Std.string(NoneDrawKind.instance) == "NoneDrawKind"`, both labeled
  variant texts in parameter order, `labelOf` over all three variants,
  and the `Std.isOfType` result of each variant against the interface and
  against a sibling variant.
- Both modules are entered in all eight generation hxml files.
- Tree assertions in `tests/ts/sealed-variants.test.ts`: the Kotlin tree
  carries `sealed interface DrawKind`, the companion `val instance`, and
  both labeled toString texts; the TypeScript tree carries
  `static readonly instance` and the bare-name return value; the Swift
  tree carries `static let instance`; the Dart tree carries
  `static final instance` on an abstract class whose kind is unchanged;
  the Rust tree carries the module static with
  `#[allow(non_upper_case_globals)]` and the bare-name string in the
  toString synthesis.
- Mutation checks: `@:sealed` on a class stops generation with
  `@:sealed applies to interfaces only`; a self-construction with
  arguments, `static final bad:NoneDrawKind = new NoneDrawKind(1);`,
  keeps the spec 30 initializer error text.
- A field-carrying `@:dataClass` sample with all-default coalescing
  constructor parameters and a zero-argument self-construction static,
  the `AutoSpacePolicy` shape of the port, appears beside the sealed
  samples: its tests assert the spec 31 labeled printed form for the
  constructed default and for a read of the static, and its tree
  assertions pin the spec 35 lowering (the Rust `LazyLock` static, the
  Kotlin companion `val Default = ...`) with no bare-name toString
  anywhere; the field-less singleton of this specification keeps its
  bare-name form in the same trees.
