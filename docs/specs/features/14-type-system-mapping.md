# Feature spec 14: Type system mapping

## Scope

This specification rules the overall mapping of the Haxe type system onto Rust, TypeScript, and Kotlin: which Haxe types are nominal, which are structural, how type identity survives translation, and where explicit conversions are permitted. It consolidates the per-construct rulings of specs 01 through 13 into one mapping table and one set of identity rules. In the current codebase, named record types appear in Haxe as typedefs over anonymous structures in `samples/boring/GlyphMetrics.hx` (lines 4-16), in Rust as structs in `reference/rust/src/lib.rs` (lines 9-22), and in TypeScript as interfaces in `reference/ts/src/records.ts` (lines 7-18); a nominal sum type appears in Rust as `VectorError` in `reference/rust/src/lib.rs` (lines 28-33). In Kotlin, named record types appear as classes with `val` constructor properties in `reference/kotlin/src/boring/GlyphMetrics.kt`, and the sum type appears as the sealed `VectorException` hierarchy in `reference/kotlin/src/boring/VectorException.kt`.

## Haxe construct

Haxe class types, enum types, abstract types, and typedefs aliasing them are nominal: two declarations denote the same type only when they name the same declaration. Anonymous structures are structural: compatibility follows field names and field types. A typedef over an anonymous structure keeps a name for documentation but remains structural, as `GlyphMetrics` does:

```haxe
typedef GlyphMetrics = {
	final codePoint:Int;
	final advanceEm:Float;
	final bounds:BoundsEm;
}
```

In the Haxe typed AST, types are represented by the `haxe.macro.Type` enum: `TInst(t:Ref<ClassType>, params:Array<Type>)` for classes, `TEnum(t:Ref<EnumType>, params:Array<Type>)` for enums, `TAbstract(t:Ref<AbstractType>, params:Array<Type>)` for abstracts, `TType(t:Ref<DefType>, params:Array<Type>)` for named typedefs, `TAnonymous(a:Ref<AnonType>)` for anonymous structures, `TFun(args:Array<{name:String, opt:Bool, t:Type}>, ret:Type)` for function types, and `TDynamic(t:Null<Type>)` for `Dynamic`.

## Current translations

### Haxe (`samples/boring/GlyphMetrics.hx`)

```haxe
typedef BoundsEm = {
	final xMin:Float;
	final yMin:Float;
	final xMax:Float;
	final yMax:Float;
}

typedef GlyphMetrics = {
	final codePoint:Int;
	final advanceEm:Float;
	final bounds:BoundsEm;
}
```

### Rust (`reference/rust/src/lib.rs`)

```rust
pub struct BoundsEm {
    pub x_min: f64,
    pub y_min: f64,
    pub x_max: f64,
    pub y_max: f64,
}

pub struct GlyphMetrics {
    pub code_point: u32,
    pub advance_em: f64,
    pub bounds: BoundsEm,
}
```

### TypeScript (`reference/ts/src/records.ts`)

```ts
export interface BoundsEmRecord {
  readonly xMin: number;
  readonly yMin: number;
  readonly xMax: number;
  readonly yMax: number;
}

export interface GlyphMetricsRecord {
  readonly codePoint: number;
  readonly advanceEm: number;
  readonly bounds: BoundsEmRecord;
}
```

## Candidate translations

### Rust Candidate 1: Nominal discipline with named structs

Every Haxe named type and every anonymous structure maps to a named Rust type. The compiler checks field compatibility at construction sites and rejects mismatches.

```rust
pub struct GlyphMetrics {
    pub code_point: u32,
    pub advance_em: f64,
    pub bounds: BoundsEm,
}
```

### Rust Candidate 2: Structural emulation with field-access traits

Anonymous structures map to generic traits with one accessor method per field, and records implement the traits.

```rust
pub trait HasCodePoint {
    fn code_point(&self) -> u32;
}
```

### TypeScript Candidate 1: Named structural interfaces with nominal brands at boundaries

All record types are named interfaces. Public API parameters that must not accept unrelated same-shape values use branded types as ruled in `docs/specs/features/02-abstract-types.md`.

```ts
export interface GlyphMetricsRecord {
  readonly codePoint: number;
  readonly advanceEm: number;
  readonly bounds: BoundsEmRecord;
}
```

### TypeScript Candidate 2: Inline structural object types

Record shapes are written inline at each use site.

```ts
export function encodeRecords(
  records: readonly { readonly codePoint: number; readonly advanceEm: number }[],
): Uint8Array {
  throw new Error("not implemented");
}
```

### Kotlin Candidate 1: Nominal data class per named type

Every Haxe named type and every anonymous structure maps to a named Kotlin `data class`. The compiler checks field compatibility at construction sites and rejects mismatches.

```kotlin
data class GlyphMetrics(
    val codePoint: Int,
    val advanceEm: Double,
    val bounds: BoundsEm,
)
```

### Kotlin Candidate 2: Structural emulation through generic aliases

