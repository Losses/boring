# Feature spec 27: class members and records

## Scope

A Haxe class declaration carries five facts about its members that the
five source targets do not lower uniformly:

1. **Visibility of instance fields.** Every Rust stored instance field follows
   the Haxe field declaration: `public` becomes `pub`, while a non-public
   declaration becomes `pub(crate)`. This exposes public data to downstream
   users while retaining crate-local access for private lowering and tests.
2. **Visibility of constructor-parameter fields.** The constructor
   parameter that holds a field states the field's visibility through the
   field declaration. TS and Rust follow `field.isPublic`; Kotlin renders
   every parameter-held field `private`; Swift renders every stored
   property without an access modifier; Dart renders every field without
   the underscore prefix, so a private field becomes public on three
   targets and a public field becomes private on one.
3. **Constructor bodies.** The statements of `new` run once per
   construction; validation lives there. TS renders them into the
   `constructor`, Swift into `init`, Dart into the constructor body after
   the initializer list. Kotlin renders them in an `init` block after
   property declarations, including lowered comprehension and pipeline
   statements. Rust lowers constructor statements before its `Self` literal;
   that lowering is part of this parity change, while the broader Rust
   constructor proposal remains separate.
3. **Getter-only properties.** A field declared `var x(get, never)` with a
   `get_x` accessor function states a computed read with no storage. No
   target handles the declaration: today the field flows into the field
   list and lowers as stored storage that no code assigns (Kotlin renders
   `= 0` for an Int, Rust builds a `Default::default()` slot), so the
   property reads a value that was never computed.
4. **Records.** A class marked `@:dataClass` states record semantics:
   structural equality, copy-with-override, and the printed form
   `Name(field=value, ...)`. Anonymous records already have this through
   the call-site macros of `std.RecordCopy` (macros/03 record copy). Class
   records have nothing: no equality, no copy, no printed form on any
   target.

The downstream motivation is the engine port: the port embeds generated
core classes into a module whose remaining sources are hand-written
Kotlin, and those sources read fields with property syntax, compare
records with `==`, copy them with `.copy(range = ...)`, and match printed
records such as `TextRange(start=0, end=1)` against recorded expectation
files. The printed form belongs to the behavior contract.

This specification rules all five source targets (ts, kotlin, swift,
dart, rust) together: one feature, five lowerings, no target left with a
silent divergence. The f32 configurations inherit the same rules; they differ only
in float width.

## Haxe construct

```haxe
@:dataClass
class TextRange {
	public final start:Int;
	public final end:Int;

	public function new(start:Int, end:Int) {
		if(start > end) throw new VectorError(StartGreaterThanEnd);
		this.start = start;
		this.end = end;
	}

	public var length(get, never):Int;

	public function get_length():Int {
		return end - start;
	}
}
```

Record operations reach the class through the call-site macros, never
through generated members:

```haxe
final shifted = RecordCopy.copy(range, {start = 1});
final same = RecordEq.eq(range, other);
final printed = RecordStr.str(range); // TextRange(start=0, end=1)
```

## Current translations

| Feature | TS | Kotlin | Swift | Dart | Rust |
| --- | --- | --- | --- | --- | --- |
| instance-field visibility | n/a | n/a | n/a | n/a | `pub` if `isPublic`, otherwise `pub(crate)` |
| ctor-param field visibility | follows `isPublic` | always `private` | never `private` | never `_`-prefixed | follows `isPublic` |
| constructor body | rendered | dropped | rendered | rendered | dropped |
| `var x(get, never)` | stored field, never assigned | stored field `= 0` | stored property | stored field | struct field, `Default::default()` |
| `@:dataClass` | n/a | n/a | n/a | n/a | n/a |

## Candidate translations

### Record operations: call-site macros vs generated members

**C1: call-site macros (the `std.RecordCopy` mechanism, extended).**
`RecordCopy.copy` accepts class records and expands to a constructor call
with the overridden fields; `RecordEq.eq` and `RecordStr.str` accept both
record kinds and expand to a field-wise comparison and a concatenation of
`Name(field=value, ...)`.

