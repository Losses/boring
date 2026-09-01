# Standard library spec 12: Std.string

## Scope

This specification rules the translation of `Std.string` on all five source
targets (ts, kotlin, swift, dart, rust). The function converts one operand to
its string form; the ported engine source calls it inside string
concatenation when rendering diagnostic text
(`engine-haxe/src/org/tiqian/core/EastAsianSpacingEdges.hx`, the `toString`
functions spell `"EastAsianSpacingEdges(leading=" + Std.string(leading) +
...)`), and renders whole collections the same way
(`TextStyle.hx` and `RubySpan.hx` stringify a `ReadOnlyArray<String>` of
font families, `CoreLayoutQueriesGapsTest.hx` stringifies an `Array<Rect>`).
The f32 configurations inherit the same rules; they differ only in float width.

The value enumeration forms the conversion relies on are ruled by the
parameterless amendment of `docs/specs/features/01-enums-and-pattern-matching.md`;
the constructor-name reads are the same reads as
`docs/specs/features/28-enum-value-queries.md` rules for `Type.enumConstructor`.

## Contract

Haxe `Std.string(value)` returns the string form of `value`. This
specification defines the conversion over the operand's content (principle 1):

- A `String` operand returns itself.
- An `Int` operand returns the decimal form.
- A `Float` operand returns the shortest form that reads back as the same
  value; the precision domain follows `docs/specs/features/23-float-precision-switch.md`,
  and the f32 configurations format the f32 value.
- A `Bool` operand returns `true` or `false`.
- A value enumeration operand returns the constructor name spelled in Haxe
  source (`Std.string(FloatWidth.F64)` is `"F64"` on every target).
- An `Array<T>` operand, and a `ReadOnlyArray<T>` operand (the abstract of
  `samples/std/ReadOnlyArray.hx` erases to `Array<T>`), renders `[` + the
  element forms joined with `", "` + `]` where every element type `T` is one
  of the operand types above; an empty array renders `[]`; a nested array
  element recurses through this rule (`[[1, 2], [3]]`). The separator is the
  form the Kotlin baseline renders for a list, which the ported engine
  compares its traces against; the native Haxe renderer joins with `","`, so
  the array rows of the Haxe target assert through the `boring_oracle`
  conditional, the pattern the unknown-name probe of
  `features/28-enum-value-queries.md` established, and the divergence is
  recorded in the sample header.

An operand of any other type (a class instance, a structure, a payload enum
value, a nullable), an array whose element type falls outside the domain,
and an operand typed as a type parameter stop the compilation with
`Std.string accepts scalars, parameterless enum values, and arrays of them
only`. The sanctioned path for other values is calling `toString` in the
Haxe source, which the explicit override rendering of
`samples/boring/ToStringOps.hx` covers, and handling nulls with an explicit
check in the source. Nullable operands are rejected on every target: the
targets render a nullable with their own spelling (`null`, `nil`, `None`),
and a uniform rejection costs less than five spellings of a nullable render
(principle 3, cost symmetry).

## Current translations

