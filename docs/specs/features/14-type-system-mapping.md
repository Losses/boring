# Feature spec 14: Type system mapping

## Scope

This specification rules the overall mapping of the Haxe type system onto Rust and TypeScript: which Haxe types are nominal, which are structural, how type identity survives translation, and where explicit conversions are permitted. It consolidates the per-construct rulings of specs 01 through 13 into one mapping table and one set of identity rules. In the current codebase, named record types appear in Haxe as typedefs over anonymous structures in `haxe/src/boring/GlyphMetrics.hx` (lines 4-16), in Rust as structs in `rust/src/lib.rs` (lines 9-22), and in TypeScript as interfaces in `ts/src/records.ts` (lines 7-18); a nominal sum type appears in Rust as `VectorError` in `rust/src/lib.rs` (lines 28-33).

## Haxe construct

Haxe class types, enum types, abstract types, and typedefs aliasing them are nominal: two declarations denote the same type only when they name the same declaration. Anonymous structures are structural: compatibility follows field names and field types. A typedef over an anonymous structure keeps a name for documentation but remains structural, as `GlyphMetrics` does:

```haxe
typedef GlyphMetrics = {
	final codePoint:Int;
	final advanceEm:Float;
	final bounds:BoundsEm;
}
```

In the Haxe typed AST, types are represented by the `haxe.macro.Type` enum: `TInst(c:Ref<ClassType>, params:List<Type>)` for classes, `TEnum(t:Ref<EnumType>, params:List<Type>)` for enums, `TAbstract(a:Ref<AbstractType>, params:List<Type>)` for abstracts, `TType(t:Ref<DefType>, params:List<Type>)` for named typedefs, `TAnonymous(a:Ref<AnonType>)` for anonymous structures, `TFun(args:Array<{t:Type, opt:Bool}>, ret:Type)` for function types, and `TDynamic` for `Dynamic`.

## Current translations

### Haxe (`haxe/src/boring/GlyphMetrics.hx`)

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

### Rust (`rust/src/lib.rs`)

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

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Rust Candidate 1 (Nominal structs) | Monomorphic named structs compile to fixed field offsets with direct access and inlining. | Distinct declarations stay distinct, and the compiler rejects field mismatches at construction. | One struct per Haxe type with no companion traits. | A named struct states the record shape once per type. |
| Rust Candidate 2 (Field-access traits) | Trait dispatch adds indirection and blocks field inlining unless calls monomorphize. | Any type implementing the traits satisfies a parameter, so two distinct Haxe types merge into one Rust interface. | Every record needs a trait declaration plus an implementation block. | Trait indirection hides the concrete memory layout from readers. |
| TS Candidate 1 (Named interfaces with brands) | Named interfaces compile to plain object shapes with monomorphic property access. | Names document intent, and brands restore nominal guarantees where the API requires them. | One interface per Haxe type. | Named interfaces match the repository rule recorded in `ts/src/records.ts` (lines 1-5). |
| TS Candidate 2 (Inline types) | The runtime shape is identical, but every use site restates the fields. | Two inline types with the same fields are interchangeable even when the Haxe types were distinct. | Field lists repeat at every use site. | Inline object types violate the repository ban recorded in `ts/src/records.ts` (lines 1-5) and AGENT.md. |

## Ruling

The fixed mapping table:

| Haxe type | Rust type | TypeScript type |
| --- | --- | --- |
| `Int` | `i32` or `u32` selected by wire width | `number` |
| `Float` | `f64` | `number` |
| `Bool` | `bool` | `boolean` |
| `String` | `String` or `&str` | `string` |
| `enum` | `enum` | discriminated union with `kind` tag |
| `class` | `struct` plus `impl` block | `class` |
| anonymous structure | named `struct` | named `interface` |
| typedef alias of a named type | type alias | type alias |
| `abstract` over `T` | newtype or type alias per features/02 | brand or type alias per features/02 |
| `Null<T>` | `Option<T>` | `T | null` or optional property per features/04 |
| `Dynamic` | banned | banned |

Rules:

- Type identity never merges. Two distinct named Haxe types translate to two distinct target types even when their shapes coincide, because merged types erase the distinction the Haxe compiler enforced.
- No silent widening or narrowing. Every numeric conversion is an explicit named function at an API or wire boundary; the numeric selection follows the wire type table in `docs/specs/features/07-numeric-tower.md`.
- Every target type is named. Inline object, function, mapped, and tuple types are banned repo-wide as recorded in `ts/src/records.ts` (lines 1-5).
- Generic parameter translation follows `docs/specs/features/05-generics.md`; this table fixes only the base types.

## Test hooks

Type parity is enforced by compilation of the three trees and by record round trips:
- `tests/ts/vector.test.ts` (lines 13-25)
- `tests/rust/vector.rs` (lines 54-70)
- `tests/haxe/Main.hx` (lines 79-88)

Consistency between this mapping table and the wire type table in features/07 is a manual review step; no automated cross-check exists yet.
