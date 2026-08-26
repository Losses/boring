# Feature spec 04: Null safety and optionality

## Scope

This specification rules the translation of Haxe `Null<T>`, optional structural fields (`?field:T`), and optional function arguments into Rust, TypeScript, and Kotlin. In the current repository, glyph metrics records (`haxe/src/boring/GlyphMetrics.hx`, `rust/src/lib.rs`, `ts/src/records.ts`) contain non-null fields. In the glyph metrics domain, optionality governs sparse font tables, fallback glyph identifiers, and optional vertical advance metrics. No Kotlin implementation exists yet; the Kotlin rulings bind generated code.

## Haxe construct

Haxe uses `Null<T>` to denote a type that permits `null` values:

```haxe
typedef ExtendedMetrics = {
	final codePoint:Int;
	final advanceEm:Float;
	final verticalAdvanceEm:Null<Float>;
}
```

On JavaScript targets, reference types and basic types (`Int`, `Float`, `Bool`) permit `null` when wrapped in `Null<T>`. Optional fields in anonymous structures use the `?` prefix:

```haxe
typedef FontHeader = {
	final unitsPerEm:Int;
	final ?familyName:String;
}
```

In the Haxe typed AST, `Null<T>` is represented by `haxe.macro.Type.TAbstract(t:Ref<AbstractType>, params:Array<Type>)` referencing the `Null` core abstract type with `params` holding `[T]`. Optional record fields and function arguments are denoted by setting `ClassField.opt = true` or by `TFun` argument metadata.

## Current translations

### Haxe (`haxe/src/boring/GlyphMetrics.hx`)

Absent. All current fields are mandatory and non-null:

```haxe
typedef GlyphMetrics = {
	final codePoint:Int;
	final advanceEm:Float;
	final bounds:BoundsEm;
}
```

### Rust (`rust/src/lib.rs`)

Absent in data records. `Option<T>` is used for internal chunk slicing in `VectorReader` (lines 74-80):

```rust
fn take_n<const N: usize>(&mut self) -> Result<[u8; N], VectorError> {
    match self.bytes[self.offset..].split_first_chunk::<N>() {
        Some((head, _)) => {
            self.offset += N;
            Ok(*head)
        }
        None => Err(VectorError::UnexpectedEof),
    }
}
```

### TypeScript (`ts/src/records.ts`)

Absent. All interface fields are mandatory and non-null:

```ts
export interface GlyphMetricsRecord {
  readonly codePoint: number;
  readonly advanceEm: number;
  readonly bounds: BoundsEmRecord;
}
```

## Candidate translations

### Rust Candidate 1: Option enum

```rust
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ExtendedMetrics {
    pub code_point: u32,
    pub advance_em: f64,
    pub vertical_advance_em: Option<f64>,
}
```

### Rust Candidate 2: In-band sentinel value

```rust
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ExtendedMetrics {
    pub code_point: u32,
    pub advance_em: f64,
    pub vertical_advance_em: f64, // -1.0 indicates missing
}
```

### TypeScript Candidate 1: Optional property with undefined

```ts
export interface ExtendedMetricsRecord {
  readonly codePoint: number;
  readonly advanceEm: number;
  readonly verticalAdvanceEm?: number;
}
```

### TypeScript Candidate 2: Union with null

```ts
export interface ExtendedMetricsRecord {
  readonly codePoint: number;
  readonly advanceEm: number;
  readonly verticalAdvanceEm: number | null;
}
```

### TypeScript Candidate 3: Sentinel number value

```ts
export interface ExtendedMetricsRecord {
  readonly codePoint: number;
  readonly advanceEm: number;
  readonly verticalAdvanceEm: number; // NaN indicates missing
}
```

### Kotlin Candidate 1: Nullable type

```kotlin
data class ExtendedMetrics(
    val codePoint: Int,
    val advanceEm: Double,
    val verticalAdvanceEm: Double?,
)
```

### Kotlin Candidate 2: Sentinel value

```kotlin
data class ExtendedMetrics(
    val codePoint: Int,
    val advanceEm: Double,
    val verticalAdvanceEm: Double, // -1.0 indicates missing
)
```

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Rust Candidate 1 (Option) | The compiler applies null-pointer and niche optimizations to Option types with zero runtime heap allocation. | Option enforces explicit branch handling through match or combinators without missing value states. | Standard library Option integrates with all Rust traits and iterator adapters. | Explicit Option types communicate optionality directly to Rust readers. |
| Rust Candidate 2 (Sentinel value) | Numeric sentinel checks execute in a single CPU comparison instruction. | Valid domain values can collide with arbitrary sentinel constants. | Every consuming function must manually duplicate sentinel check constants. | Magic sentinel numbers conceal optionality from the type system. |
| TS Candidate 1 (undefined / optional) | V8 and JavaScript runtimes optimize optional property access without boxing. | The TypeScript compiler enforces strict null checking under strictNullChecks mode. | Optional properties integrate directly with JavaScript destructuring defaults. | The standard question-mark property syntax communicates optionality directly. |
| TS Candidate 2 (Union with null) | Property access performance matches optional property access. | Dual representations arise when callers mix null and undefined. | Codebases must handle both null and undefined across serialization boundaries. | Explicit null unions require repetitive null checks in client code. |
| TS Candidate 3 (Sentinel value) | Numeric comparisons execute quickly at runtime. | Sentinel numbers like NaN or negative numbers break standard arithmetic operations. | Serialization code must duplicate sentinel checks across encoders and decoders. | Sentinel values hide optional presence from type checker validation. |
| Kotlin Candidate 1 (Nullable type) | Null checks compile to single references or flag tests; `Double?` boxes, which the type makes visible at the signature. | The compiler forces a null check or a default before every dereference. | Nullable types integrate with `?.`, `?:`, and `let` without helper types. | The `?` suffix states optionality directly in the field type. |
| Kotlin Candidate 2 (Sentinel value) | Numeric sentinel checks execute in a single comparison instruction. | Valid domain values can collide with the sentinel constant. | Every consumer duplicates the sentinel check. | Magic numbers conceal optionality from the type system. |

## Ruling

Haxe `Null<T>` and optional fields translate to `Option<T>` in Rust, to optional properties (`prop?: T` or `T | undefined`) in TypeScript, and to nullable types `T?` in Kotlin. Sentinel values are forbidden across all targets.

This ruling prevents out-of-band error states and ensures that absence of a value is enforced by the compiler type checker on all platforms.

## Test hooks

Null safety is enforced by TypeScript `strictNullChecks` in `tsconfig.json` and Rust type checking. Specific vector tests for optional metrics are none yet.