| Target | State |
| --- | --- |
| TypeScript | `Std.string` renders `String(x)` through the static reference router (`TsExpr.hx`, `case "Std"`). Scalars convert; an enum operand renders the object form and prints `[object Object]`. |
| Kotlin | No lowering exists; the call passes through as an unresolved `Std.string(...)` reference (the engine gap). String concatenation wraps a non-string left operand with `.toString()` (`KotlinExpr.hx`, the `OpAdd` arm). |
| Swift | The call site renders `String(x)` (`SwiftExpr.hx`, the `Std` call arm). Scalars convert; an enum operand prints the target's lower-cased case name. |
| Dart | The call site renders `'${x}'` (`DartExpr.hx`, the `Std` call arm). Scalars convert; an enum operand prints the instance form of the sealed class. |
| Rust | No lowering exists for the call. |

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Per-target conversion calls (`String`, `.toString()`, interpolation, `to_string`) at the call site | One conversion call, or none inside concatenation where the target coerces. | The operand domain is checked at compile time with one named error on every target. | No runtime helper exists to keep in sync. | Sites read as the target's own conversion. |
| A runtime stringify resident | Every call pays a helper dispatch for a conversion every target performs natively. | The helper invents its own rendering rules per target. | Five helpers for one conversion. | Sites read as a library call the target already spells shorter. |
| Source-side `Std.string` avoidance in the port | No compiler work; the port re-spells every conversion by hand. | Haxe typing rules require `Std.string` for some operands, so the port cannot avoid it everywhere. | Every consumer re-decides the rendering. | Port source stops using the standard library function. |
| Array operand lowered at the call site (one single-pass builder per target) | One growable accumulator and one index loop; zero per-element closure calls and zero intermediate collections; Kotlin and Rust format scalars into the buffer without building an element string. | The element domain is checked with the same named error; the separator and brackets are ruled, so no target renders its own native array form. | The element rendering reuses the scalar and enumeration lowerings of rules 2 and 3; the compiler holds no second element renderer. | Sites keep writing `Std.string(xs)`. |
| Port-side hand loops for every collection render | No compiler work. | Every consumer re-decides the separator and the brackets. | The loop shape repeats at every call site of the ported engine. | Port source drifts from the shape of the Kotlin original. |

## Ruling

1. `Std.string` lowers at its call site on every target, in two positions.

2. **Inside string concatenation** (an `OpAdd` chain with at least one string
   operand), the operand renders bare where the target coerces, and renders
   its conversion where it does not:

   | Operand | TypeScript | Kotlin | Swift | Dart | Rust |
   | --- | --- | --- | --- | --- | --- |
   | String | bare | bare | bare | bare | bare |
   | Int, Float, Bool | bare (the `+` coerces) | bare (the `+` invokes `toString()`) | `\(...)` interpolation | `'${...}'` interpolation | the format argument the concat renders |
   | value enumeration | `w.kind` | `w` (the enum `toString()` returns the name) | `w.rawValue` | `w.label` | `w.name()` |

   The enumeration reads are the constructor-name reads of
   `features/28-enum-value-queries.md`; a bare enum operand would print the
   target's own spelling (an object form in TypeScript, a lower-cased case
   name in Swift, an instance form in Dart), so the name read is what keeps
   the result defined over the constructor name (principle 1).

3. **Standalone calls** render the target conversion:

   | Operand | TypeScript | Kotlin | Swift | Dart | Rust |
   | --- | --- | --- | --- | --- | --- |
   | String | `x` | `x` | `x` | `x` | `x.clone()` or the borrow the concat already renders |
   | Int, Float, Bool | `String(x)` | `x.toString()` | `String(x)` | `'${x}'` | `x.to_string()` |
   | value enumeration | `w.kind` | `w.name` | `w.rawValue` | `w.label` | `w.name().to_string()` |

4. The operand domain check runs where the operand type is known, in every
   target's `Std.string` arm, with the one named error of the Contract
   section. The check and the lowering ship in one change on all five targets
   (principle 2: the restriction names its provided replacement, the source
   `toString` call, in the same specification).

5. Every conversion allocates at most the returned string; no intermediate
   object or helper call exists on any target. The name reads of enumeration
   operands return a constant string on every target.