- performance: the expansion is plain construction, comparison, and
  concatenation; stage 1 and every target run the same lowered code.
- ambiguity: one expansion exists; the macro reads the field list of the
  receiver type, so the record's shape lives in one place.
- redundancy: three macros total, shared by anonymous and class records.
- readability: call sites name the operation (`RecordEq.eq`), the way the
  anonymous-record samples already do.

**C2: the compiler synthesizes members per target.** `@:dataClass` makes
each target emit `copy`/`equals`/`toString` in the target's own member
syntax.

- performance: as C1.
- ambiguity: five syntheses must agree on the printed form and the
  comparison order; stage 1 has no compiler and needs a synthesis of its
  own, raising the count to six.
- redundancy: one implementation per target.
- readability: `record.copy(...)` reads as member syntax on every target.

**C3: hand-written members in each record class.**

- performance: as C1.
- ambiguity: none.
- redundancy: three members per record class; the port's record count
  makes this repetition the dominant cost of the source tree.
- readability: as C2.

### `@:dataClass` on the compiler side

**K1: Kotlin renders `data class` and validates the marker.** The native
synthesis gives the hand-written surrounding module `==`, `.copy(field = ...)`,
and the printed form with no generated text.

**K2: every target renders its native record construct.** Swift, Dart,
and TS have no derivation for classes; each would synthesize members,
which candidate C1 already removes the need for. Rust has derives
(`PartialEq`, `Clone`) but no named-argument copy; the `Option`-parametered
`copy` it could synthesize duplicates what `RecordCopy.copy` expands to.

**K3: no compiler-side effect; macros only.** The hand-written Kotlin
module cannot reach structural `==` or native `.copy(field = ...)` through
generated members, so the port context fails.

### Constructor-parameter field visibility

**V1: every target follows the field declaration.** Kotlin renders `val`
/ `var` for public fields and `private val` / `private var` for private
ones; Swift renders `private let` / `private var` for private fields;
Dart renders the `_`-prefixed name for private fields; TS and Rust keep
their current lowering.

- performance: the access modifier and the name prefix affect name
  resolution only; the instruction count is unchanged.
- ambiguity: the declaration is the single source of visibility on every
  target.
- redundancy: none.
- readability: generated members state the visibility the source states.

**V2: current state on the three divergent targets.**

- performance: none.
- ambiguity: three targets state visibility the source does not state,
  one states the opposite of it.
- redundancy: none.
- readability: a private field reads as public (or the reverse) in the
  generated tree.

### Constructor body

**B1: every target renders the statements.** Kotlin wraps them in one
`init` block as the first member of the class body; Rust renders them
before the `Self { ... }` literal inside `fn new`, and a constructor whose
body throws returns `Result<Self, E>` through the existing fallibility
machinery. TS, Swift, and Dart keep their current rendering.

- performance: the statements run once per construction, as the source
  states; validation is a branch and a throw.
- ambiguity: construction semantics live in the generated constructor
  path on every target.
- redundancy: on Kotlin the `this.f = f` self-assignments drop out (the
  primary-constructor parameter carries them); on Rust they are the
  struct literal itself.
- readability: the generated constructor reads as the source constructor.

**B2: Kotlin and Rust keep dropping the body.**

- performance: none.
- ambiguity: the source states construction invariants that the
  generated class does not enforce; the two disagree silently.
- redundancy: none.
- readability: the omission is invisible in the output.

### Getter-only property

**P1: no storage; the target's property syntax beside the accessor.**
Kotlin renders `val x: T get() = get_x()`; TS renders
`get x(): T { return this.get_x(); }`; Swift renders `var x: T { get_x() }`;
Dart renders `T get x => get_x();`. Rust has no property syntax: the
`get_x()` method is the lowering, and the declaration contributes no
storage (today it contributes a wrong `Default::default()` slot).

- performance: the facade is one delegating call, inlined by the target
  compiler; the value is computed per read exactly as the source computes
  it. Rust pays nothing and stores nothing.
- ambiguity: the property names the computation the `get_x` function
  states.
- redundancy: one facade line per property.
- readability: consumers use property syntax for computed and stored
  values alike on four targets, and method syntax on Rust, which is the
  idiom of each language.

