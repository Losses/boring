# Feature spec 03: Structures and typedefs

## Scope

This specification rules the translation of Haxe anonymous structures and `typedef` declarations into Rust, TypeScript, and Kotlin. In the current codebase, structured records appear in Haxe as `BoundsEm` and `GlyphMetrics` in `haxe/src/boring/GlyphMetrics.hx`, in Rust as `BoundsEm` and `GlyphMetrics` in `rust/src/lib.rs` (lines 9-22), and in TypeScript as `BoundsEmRecord` and `GlyphMetricsRecord` in `ts/src/records.ts`. In Kotlin, structured records appear as `GlyphBounds` and `GlyphMetrics` in `kotlin/src/boring/GlyphMetrics.kt`.

## Haxe construct

Haxe anonymous structures define structural record types composed of named fields. The `typedef` keyword assigns a nominal alias to an anonymous structure:

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

Haxe unifies anonymous structures by shape. Instantiation uses structural object literals `{ field: value }`.

In the Haxe typed AST, a `typedef` is represented by `haxe.macro.Type.TType(t:Ref<DefType>, params:Array<Type>)`. When aliasing an anonymous structure, the underlying type is `haxe.macro.Type.TAnonymous(a:Ref<AnonType>)`, where `AnonType` contains `fields:Array<ClassField>`. Object creation expressions are represented by `haxe.macro.TypedExprDef.TObjectDecl(fields:Array<{name:String, expr:TypedExpr}>)`.

## Current translations

### Haxe (`haxe/src/boring/GlyphMetrics.hx`)

```haxe
package boring;

/** Glyph bounding box in em units. */
typedef BoundsEm = {
	final xMin:Float;
	final yMin:Float;
	final xMax:Float;
	final yMax:Float;
}

/** Fixed glyph metrics record shared by every language suite. */
typedef GlyphMetrics = {
	final codePoint:Int;
	final advanceEm:Float;
	final bounds:BoundsEm;
}
```

### Rust (`rust/src/lib.rs`)

```rust
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct BoundsEm {
    pub x_min: f64,
    pub y_min: f64,
    pub x_max: f64,
    pub y_max: f64,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct GlyphMetrics {
    pub code_point: u32,
    pub advance_em: f64,
    pub bounds: BoundsEm,
}
```

### TypeScript (`ts/src/records.ts`)

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

### Rust Candidate 1: Named struct with derived traits

```rust
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct BoundsEm {
    pub x_min: f64,
    pub y_min: f64,
    pub x_max: f64,
    pub y_max: f64,
}
```

### Rust Candidate 2: Anonymous tuple

```rust
pub type BoundsEm = (f64, f64, f64, f64);
pub type GlyphMetrics = (u32, f64, BoundsEm);
```

### TypeScript Candidate 1: Named interface with readonly fields

```ts
export interface BoundsEmRecord {
  readonly xMin: number;
  readonly yMin: number;
  readonly xMax: number;
  readonly yMax: number;
}
```

### TypeScript Candidate 2: Named type alias for object literal

```ts
export type BoundsEmRecord = {
  readonly xMin: number;
  readonly yMin: number;
  readonly xMax: number;
  readonly yMax: number;
};
```

### TypeScript Candidate 3: Inline anonymous object type

```ts
export function encodeRecord(record: {
  readonly codePoint: number;
  readonly advanceEm: number;
  readonly bounds: {
    readonly xMin: number;
    readonly yMin: number;
    readonly xMax: number;
    readonly yMax: number;
  };
}): Uint8Array {
  return new Uint8Array(44);
}
```

### Kotlin Candidate 1: data class with val properties

```kotlin
data class BoundsEm(
    val xMin: Double,
    val yMin: Double,
    val xMax: Double,
    val yMax: Double,
)
```

### Kotlin Candidate 2: Pair and Triple composition

```kotlin
typealias BoundsEm = Pair<Pair<Double, Double>, Pair<Double, Double>>
```

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Rust Candidate 1 (Named struct) | Struct layout has zero indirection and matches native C ABI alignment. | Explicit field names prevent positional transposition errors. | Type definitions are declared once per module. | Standard struct syntax communicates data layout directly to Rust engineers. |
| Rust Candidate 2 (Anonymous tuple) | Tuples execute with identical memory layout to structs. | Positional fields create ambiguity when multiple fields share the same type. | Tuples require helper conversion functions to access fields by domain meaning. | Numeric index access obscures the semantic meaning of bounding box dimensions. |
| TS Candidate 1 (Named interface) | Interfaces incur zero runtime overhead after TypeScript compilation. | Named interfaces establish strict structural validation across all function boundaries. | The interface is declared once in records.ts and imported across the package. | Explicit interface definitions state data shapes directly without cluttering signatures. |
| TS Candidate 2 (Named type alias) | Type aliases incur zero runtime performance cost. | Aliases produce equivalent type checking behavior to interfaces for plain data shapes. | Type declarations duplicate the naming overhead of interfaces without distinct advantages. | Object type aliases present familiar syntax for JavaScript developers. |
| TS Candidate 3 (Inline object type) | Compiler type checking handles inline objects with zero runtime overhead. | Anonymous shapes invite field divergence between functions when signatures change independently. | Field shapes are re-declared across every function parameter and return type. | Verbose inline shapes clutter function headers and violate repository style rules. |
| Kotlin Candidate 1 (data class) | `data class` instances store fields inline in one flat allocation. | Named `val` properties keep field identity explicit, and generated `equals` and `copy` match record semantics. | One declaration per Haxe structure with component functions for destructuring. | Named properties state the record shape once per type. |
| Kotlin Candidate 2 (Pair composition) | Pair chains add one wrapper object per nesting level per record. | Positional access (`first`, `second`) hides which coordinate each slot holds. | Readers must reconstruct the field order from the alias definition. | Nested pairs erase the field names the Haxe source states. |

## Ruling

Haxe anonymous structure typedefs translate to named `struct` declarations in Rust with public fields and derived traits (`Debug`, `Clone`, `Copy`, `PartialEq`), to named `interface` declarations in TypeScript with `readonly` properties, and to `data class` declarations in Kotlin with `val` properties.

This ruling satisfies the strong typing rules in `AGENT.md`, which ban inline object types outside the direct right-hand side of type aliases (`boring/no-inline-types`) and restrict interfaces to data shape definitions without methods (`boring/no-interface-methods`).

## Test hooks

Record comparisons and structure field integrity are verified in:
- `tests/haxe/Main.hx` (lines 51-66)
- `tests/rust/vector.rs` (lines 9-52)
- `tests/ts/vector.test.ts` (lines 13-25)
