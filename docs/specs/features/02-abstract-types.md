# Feature spec 02: Abstract types

## Scope

This specification rules the translation of Haxe abstract types into Rust and TypeScript. Abstract types do not appear in the repository today; `haxe/src/boring/GlyphMetrics.hx` defines domain records using primitive `Int` and `Float` types. In the glyph metrics domain, abstract types represent specialized scalar domains such as `CodePoint` (constrained to valid Unicode ranges) and `EmUnit` (floating-point em coordinates).

## Haxe construct

Haxe abstract types provide compile-time type distinctions over underlying representation types with zero runtime overhead:

```haxe
abstract CodePoint(Int) from Int to Int {
	public inline function new(value:Int) {
		this = value;
	}

	@:to
	public inline function toHex():String {
		return StringTools.hex(this, 4);
	}
}
```

An abstract type introduces a distinct nominal type at compile time while compiling directly to the underlying primitive type on the target platform. Explicit casts (`@:from`, `@:to`) control conversions between the abstract type and other representations.

In the Haxe typed AST, an abstract type is represented by `haxe.macro.Type.TAbstract(t:Ref<AbstractType>, params:List<Type>)`. The `AbstractType` structure stores the underlying type in `t:Type`, defined conversions in `from:Array<{t:Type, field:Null<ClassField>}>` and `to:Array<{t:Type, field:Null<ClassField>}>`, and the implementation class in `impl:Null<Ref<ClassType>>`.

## Current translations

### Haxe (`haxe/src/boring/GlyphMetrics.hx`)

Absent. Primitive types are used directly:

```haxe
typedef GlyphMetrics = {
	final codePoint:Int;
	final advanceEm:Float;
	final bounds:BoundsEm;
}
```

### Rust (`rust/src/lib.rs`)

Absent. Primitive types are used directly:

```rust
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct GlyphMetrics {
    pub code_point: u32,
    pub advance_em: f64,
    pub bounds: BoundsEm,
}
```

### TypeScript (`ts/src/records.ts`)

Absent. Primitive types are used directly:

```ts
export interface GlyphMetricsRecord {
  readonly codePoint: number;
  readonly advanceEm: number;
  readonly bounds: BoundsEmRecord;
}
```

## Candidate translations

### Rust Candidate 1: Newtype tuple struct

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub struct CodePoint(pub u32);

impl From<u32> for CodePoint {
    fn from(value: u32) -> Self {
        CodePoint(value)
    }
}
```

### Rust Candidate 2: Primitive type alias

```rust
pub type CodePoint = u32;
```

### TypeScript Candidate 1: Branded primitive type

```ts
declare const CodePointBrand: unique symbol;
export type CodePoint = number & { readonly [CodePointBrand]: true };

export function asCodePoint(value: number): CodePoint {
  return value as CodePoint;
}
```

### TypeScript Candidate 2: Primitive type alias

```ts
export type CodePoint = number;
```

### TypeScript Candidate 3: Wrapper class

```ts
export class CodePoint {
  constructor(readonly value: number) {}
}
```

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Rust Candidate 1 (Newtype struct) | The compiler lays out single-field tuple structs identically to the wrapped primitive without heap overhead. | Distinct nominal types prevent accidental assignment of incompatible integer values. | Trait implementations for arithmetic and conversions must be declared explicitly for the new type. | The explicit type signature documents domain constraints directly in function signatures. |
| Rust Candidate 2 (Type alias) | Machine code emission operates directly on native primitive registers. | Type aliases are transparent to the compiler and allow accidental substitution of any u32 value. | Zero duplicate trait or conversion boilerplate is required. | Aliases provide lightweight domain naming with familiar standard primitive semantics. |
| TS Candidate 1 (Branded type) | Type branding exists entirely in the type checker and incurs zero runtime cost. | Nominal brand symbols prevent accidental assignment of raw numbers. | Creation functions must cast raw primitives at validation boundaries. | Type signatures declare domain types while preserving native number operations. |
| TS Candidate 2 (Type alias) | Primitives execute with native JavaScript number performance. | Aliases are erased by TypeScript and provide no protection against assigning arbitrary numbers. | Zero validation wrappers or branding symbols are defined. | Simple type aliases integrate straightforwardly with existing TypeScript code. |
| TS Candidate 3 (Wrapper class) | Class wrappers allocate heap objects for every numeric value and trigger garbage collection churn. | Class instances cannot be compared using value equality without custom methods. | Wrapper classes duplicate storage and conversion logic across modules. | Object wrapping introduces unnecessary ceremony for basic scalar values. |

## Ruling

On codec hot paths and record data carriers, abstract types translate to primitive type aliases (`type CodePoint = u32` in Rust, `type CodePoint = number` in TypeScript) to maintain direct memory access and zero allocation overhead. At domain validation boundaries, abstract types with explicit constraints translate to single-field newtype structs in Rust and branded primitive types in TypeScript.

This separation prevents validation overhead during dense array serialization while providing strong compile-time type safety at API ingestion boundaries.

## Test hooks

Round-trip tests in `tests/ts/codec.test.ts` and `tests/rust/vector.rs` verify primitive integer and float behavior on the wire. Specific unit tests for abstract domain types are none yet.
