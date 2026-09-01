# Feature spec 28: Enum value queries

## Scope

This specification rules the translation of the three enum queries of the
Haxe `Type` module over value enumerations: `Type.allEnums`, `Type.enumConstructor`,
and `Type.createEnum`. The mechanism is a compile-time expansion in the typed
common layer plus per-target artifacts, the same layer and the same dual hookup
as the default argument expansion of `docs/specs/features/22-default-argument-expansion.md`
and the collection pipeline expansion of `docs/specs/macros/01-functional-idiom-expansion.md`.
The value enumeration declaration forms the queries build on are ruled by the
parameterless amendment of `docs/specs/features/01-enums-and-pattern-matching.md`.

This specification rules all five source targets (ts, kotlin, swift, dart,
rust) together: one feature, five lowerings, no target left with a silent
divergence. The f32 configurations inherit the same rules; they differ only in float
width.

The downstream motivation is the engine port. The handwritten engine tests
consume enumeration, name lookup, and name reads on every target
(`engine/src/commonTest/kotlin/org/tiqian/core/EastAsianSpacingCoverageTest.kt`
iterates `UnicodeScriptEvidence.entries` and reads `.name`), and the ported
Haxe source needs the same operations with one spelling. The reflection ban
(`V03 Reflection`, `docs/specs/style/01-haxe-style-standard.md`) today rejects
every member of `Type`, so the sanctioned subset needs this specification
before any of the three calls compiles.

## Haxe construct

The three calls and their Haxe contracts, quoted from the standard library
`Type.hx`:

- `Type.allEnums(e)` returns every constructor of `e` that requires no
  arguments, in constructor declaration order.
- `Type.enumConstructor(v)` returns the constructor name of `v` as a String,
  without constructor arguments.
- `Type.createEnum(e, constr, ?params)` creates the constructor named `constr`.
  The library leaves an unknown name unspecified.

```haxe
enum FloatWidth {
	F64;
	F32;
	F16;
}

final all:Array<FloatWidth> = Type.allEnums(FloatWidth);
final count:Int = all.length;
for (index in 0...count) {
	final width = all[index];
	final name:String = Type.enumConstructor(width);
	final back:Null<FloatWidth> = Type.createEnum(FloatWidth, name);
}
```

The style standard (`V01 IteratorLoop`) requires indexed range loops over
arrays, so iteration reaches the compiler as a count read plus index reads,
through one alias local or through direct calls (`Type.allEnums(E).length`,
`Type.allEnums(E)[i]`).

## Current translations

`V03 Reflection` rejects every `Type.*` static call before any target sees it
(`src/Intercept.hx`, `REFLECTION_ROOTS`, rejection text
`` `Type.x has no translation with identical behavior` ``). No target compiler
contains any enum query support; a full-source grep finds `Type.enumConstructor`
only in the Haxe-side test collector (`src/TestCollector.hx:210,257`), which
generates the Haxe oracle runner and never compiles through a target.

Per-target value enumeration support today, after the parameterless amendment
of `docs/specs/features/01-enums-and-pattern-matching.md`:

| Capability | TS | Kotlin | Swift | Dart | Rust |
| --- | --- | --- | --- | --- | --- |
| Every-member collection | none | `E.entries` (library) | `E.allCases` (library) | `E.values` (library) | none |
| Constructor name | `w.kind` | `w.name` | `w.rawValue` | `w.label` | none |
| Name lookup | none | `E.valueOf(s)`, throws on miss | `E(rawValue: s)`, nil on miss | none | none |

## Candidate translations

**C1: runtime residents.** A runtime module per target implements the three
calls against a registry of enum types: every enumeration registers its
members at startup and the functions consult the registry.

- performance: every query pays a lookup into a registry structure; the
  registry itself is runtime state constructed at startup.
- ambiguity: the registry shape is a compiler invention on every target.
- redundancy: five registry implementations for data the compiler already
  holds at compile time.
- readability: the generated call sites read as reflection calls.

**C2: compile-time site expansion plus per-target artifacts (chosen).** The
common layer recognizes the three calls, checks their argument forms, records
which artifacts each enumeration needs, and replaces the calls with marker
expressions; every target renders the markers from data the compiler already
holds, emitting generated artifacts beside the declaration on demand.

- performance: every query reads a constant, a field, or a language member;
  each evaluation allocates nothing; each artifact initializes once.
- ambiguity: the argument forms are checked at compile time with named errors.
- redundancy: each artifact is emitted once per enumeration and only when the
  program queries that enumeration.
- readability: call sites read as member access in the target's own spelling.

**C3: a source-side macro library the Haxe program writes itself.** The engine
port carries its own query macros and expands them before boring runs.

- performance: equivalent after expansion.
- ambiguity: every consumer re-implements the table; five targets verify five
  inventions.