Anonymous structures map to generic container aliases, and records access fields positionally.

```kotlin
typealias GlyphMetricsFields = Triple<Int, Double, BoundsEmFields>
```

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Rust Candidate 1 (Nominal structs) | Monomorphic named structs compile to fixed field offsets with direct access and inlining. | Distinct declarations stay distinct, and the compiler rejects field mismatches at construction. | One struct per Haxe type with no companion traits. | A named struct states the record shape once per type. |
| Rust Candidate 2 (Field-access traits) | Trait dispatch adds indirection and blocks field inlining unless calls monomorphize. | Any type implementing the traits satisfies a parameter, so two distinct Haxe types merge into one Rust interface. | Every record needs a trait declaration plus an implementation block. | Trait indirection hides the concrete memory layout from readers. |
| TS Candidate 1 (Named interfaces with brands) | Named interfaces compile to plain object shapes with monomorphic property access. | Names document intent, and brands restore nominal guarantees where the API requires them. | One interface per Haxe type. | Named interfaces match the repository rule recorded in `reference/ts/src/records.ts` (lines 1-5). |
| TS Candidate 2 (Inline types) | The runtime shape is identical, but every use site restates the fields. | Two inline types with the same fields are interchangeable even when the Haxe types were distinct. | Field lists repeat at every use site. | Inline object types violate the repository ban recorded in `reference/ts/src/records.ts` (lines 1-5) and AGENT.md. |
| Kotlin Candidate 1 (Nominal data class) | Flat field layout with direct property access and generated `equals` and `copy`. | Distinct declarations stay distinct, and the compiler rejects field mismatches at construction. | One `data class` per Haxe type with no companion machinery. | Named properties state the record shape once per type. |
| Kotlin Candidate 2 (Generic aliases) | Container access runs at full speed, with field identity lost to positional calls. | Any alias with matching component types satisfies a parameter, merging two distinct Haxe types into one shape. | Every access re-derives field meaning from the alias definition. | Positional components hide the field names the Haxe source states. |

## Ruling

The fixed mapping table:

| Haxe type | Rust type | TypeScript type | Kotlin type |
| --- | --- | --- | --- |
| `Int` | `u32` (`i32` inside resident runtime modules) | `number` | `Int` (`Long` when the declared range exceeds `0x7FFFFFFF`) |
| `Float` | `f64` | `number` | `Double` |
| `Bool` | `bool` | `boolean` | `Boolean` |
| `String` | `String` or `&str` | `string` | `String` |
| `enum` | `enum` | discriminated union with `kind` tag | `sealed interface` with `data object` and `data class` variants |
| `class` | `struct` plus `impl` block | `class` | `class` |
| anonymous structure | named `struct` | named `interface` | `data class` with `val` properties |
| typedef alias of a named type | type alias | type alias | `typealias` |
| `abstract` over `T` | newtype or type alias per features/02 | brand or type alias per features/02 | `value class` or `typealias` per features/02 |
| `Null<T>` | `Option<T>` | optional property (`prop?: T` or `T | undefined`) per features/04 | `T?` per features/04 |
| `Dynamic` | banned | banned | banned |

Rules:

- Type identity never merges. Two distinct named Haxe types translate to two distinct target types even when their shapes coincide, because merged types erase the distinction the Haxe compiler enforced.
- The Kotlin `Long` promotion in the table is conditional on a declared
  range above `0x7FFFFFFF`. The generator has no schema mechanism that
  declares a field range, so the promotion has no implementation path. No
  current field exceeds the range: wire counts are bounded by
  `CountOverflow` at `2^31` and code points by `0x10FFFF`. The promotion
  is implemented when the first field with such a range is declared; the
  declaration mechanism and the promotion are implemented in the same
  change.
- No silent widening or narrowing. Every numeric conversion is an explicit named function at an API or wire boundary; the numeric selection follows the wire type table in `docs/specs/features/07-numeric-tower.md`.
- The Rust `Int` domain follows the module kind: business modules render `u32`, resident runtime modules render `i32`, and the call boundary converts between the two domains through the named adapters of `docs/specs/stdlib/07-sorted-keyed-tables.md`, `docs/specs/stdlib/10-unicode-string-access.md`, and `docs/specs/stdlib/11-grapheme-clusters.md`.
- Every target type is named. Inline object, function, mapped, and tuple types are banned repo-wide as recorded in `reference/ts/src/records.ts` (lines 1-5).
- Generic parameter translation follows `docs/specs/features/05-generics.md`; this table fixes only the base types.
- Kotlin `data class` gives record equality, copying, and destructuring; `value class` wraps its underlying representation without boxing outside nullable and generic positions.

## Test hooks

Type parity is enforced by compilation of the three trees and by record round trips:
- `tests/ts/vector.test.ts` (lines 13-25)
- `tests/rust/vector.rs` (lines 54-70)
- `tests/haxe/Main.hx` (lines 79-88)

Consistency between this mapping table and the wire type table in features/07 is a manual review step; no automated cross-check exists yet.
