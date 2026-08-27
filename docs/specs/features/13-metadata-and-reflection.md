# Feature spec 13: Metadata and reflection

## Scope

This specification rules compiler metadata tags (`@:native`, `@:keep`, `@:build`, custom metadata) and runtime reflection (`Type`, `Reflect`) across Haxe, Rust, TypeScript, and Kotlin. In the current codebase, compiler metadata appears in Haxe extern declarations in `haxe/src/std/Process.hx` (line 7) and `haxe/src/std/Console.hx` (line 7), derive attributes appear in Rust in `rust/src/lib.rs` (lines 9, 17, 27), and typed runtime validators appear in TypeScript in `ts/src/vector-json.ts` (lines 14-65). `tests/haxe/Main.hx` explicitly notes (lines 13-16) that reflection is unused in tests. In Kotlin, the codec declares no runtime reflection; failure identity is the sealed class hierarchy of `kotlin/src/boring/VectorException.kt`.

## Haxe construct

Haxe provides metadata annotations with `@` (compiler metadata prefixed with `@:`) on types, fields, and expressions:

```haxe
@:native("process")
extern class Process {
	static function exit(code:Int):Void;
}
```

Haxe provides runtime reflection through the `Type` and `Reflect` standard library modules:

```haxe
final fieldNames:Array<String> = Reflect.fields(record);
final value:Dynamic = Reflect.field(record, "codePoint");
final className:String = Type.getClassName(Type.getClass(instance));
```

In the Haxe typed AST, metadata entries are represented by `haxe.macro.Expr.MetadataEntry`. `ClassType`, `ClassField`, and `EnumType` expose their metadata through a `meta:MetaAccess` field, whose `extract(name)` returns `Array<Expr.MetadataEntry>`; metadata attached to expressions appears as `haxe.macro.TypedExprDef.TMeta(m:Expr.MetadataEntry, e1:TypedExpr)`. Reflection calls map to standard `TCall` nodes invoking static methods of `Type` or `Reflect`.

## Current translations

### Haxe (`haxe/src/std/Process.hx`, `tests/haxe/Main.hx`)

```haxe
@:native("process")
extern class Process {
	static function exit(code:Int):Void;
}
```

Reflection is absent from codec logic. `tests/haxe/Main.hx` (lines 51-66) uses explicit field-wise comparison:

```haxe
static function recordEquals(left:GlyphMetrics, right:GlyphMetrics):Bool {
	return left.codePoint == right.codePoint
		&& left.advanceEm == right.advanceEm
		&& left.bounds.xMin == right.bounds.xMin
		&& left.bounds.yMin == right.bounds.yMin
		&& left.bounds.xMax == right.bounds.xMax
		&& left.bounds.yMax == right.bounds.yMax;
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
```

### TypeScript (`ts/src/vector-json.ts`)

```ts
export function toGlyphMetricsRecord(value: unknown): GlyphMetricsRecord {
  if (!isRecord(value)) {
    throw new Error("record must be an object");
  }
  const codePoint = value["codePoint"];
  const advanceEm = value["advanceEm"];
  const bounds = value["bounds"];
  if (typeof codePoint !== "number" || !Number.isInteger(codePoint)) {
    throw new Error("codePoint must be an integer");
  }
  // ...
  return { codePoint, advanceEm, bounds: toBoundsEm(bounds) };
}
```

## Candidate translations

### Rust Candidate 1: Compile-time derive attributes and explicit field access

```rust
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct GlyphMetrics {
    pub code_point: u32,
    pub advance_em: f64,
    pub bounds: BoundsEm,
}
```

### Rust Candidate 2: Dynamic Any trait downcasting

```rust
use std::any::Any;

pub fn inspect_field(value: &dyn Any) -> Option<u32> {
    value.downcast_ref::<u32>().copied()
}
```

### TypeScript Candidate 1: Compile-time typed interfaces and explicit property guards

```ts
export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}
```

### TypeScript Candidate 2: Reflect API metadata and dynamic property iteration

```ts
export function serializeWithReflection(record: object): Uint8Array {
  const keys = Reflect.ownKeys(record);
  const count = keys.length;
  for (let i = 0; i < count; i += 1) {
    const value = Reflect.get(record, keys[i]);
  }
  return new Uint8Array(44);
}
```

### Kotlin Candidate 1: Annotations as compile-time hints and explicit field access

```kotlin
@JvmName("GlyphMetricsRecord")
data class GlyphMetrics(
    val codePoint: Int,
    val advanceEm: Double,
    val bounds: BoundsEm,
)
```

### Kotlin Candidate 2: kotlin.reflect member iteration

```kotlin
fun inspectFields(record: Any): List<String> {
    return record::class.members.map { it.name }
}
```

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Rust Candidate 1 (Derive and explicit access) | Static field access compiles to direct register loads without memory lookups. | Struct definitions fix field offsets and types at compile time. | Single struct declarations provide serialization and formatting logic. | Direct field identifiers state intent directly to Rust engineers. |
| Rust Candidate 2 (Any downcasting) | Dynamic downcasting introduces type ID comparisons and pointer indirection overhead. | Dynamic type inspection bypasses static field layout validation. | Runtime inspection logic forces manual downcast handling at each call site. | Trait object inspection obscures concrete record fields behind dynamic types. |
| TS Candidate 1 (Interfaces and explicit guards) | Direct property access executes with high-speed monomorphic property loads. | Explicit type guards validate unknown inputs before record construction. | Type guards map incoming data directly to named interfaces. | Typed property access communicates data structure shapes directly. |
| TS Candidate 2 (Reflect API iteration) | Reflect and dynamic key iteration incur hash map lookup and string allocation penalties. | Dynamic iteration relies on object property insertion order which can diverge from wire field order. | Dynamic reflection loops require separate schema validation layers. | Reflection helpers obscure field serialization sequence from readers. |
| Kotlin Candidate 1 (Annotations and field access) | Annotations compile to metadata or vanish entirely; field access compiles to direct loads. | Data class properties name every field at compile time. | Generated `equals` and `copy` replace reflective comparison. | Property access states the field it reads. |
| Kotlin Candidate 2 (kotlin.reflect) | `kotlin.reflect` builds member descriptors lazily with allocation on first touch. | Member iteration exposes declaration order details that carry no wire meaning. | Reflection replaces the generated field-wise serialization with a lookup layer. | Indirect member access hides the serialization sequence from readers. |

## Ruling

Compiler metadata is consumed exclusively at build time by the Haxe compiler and Reflaxe generator to configure target code emission, while runtime reflection (`Type`, `Reflect`, `std::any::Any`, `eval`, `kotlin.reflect`) is banned in the codec. Kotlin annotations such as `@JvmName` serve as compile-time emission hints for the generator; runtime annotation retention and inspection are banned with the rest of reflection.

Target codebases must use explicit static field access, derive macros, and build-time generated serializer routines. Dynamic JSON data at boundary points must be validated via explicit type guard functions.

## Test hooks

Field access integrity and non-reflective equality are asserted in:
- `tests/rust/vector.rs` (lines 54-70)
- `tests/haxe/Main.hx` (lines 51-66, 79-88)
- `tests/ts/vector.test.ts` (lines 13-25)