- redundancy: every consumer carries its own expansion; the compiler holds none of it.
- readability: the Haxe source calls a macro where a standard library call
  exists.

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| C1 runtime residents | Registry lookup per query and registry state at startup violate the cost floor for data known at compile time. | The registry is a new invention per target with no language anchor. | Five registry implementations of one table. | Reads as reflection. |
| C2 site expansion plus artifacts | Zero allocation per evaluation; once-only initialization; literal bounds in loops. | Argument forms get compile-time named errors; miss behavior is uniform. | One artifact per queried enumeration, generated once. | Sites read as native member access on every target. |
| C3 source macros | Same post-expansion cost, paid by every consumer separately. | Five consumers can expand five different ways. | The table is duplicated per consumer. | Standard library calls become macro calls in source. |

## Ruling

1. **Sanctioned calls.** `Type.allEnums`, `Type.enumConstructor`, and
   `Type.createEnum` are the sanctioned `Type` members. Every other `Type`
   member stays rejected by `V03 Reflection`; the style row text changes to
   name the three exceptions. Principle 2: the restriction keeps its provided
   replacement in the same change.

2. **Argument forms, with named errors.** `Type.allEnums` accepts a direct
   enum type reference; any other argument form stops the compilation with
   `Type.allEnums accepts an enum type reference only`. `Type.enumConstructor`
   accepts an operand whose type is a value enumeration; otherwise
   `Type.enumConstructor accepts parameterless enum values only`.
   `Type.createEnum` accepts the two-argument form (type reference, string);
   the third `params` argument stops the compilation with
   `Type.createEnum accepts the two-argument form only`. Any argument of the
   three calls whose enum declares a constructor with parameters stops the
   compilation with `enum queries accept enums without constructor parameters
   only`; a program that needs enumeration of a payload enum splits its
   payload-less constructors into a value enumeration, which is the sanctioned
   path.

3. **Miss semantics.** `Type.createEnum(E, s)` with a name no constructor
   declares returns the target's empty value (`null` in TypeScript, Kotlin,
   and Dart; `nil` in Swift; `None` in Rust). Haxe leaves the case
   unspecified; this specification defines it, and the consistency run asserts
   it on every target (principle 1: the meaning is defined over the names,
   with one behavior on all five targets).

4. **Per-target lowerings.** The markers render as follows.

   | Query | TypeScript | Kotlin | Swift | Dart | Rust |
   | --- | --- | --- | --- | --- | --- |
   | `Type.allEnums(E)` (collection) | `E_ALL` | `E.entries` | `E.allCases` | `E.values` | `E::ALL` |
   | `.length` of the collection | literal count | literal count | literal count | literal count | literal count |
   | `c[i]` of the collection | `E_ALL[i]` | `E.entries[i]` | `E.allCases[i]` | `E.values[i]` | `E::ALL[i]` |
   | `Type.enumConstructor(w)` | `w.kind` | `w.name` | `w.rawValue` | `w.label` | `w.name()` |
   | `Type.createEnum(E, s)` | `eOfName(s)` | `E.entries.firstOrNull { it.name == s }` | `E(rawValue: s)` | `eOfName(s)` | `E::from_name(s)` |

   For `FloatWidth`, `E_ALL` is `FLOAT_WIDTH_ALL` and `eOfName` is
   `floatWidthOfName`.

5. **Sanctioned positions for the collection.** The `Type.allEnums` expansion
   is legal in exactly three shapes: a `.length` read, an index read, and one
   local whose single initializer is the call, feeding those two reads. Any
   other position stops the compilation with
   `Type.allEnums expands in length and index positions only`. Enumeration is
   count plus element access; a program that needs to pass the members around
   references the constructors directly. Principle 3: the restriction holds
   the query at its inherent cost and keeps Rust free of a vector clone.

6. **Literal count folding.** A `.length` read of the collection renders the
   member count as a literal on every target, in every expression position.
   An indexed range loop over the collection therefore renders with the
   literal bound, and the index reads render against the collection:

   ```ts
   for (let index = 0; index < 3; index += 1) { const width = FLOAT_WIDTH_ALL[index]; }
   ```

   ```kotlin
   for (index in 0 until 3) { val width = FloatWidth.entries[index] }
   ```

   ```swift
   for index in stride(from: 0, to: 3, by: 1) { let width = FloatWidth.allCases[Int(index)] }
   ```

   ```dart
   for (var index = 0; index < 3; index++) { final width = FloatWidth.values[index]; }
   ```

   ```rust
   for index in 0..3 { let width = FloatWidth::ALL[index]; }
   ```

   The count literal is the constructor count of the enum declaration, known
   at compile time. The existing TypeScript length hoist
   (`features/09 LengthHoist`, `src/reflaxe/ts/tscompiler/TsExpr.hx`) folds a
   literal bound by short-circuiting the hoist: a literal needs no hoisted
   read. Principle 3: repeated positional access gets constant-time indexing
   with a bound computed at compile time.