**P2: keep rendering stored fields.** The current state.

- performance: construction allocates a slot no code writes.
- ambiguity: the generated class states storage the source does not.
- redundancy: one slot per property.
- readability: `record.length` reads a value that was never computed.

**P3: store the computed value at construction.**

- performance: construction pays for every property read or not.
- ambiguity: the stored copy can diverge from the computation; mutation
  of the inputs after construction leaves a stale value.
- redundancy: a second representation of a derivable value.
- readability: the class states storage the source does not.

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| records C1 call-site macros | plain lowered code | one expansion, one shape source | three macros shared by both record kinds | operation named at the call site |
| records C2 synthesized members | as C1 | six agreements on text and order | one implementation per target | member syntax |
| records C3 hand-written | as C1 | none | three members per class | as C2 |
| `@:dataClass` K1 Kotlin `data class` | native synthesis | marker states recordhood | one prefix | hand-written Kotlin uses `==` and `.copy` |
| `@:dataClass` K2 native per target | as K1 where a construct exists | five printings to keep identical | five syntheses | member syntax varies |
| `@:dataClass` K3 macros only | as K1 | none added | none added | port context fails |
| visibility V1 follow declaration | name resolution only | one source of visibility | none | states what the source states |
| visibility V2 current | none | three targets misstate | none | misstates |
| body B1 render on every target | once per construction | same place as the source | self-assignments folded | as the source |
| body B2 drop on two targets | none | silent disagreement | none | invisible omission |
| property P1 facade / method | one delegating call | property names the function | one line | each language's idiom |
| property P2 stored, unassigned | dead slot | undeclared storage | one slot per property | reads an unwritten value |
| property P3 stored at construction | pays for unread properties | stale-value divergence | second representation | undeclared storage |

## Ruling

1. **Record operations are call-site macros.** `std.RecordCopy.copy`
   accepts class records whose type carries `@:dataClass` and expands to
   a constructor call whose arguments follow the constructor parameter
   order, each argument the override or the receiver's field of that
   parameter. `std.RecordEq.eq(a, b)` expands to a comparison of the
   constructor parameter fields with `==`, joined by `&&`, in
   constructor parameter order; `std.RecordStr.str(r)` expands to a
   concatenation producing `Name(field=value, ...)` with `, ` between
   fields. For anonymous records the three operate on the fields in
   declaration order and print `{ field=value, ... }`. The class-record
   expansions cover exactly the constructor parameters, matching what the
   Kotlin synthesis of ruling 2 compares, copies, and prints; a class
   record whose constructor parameters are not all held by fields stops
   the compilation at the macro with `record copy requires every
   constructor parameter to be a class field`. All three macros reject
   non-record receivers with a fatal error naming the receiver type. No
   target synthesizes record members.
2. **`@:dataClass` renders `data class` on Kotlin and is inert
   elsewhere.** On Kotlin the class declaration gains the `data` prefix;
   the native synthesis supplies `==`, `.copy(field = ...)`, `hashCode`,
   and the printed form to hand-written surrounding code. Kotlin
   validates the marker: at least one constructor parameter, and every
   constructor parameter held by a class field; a violation stops the
   compilation with `@:dataClass requires at least one constructor
   parameter` or `@:dataClass requires every constructor parameter to be
   a class field`. The printed form of the Kotlin synthesis
   (`Name(field=value, ...)`) and `RecordStr.str` produce the same text.
   On TS, Swift, Dart, and Rust the marker changes nothing; record
   behavior on those targets comes from the macros of ruling 1.
3. **Constructor-parameter field visibility follows the field
   declaration on every target.** Kotlin renders a parameter held by a
   `public final` field `val`, by a `public` mutable field `var`, by a
   private field `private val` / `private var`, and a parameter with no
   field as a bare parameter. Swift prefixes `private` on stored
   properties of private fields. Dart renders private fields with the
   `_`-prefixed name at the declaration and at every access site; a
   private-field access from a module other than the declaring module and
   its subclasses within it has no lowering and stops the compilation.
   TS and Rust keep their current lowering.
