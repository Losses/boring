# Feature spec 16: Static object access

## Scope

This specification rules the read and write syntax for static objects: fixed-shape anonymous structures and their arrays. Haxe source keeps the human-friendly syntax: dot access for fields, bracket access with an integer index for arrays, and brace literals for construction. The generated code for every target uses the performance-optimal native form, and the observable behavior is identical across languages: reading a declared field always yields the stored value, construction initializes every field exactly once, and no operation changes the shape of an object after construction. In the current codebase, static objects appear as `BoundsEm` in `samples/boring/GlyphMetrics.hx`, as `BoundsEm` in `reference/rust/src/lib.rs`, and as `BoundsEmRecord` in `reference/ts/src/records.ts`. In Kotlin, static objects appear as `GlyphBounds` in `reference/kotlin/src/boring/GlyphMetrics.kt`.

## Haxe construct

A static object is an anonymous structure whose field list is fixed at declaration:

```haxe
typedef BoundsEm = {
	final xMin:Float;
	final yMin:Float;
	final xMax:Float;
	final yMax:Float;
}

final bounds:BoundsEm = {
	xMin: xMin,
	yMin: yMin,
	xMax: xMax,
	yMax: yMax,
};

final left:Float = bounds.xMin;
final first:GlyphMetrics = records[0];
```

The source syntax is unrestricted Haxe: dots for fields, brackets for array indices, braces for literals. Two restrictions define the static boundary, and the interception of `docs/specs/style/01-haxe-style-standard.md` enforces both:

1. Bracket access on an anonymous structure with a `String` key, such as `bounds["xMin"]`, is rejected. Bracket access is reserved for integer indices on arrays; field access goes through the dot form, so the accessed field is always a declared, typed field.
2. No operation adds, removes, or conditionally omits a field after construction. Construction sets every declared field exactly once in declaration order.

In the Haxe typed AST, structure literals are `haxe.macro.TypedExprDef.TObjectDecl(fields:Array<{name:String, expr:TypedExpr}>)`, field reads are `TField(e, fa)` with the field access carrying the class or structure field, integer-indexed reads are `TArray(e1, e2)` with `e2` typed `Int`, and writes are `TBinop(OpAssign, ...)` targeting a declared field.

## Current translations

### Haxe (`samples/boring/GlyphMetrics.hx`)

```haxe
typedef BoundsEm = {
	final xMin:Float;
	final yMin:Float;
	final xMax:Float;
	final yMax:Float;
}
```

### Rust (`reference/rust/src/lib.rs`)

```rust
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct BoundsEm {
    pub x_min: f64,
    pub y_min: f64,
    pub x_max: f64,
    pub y_max: f64,
}
```

### TypeScript (`reference/ts/src/records.ts`, `reference/ts/src/vector-format.ts`)

```ts
export interface BoundsEmRecord {
  readonly xMin: number;
  readonly yMin: number;
  readonly xMax: number;
  readonly yMax: number;
}

const bounds = { xMin, yMin, xMax, yMax };
const left = bounds.xMin;
```

## Candidate translations

The candidates below fix the TypeScript rendering; Rust and Kotlin have one native form each, ruled without alternatives at the end.

### TypeScript Candidate 1: Object literal with direct property access (selected)

```ts
const bounds: BoundsEmRecord = { xMin, yMin, xMax, yMax };
const left = bounds.xMin;
```

### TypeScript Candidate 2: Map keyed by field names

```ts
const bounds = new Map<string, number>([
  ["xMin", xMin],
  ["yMin", yMin],
]);

const left = bounds.get("xMin");
```

### TypeScript Candidate 3: Class instances with accessor methods

```ts
export class BoundsEm {
  #xMin: number;
  constructor(xMin: number) {
    this.#xMin = xMin;
  }
  get xMin(): number {
    return this.#xMin;
  }
}
```

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| TS Candidate 1 (Literal and direct access) | One allocation per object; every access site with the same shape hits the same hidden class, so property reads compile to inline offset loads. | The interface declares every field, and the type checker rejects access to undeclared names. | No accessor methods, no wrapper types, no key constants. | Field reads state the field name directly. |
| TS Candidate 2 (Keyed Map) | Every read hashes a string key and boxes the result through `get`, and numbers allocate when stored as `Map` values. | The value type widens to `number | undefined`, so every read carries a presence question the static shape already answers. | Key strings repeat at every access site. | Keyed reads replace the field name with a string literal. |
| TS Candidate 3 (Accessor class) | Private fields plus getters add one function call per read unless the engine inlines it, and construction runs a constructor with parameter validation. | Accessors expose exactly the declared fields, at the cost of method syntax for data. | One getter per field duplicates what the property states. | Accessor calls read as method invocations on data carriers. |

## Ruling

Static objects translate to the direct native data form on every target: named `struct` with public fields in Rust, object literal typed by a named interface with direct property access in TypeScript (Candidate 1), and `data class` with `val` properties in Kotlin, following the type mapping of `docs/specs/features/14-type-system-mapping.md`.

Behavior parity rules bind all targets:

1. Construction initializes every declared field exactly once, in declaration order. Declaration order is part of the format definition; it keeps hidden-class transitions in V8 monomorphic and keeps JSON serialization of equivalent values identical across trees.
2. Reading a declared field yields the stored value in every language. No language produces `null`, `undefined`, or a default on a declared field of a constructed object, because construction sets every field.
3. Writing obeys the mutability declared in Haxe: `final` fields translate to `readonly` properties in TypeScript, non-`mut` struct fields in Rust, and `val` properties in Kotlin.
4. Nothing changes an object's shape after construction. Rust and Kotlin make this unrepresentable; TypeScript makes it a rejection: `Reflect.set`, `delete`, and assignment to an undeclared property are rejected by the structure test that scans `reference/ts/src` for those call sites.
5. Bracket access with a `String` key on a structure is rejected on the Haxe side before generation; bracket access with an `Int` index translates to array element access on every target.

Field iteration over a static object does not translate. An algorithm that must visit every field of a structure enumerates an explicitly declared constant array of the field names it processes; that array is compile-time constant data and unrolls per `docs/specs/stdlib/04-haxe-ds-vector.md`. Dynamic enumeration through `Reflect.ownKeys` or `Object.keys` on static shapes is banned, consistent with `docs/specs/features/13-metadata-and-reflection.md`.

## Test hooks

Round trips through the bounds structure are asserted in:
- `tests/rust/vector.rs` (lines 54-70)
- `tests/haxe/Main.hx` (lines 79-88)
- `tests/ts/vector.test.ts` (lines 13-25)

Required guards, none of which exist yet:

- A structure test asserts that no file under `reference/ts/src` calls `Reflect.set`, `Reflect.get`, `delete`, or `Object.keys` on a record-typed value.
- An interception test compiles a Haxe source with a `String`-keyed bracket access and a post-construction field addition, and asserts that both abort with the named violations of `docs/specs/style/01-haxe-style-standard.md`.