7. **Generated artifacts, on demand.** Each enumeration that a program queries
   gets its artifacts emitted beside its declaration in the same module, once
   per program: TypeScript gets `FLOAT_WIDTH_ALL`, one array of the record
   members wrapped in `Object.freeze(`, and `floatWidthOfName(name: string):
   FloatWidth | null`, a chain of name comparisons returning record members;
   Rust gets `impl FloatWidth { pub const ALL: [FloatWidth; 3] = [...]; }`,
   `pub fn name(&self) -> &'static str`, and
   `pub fn from_name(name: &str) -> Option<FloatWidth>`; Dart gets the
   top-level function `floatWidthOfName(String name): FloatWidth?` as a chain
   of label comparisons returning constants. Kotlin and Swift need no
   artifacts beyond language members (`entries`; `allCases` and `rawValue`
   arrive with the conformances the parameterless amendment of `features/01`
   adds). An enumeration no program queries emits no artifact, so Rust
   reports no unused constant and TypeScript ships no unused export. The name
   and lookup artifacts of Rust are emitted when `Type.enumConstructor` or
   `Type.createEnum` queries that enumeration, including query sites that
   appear without a collection query.

8. **Costs.** Every query evaluation allocates nothing on every target: the
   collection is a shared constant, the name is a field or language member
   read, and the lookup compares strings and returns a constant. Each
   artifact initializes at most once per process (TypeScript at module
   evaluation; Kotlin and Dart during type initialization; Swift on first
   `allCases` access; Rust at compile time). Constructor construction sites
   allocate nothing under the parameterless amendment of `features/01`, so a
   query result feeds comparisons and switches with no intermediate object.

9. **Equality is unchanged.** Comparisons keep the rules of
   `features/01`: TypeScript compares the `kind` tag, the other targets use
   their native equality. A consumer can still write a TypeScript object
   literal that satisfies a variant interface; tag comparison assigns it to
   the right constructor where identity comparison would misclassify it
   (principle 1).

10. **Implementation shape.** A common-layer pass records, per enum type,
    which queries appear (collection, name, lookup) and rewrites the calls
    into marker expressions, following the registry pattern of
    `src/DefaultArgExpander.hx`; the pass runs from the shared hookup in
    `src/Intercept.hx` (`walkClassFields`) and from every target expression
    entry, because every target re-runs the passes on its own view. Each target
    renders the markers in its `*Expr` compiler and each `enumDecl` emits the
    artifacts its target needs from the registry. The `V03` rejection in
    `src/Intercept.hx` (`REFLECTION_ROOTS`) admits the three members by name
    before the wholesale rejection.

This ruling exercises principle 1 (miss behavior and name strings are defined
over constructor names), principle 2 (the reflection restriction keeps a
sanctioned subset), and principle 3 (constant-time queries at constant cost,
literal bounds, once-only initialization).

## Test hooks

- `samples/boring/EnumQueriesOps.hx`: functions over `FloatWidth` and a
  second value enumeration covering, on all five targets: collection order
  equals declaration order; every `Type.enumConstructor` result equals the
  constructor name; `Type.createEnum` round-trips every constructor through
  its name; an unknown name returns the target empty value, asserted by
  rendering the outcome as a string the consistency run compares; count reads
  through an alias local and through the direct call; indexed iteration over
  the collection through an alias local; lookup results compare equal to the
  constructors they name.
- `samples/tests/EnumQueriesTests.hx` with `@:test` functions over the ops
  module; both modules are entered in all eight generation hxml files (ts,
  kotlin, kotlin-f32, rust, rust-f32, swift, swift-f32, dart).
- `samples/tests/EnumQueriesProbes.hx`: the named errors of ruling 2 and
  ruling 5 as ordinary statics, following the `ValueRecordProbes` pattern.
- Tree assertions in `tests/ts/enum-queries.test.ts`: per target, the generated
  module contains the artifacts of ruling 7 (TypeScript: the
  `Object.freeze(`-wrapped record of the parameterless amendment plus
  `FLOAT_WIDTH_ALL` and the comparison chain of `floatWidthOfName`; Kotlin:
  `enum class` and `entries`; Swift: `String`, `CaseIterable`, and the raw
  values; Dart: the enhanced enum with `label` and the lookup function; Rust:
  the `impl` block with `ALL`, `name`, and `from_name`), the loop bound is
  the literal count, and no generated tree contains a `Type.` static call.
- Coverage: `bun run gen:ts && bun run gen:kotlin && bun run gen:kotlin-f32 &&
  bun run gen:rust && bun run gen:rust-f32 && bun run gen:swift && bun run
  gen:swift-f32 && bun run gen:dart`, then `bun run test && bun run test:haxe
  && bun run test:kotlin && bun run test:rust && bun run test:swift && bun
  run test:dart` and the remaining steps of `bun run verify`. The consistency
  manager (`docs/specs/features/19-testing.md`) must report the same test
  count, identifiers, verdicts, and failure bytes across kotlin (baseline),
  haxe, ts, rust, swift, and dart.
- The mutation checks for this feature live in the dispatch task file and are
  part of the completion criteria.