6. An array operand renders on every target with one single-pass builder: a
   hoisted length, an index loop, and one growable string accumulator. The
   rendering is the same expression in the concatenation and the standalone
   position:

   | Target | rendering of `Std.string(xs)` |
   | --- | --- |
   | TypeScript | `(() => { let out = "["; const n = xs.length; for (let i = 0; i < n; i += 1) { if (i > 0) { out += ", "; } out += <element>; } out += "]"; return out; })()` |
   | Kotlin | `run { val sb = StringBuilder(); sb.append('['); val n = xs.size; var i = 0; while (i < n) { if (i > 0) { sb.append(", "); } sb.append(<element>); i += 1; }; sb.append(']'); sb.toString() }` |
   | Swift | `{ () -> String in var out = "["; let n = xs.count; var i = 0; while i < n { if i > 0 { out += ", "; } out += <element>; i += 1; }; out += "]"; return out }()` |
   | Dart | `(() { final sb = StringBuffer("["); final n = xs.length; var i = 0; while (i < n) { if (i > 0) { sb.write(", "); } sb.write(<element>); i += 1; } sb.write("]"); return sb.toString(); })()` |
   | Rust | `{ let mut out = String::new(); out.push('['); let n = xs.len(); let mut i = 0usize; while i < n { if i > 0 { out.push_str(", "); } let _ = write!(out, "{}", <element>); i += 1; } out.push(']'); out }` |

   `<element>` is the operand form rule 2 renders for one element at its own
   type: bare where the accumulator formats it in place (a scalar on Kotlin
   through the `StringBuilder` append overloads, a scalar on TypeScript
   through the `+=` coercion, a value enumeration on Kotlin through its
   `toString` returning the name constant), the interpolation form on Swift,
   the interpolation form on Dart, and the constructor-name read where the
   target renders a bare operand with its own spelling (`w.kind` on
   TypeScript, `w.rawValue` on Swift, `w.label` on Dart, `w.name()` on Rust
   through the same `write!`). A nested array element is the recursive
   rendering of this rule, appended as the produced string.

   The accumulator is one growable buffer. A two-pass exact pre-sizing would
   convert every element twice, so the single pass with amortized growth is
   the optimal shape (principle 1). No closure runs per element and no
   intermediate collection exists on any target; Kotlin and Rust format
   scalars into the buffer without building an element string (the `append`
   overloads on Kotlin, `write!` on Rust). One immediately-invoked closure
   carries the statement sequence on TypeScript, Swift, and Dart: it is
   allocated once per rendering and zero times per element, and Kotlin `run`
   and the Rust block carry the same sequence without any allocation. No
   resident exists.

## Samples and tests

- `samples/boring/StdStringOps.hx`: concatenations and standalone conversions
  over a `String`, an `Int`, a `Float` (values whose shortest forms agree
  across targets, per the Contract), a `Bool`, and `FloatWidth` constructors;
  an enum conversion compared against its constructor name. Array rows: an
  `Array<Int>`, an `Array<String>`, an `Array<Float>` (shortest-form-agreeing
  values), an `Array<Bool>`, an `Array<FloatWidth>`, an empty array, a
  nested `Array<Array<Int>>`, and a `ReadOnlyArray<String>` operand, each
  compared against its ruled literal; the array rows assert through the
  `boring_oracle` conditional on the Haxe target.
- `samples/tests/StdStringTests.hx` with `@:test` functions; both modules are
  entered in all eight generation hxml files (ts, kotlin, kotlin-f32, rust,
  rust-f32, swift, swift-f32, dart).
- `samples/tests/StdStringProbes.hx`: the named error as ordinary statics,
  following the `ValueRecordProbes` pattern; the probes carry the extended
  message, and array probes cover an out-of-domain element (a class instance
  element, a payload enum element, a nullable element) and an operand typed
  as a type parameter.
- Tree assertions in `tests/ts/std-string.test.ts`: no generated tree
  contains a `Std.` reference; the Kotlin tree renders the bare operands
  inside concatenation; the enum operands render `kind`, `name`, `rawValue`,
  `label`, and `name()` per target; the array operands render a `StringBuilder`
  loop on Kotlin, a `StringBuffer` loop on Dart, a `let` accumulator loop on
  TypeScript, a `var` accumulator loop on Swift, and `String::new` with
  `write!` on Rust; no array row renders `.map(`, `join`, `joinToString`, or
  `joined`.
- Coverage: `bun run gen:ts && bun run gen:kotlin && bun run gen:kotlin-f32 &&
  bun run gen:rust && bun run gen:rust-f32 && bun run gen:swift && bun run
  gen:swift-f32 && bun run gen:dart`, then `bun run test && bun run test:haxe
  && bun run test:kotlin && bun run test:rust && bun run test:swift && bun
  run test:dart` and the remaining steps of `bun run verify`; the consistency
  manager must report identical identifiers and verdicts across kotlin
  (baseline), haxe, ts, rust, swift, and dart.
- The mutation checks for this feature live in the dispatch task file and are
  part of the completion criteria.