4. **Constructor bodies render on every target.** Kotlin renders the
   statements of `new` in source order into one `init { }` after the
   stored-property declarations, before the functions; Kotlin requires
   the declarations to precede the block's assignments. The block drops
   `this.f = f` where `f` is a
   primary-constructor field; an assignment to a primary-constructor
   field from any other expression stops the compilation with
   `constructor assigns F from another expression; assign the constructor
   parameter F directly`. The single exception is the coalescing default of
   `docs/specs/features/22-default-argument-expansion.md`: an assignment of
   exactly the shape `this.f = f == null ? E : f` over a nullable-optional
   constructor parameter is that specification's sanctioned default and
   lowers by its per-target products, with the parameter staying the primary
   field. An assignment to a field the constructor does
   not receive as a parameter is that field's initialization: the
   statement renders in the init block and the field declaration carries
   no initializer. Rust renders the
   statements before the `Self { ... }` literal; a constructor whose body
   can throw returns `Result<Self, E>` under the existing fallibility
   rules, and construction sites lower accordingly. TS, Swift, and Dart
   keep their current rendering.
5. **Getter-only properties render no storage.** A field declared
   `var x(get, never)` with the standard read accessor renders beside the
   `get_x` function: the Kotlin facade `val x: T get() = get_x()`, the TS
   accessor `get x(): T { return this.get_x(); }`, the Swift computed
   property `var x: T { get_x() }`, and the Dart getter
   `T get x => get_x();`. On Rust the `get_x()` method is the lowering
   and the declaration renders nothing. Custom accessor names and `set`
   accessors raise no error and render no facade; they await a consumer.
6. **No other construct moves.** Interfaces, companions, statics, enums,
   exception folding, anonymous records, and the test apparatus keep
   their current lowering. A test class carries `@:test` functions and
   nothing else; a field or function without `@:test` stops the
   compilation with `test class T carries a non-test member F; shared
   logic belongs in an ordinary class`, whose member lowering every
   target already renders.
7. **A zero-argument `toString` method overrides `Any` on Kotlin.** Haxe
   models no root type, so nothing in the typed tree marks the method as
   an override; the Kotlin rendering of a zero-argument `toString`
   carries the `override` modifier. The other targets render the method
   unchanged, and no other method name receives the modifier.

## Test hooks

- `samples/boring/ValueRecord.hx`: a `@:dataClass` class with public
  `final` fields, a validating constructor that throws on two invariants,
  and a getter-only property. `samples/boring/PrivateHolder.hx`: a public
  and a private constructor-parameter field, the private one read inside
  the class only. Both are entered with `tests.ValueRecordTests` in the
  entry lists of all eight generation hxml files (ts, kotlin, kotlin-f32,
  rust, rust-f32, swift, swift-f32, dart).
- `samples/std/RecordCopy.hx`, `samples/std/RecordEq.hx`,
  `samples/std/RecordStr.hx`: the three macros, shared by the anonymous
  and class record samples. `samples/tests/ValueRecordProbes.hx` holds
  the rejection probe as ordinary statics, per ruling 6.
- `tests/ValueRecordTests.hx` asserts through the macros: property reads,
  copy with no override / one override / reordered overrides, structural
  equality both ways, the printed form `ValueRecord(start=..., end=...)`,
  and that construction throws on each violated invariant. The existing
  `BinaryReader` and `BinaryWriter` constructors exercise the
  field-initialization arm of ruling 4 on every target.
- Regeneration diffs show per target: the Kotlin `data class` prefix, the
  Kotlin `init` block and property facade, the Swift `private` stored
  property and computed property, the Dart `_`-prefixed private field and
  getter, the TS accessor, and the Rust constructor body with
  `Result<Self, E>`.
- Coverage: `bun run gen:ts && bun run gen:kotlin && bun run gen:kotlin-f32
  && bun run gen:rust && bun run gen:rust-f32 && bun run gen:swift &&
  bun run gen:swift-f32 && bun run gen:dart`, then
  `bun run test && bun run test:haxe && bun run test:kotlin &&
  bun run test:rust && bun run test:swift && bun run test:dart` and the
  remaining steps of `bun run verify`.
