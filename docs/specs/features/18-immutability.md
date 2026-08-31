# Feature spec 18: Immutability and read-only data

## Scope

This specification rules the translation of read-only data: values whose
contents no consumer may change after construction, with the failure of a
mutation attempt reported at the earliest point each platform can state it.
Decoded vector data is the reference case: `VectorCodec.decode` and the JSON
boundary return records that downstream code reads and never writes. In the
current codebase, the read-only record types appear in TypeScript as the
`readonly` members of `reference/ts/src/records.ts`, the Haxe source exposes decoded
arrays through the `ReadOnlyArray` abstract in `samples/boring/`, the Kotlin
codec returns the `List` view built in `reference/kotlin/src/boring/VectorCodec.kt`,
and Rust exposes decoded data through borrowed slices per this ruling.

## Haxe construct

Haxe has no read-only array type in its standard library. The translatable
subset states read-only through two existing constructs:

1. Record fields declared `final`. Structure typedefs under style rule 1
   already declare every field with a `final` or mutable marker; a typedef
   whose fields are all `final` is a read-only record.
2. A read-only array type declared as an abstract over `Array<T>`:

```haxe
@:forward(length)
abstract ReadOnlyArray<T>(Array<T>) from Array<T> {
	@:arrayAccess inline function get(index:Int):T {
		return this[index];
	}
}
```

The abstract forwards `length` and indexed reads only. It accepts any
`Array<T>` through the `from` conversion, so decode implementations fill a
plain array and return it as `ReadOnlyArray<T>`. A mutation call on the
abstract (`push`, `pop`, `shift`, `unshift`, `insert`, `remove`, indexed
assignment) does not typecheck, because no forwarded or declared member
provides it; extracting the mutable array requires a cast, and casts without
a target type are rejection `V05` in `docs/specs/style/01-haxe-style-standard.md`.
Enforcement therefore lives in the Haxe type system and needs no additional
rejection row. The abstract is a compile-time construct: it erases before
any target sees it, and the generator reads the abstract type as the signal
for the read-only lowering below.

## Current translations

### Haxe (`samples/boring/VectorCodec.hx`)

```haxe
public static function decode(bytes:Bytes):ReadOnlyArray<GlyphMetrics> {
	// ...
	final records = new Array<GlyphMetrics>();
	for (index in 0...count) {
		// ...
		records[index] = { codePoint: codePoint, advanceEm: advanceEm, bounds: {
			xMin: xMin, yMin: yMin, xMax: xMax, yMax: yMax } };
	}
	return records;
}

public static function encode(records:ReadOnlyArray<GlyphMetrics>):Bytes {
	// traversal only: records.length and records[index]
}
```

### TypeScript (`reference/ts/src/vector-format.ts`)

```ts
export function decodeVector(bytes: Uint8Array): readonly GlyphMetricsRecord[] {
  // ...
  const records: GlyphMetricsRecord[] = new Array<GlyphMetricsRecord>(count);
  for (let i = 0; i < count; i += 1) {
    // ...
    const bounds = Object.freeze({ xMin, yMin, xMax, yMax });
    records[i] = Object.freeze({ codePoint, advanceEm, bounds });
  }
  return Object.freeze(records);
}
```

The type layer carries `readonly` members (`reference/ts/src/records.ts`) and
`readonly` array types on every decode return; the runtime layer returns
each record, its bounds object, and the array itself as frozen objects at
the decode boundary (`DecodeBoundaryFreeze`). Assignment to a frozen object
or array in strict mode, and method calls that change a frozen array,
throw `TypeError`.

### Kotlin (`reference/kotlin/src/boring/VectorCodec.kt`)

```kotlin
fun decode(bytes: ByteArray): List<GlyphMetrics> {
    // ...
    val count = reader.readU32()
    val records = Array(count) {
        val codePoint = reader.readU32()
        val advanceEm = reader.readF64()
        // ... yMin, xMax, yMax read the same way
        GlyphMetrics(
            codePoint = codePoint,
            advanceEm = advanceEm,
            bounds = GlyphBounds(xMin = xMin, yMin = yMin, xMax = xMax, yMax = yMax)
        )
    }
    return records.asList()
}
```

Record classes declare `val` properties only (`reference/kotlin/src/boring/GlyphMetrics.kt`).
The fill uses the array initializer ruled in `docs/specs/stdlib/04-haxe-ds-vector.md`;
`asList()` returns the zero-copy fixed-size view over the backing array, so
the decode return type is the read-only `List` interface (`ArrayInitializerFill`,
`AsListReadView`). `add` and `remove` on the view throw
`UnsupportedOperationException` at runtime; element writes have no pathway
through the `List` interface.

### Rust (`reference/rust/src/lib.rs`)

```rust
pub fn decode_vector(bytes: &[u8]) -> Result<Vec<GlyphMetrics>, VectorError> {
    // ...
}

pub fn encode_vector(records: &[GlyphMetrics]) -> Result<Vec<u8>, VectorError> {
    // records is a borrowed slice: mutation has no pathway
}
```

Rust states read-only through borrows: owned data leaves the decoder, and
every read-only consumption site takes `&[GlyphMetrics]` or `&GlyphMetrics`.
Mutation of a borrowed value fails compilation in the consumer, before the
program runs.

## Candidate translations

### Haxe Candidate 1: Read-only abstract over Array (selected)

The `ReadOnlyArray<T>` abstract above: compile-time enforcement, zero runtime
cost, erases on every target.

### Haxe Candidate 2: Metadata marker with interception row

A `@:readOnly` metadata on typedefs and locals, with a rejection row for
mutation calls on marked values.

### Haxe Candidate 3: Wrapper class holding a private array

A `class ReadOnly<T>` with explicit getter methods and a private backing
field.

### TypeScript Candidate 1: readonly types plus a frozen boundary (selected)

`readonly` members and `readonly T[]` on every decode return type, plus
`Object.freeze(...)` applied to each record, its nested objects, and the
array at the decode boundary.

### TypeScript Candidate 2: readonly types alone

The type layer states read-only; objects stay mutable at runtime.

### TypeScript Candidate 3: Deep-copy-on-read defensive accessors

Every read returns a fresh copy, so mutations hit the copy.

### Kotlin Candidate 1: Read-only List interface over an initializer-filled array (selected)

`Array(count) { ... }` filled per the allocation ruling, exposed through
`asList()` as `List<T>`; `add`/`remove` throw at runtime.

### Kotlin Candidate 2: MutableList return type

Decode returns `ArrayList<GlyphMetrics>` directly.

### Kotlin Candidate 3: Custom persistent wrapper

A hand-written `ReadOnlyList<T>` class delegating reads to a private list.

### Rust Candidate 1: Borrow-based read-only access (selected)

Decode returns owned data; read-only consumption takes `&[T]`; the compiler
rejects mutation at the consumer.

### Rust Candidate 2: Wrapper struct owning private data

A `struct ReadOnlyVec<T>(Vec<T>)` exposing read methods only.

### Rust Candidate 3: compile_error!-guarded mutator shims

Generated mutator functions whose bodies are `compile_error!` with a named
message, planted wherever a lowering would otherwise emit a mutation of a
read-only-typed value.

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Haxe C1 (Abstract) | Abstracts erase after typing; reads inline to plain array accesses with zero runtime cost. | The abstract name states the read-only contract at every declaration site. | One abstract serves every element type through its parameter. | `ReadOnlyArray<T>` reads as a type that exposes no mutating members. |
| Haxe C2 (Metadata) | Metadata checks run at compilation with no runtime cost. | The contract lives in an annotation a reader can miss at the use site. | A rejection row and its test cases duplicate what the type system states. | Mutation errors appear as interception reports at generation time. |
| Haxe C3 (Wrapper) | Every read passes through a method call; inline mitigates but the declaration cost stays. | The contract is explicit in the class shape. | One wrapper instance per collection at runtime. | Getter chains lengthen every access expression. |
| TS C1 (readonly + frozen boundary) | One pass over the decoded payload calls `Object.freeze(` on each object at the boundary; reads afterward are plain property loads with no wrapper. | The type layer rejects mutation at compile time and the frozen objects reject it at runtime; the two state one contract. | One `Object.freeze(` call per object; no per-access machinery. | `readonly GlyphMetricsRecord[]` states the contract in the signature. |
| TS C2 (readonly only) | No runtime enforcement cost. | JavaScript consumers without the types mutate freely; the contract holds only inside checked TypeScript. | Least code of the three. | The signature promises a guarantee the runtime does not keep. |
| TS C3 (Copy-on-read) | Every read allocates a copy; a traversal over n records allocates n copies. | Copy semantics differ from reference semantics, changing identity comparisons. | A copy per access multiplies allocations by access count. | Readers cannot tell whether they hold the original or a copy. |
| Kotlin C1 (List view) | The fill keeps the array initializer cost profile; `asList()` wraps the backing array with one small view object and no copy; reads go through the `List` interface, which the JIT inlines to direct indexing at monomorphic call sites. | The `List` return type states the read-only contract; `add`/`remove` fail at runtime with the platform's own exception. | One view object per collection. | `List<GlyphMetrics>` is the standard Kotlin read-only type. |
| Kotlin C2 (MutableList) | Identical construction cost. | The signature invites mutation; nothing states the contract. | None. | Consumers cannot tell decoded data from scratch storage. |
| Kotlin C3 (Wrapper) | Reads pass through delegation; one wrapper instance per collection. | The contract is explicit but nonstandard. | A parallel type duplicates the platform interface. | A custom name replaces the interface every Kotlin reader knows. |
| Rust C1 (Borrows) | Borrows compile to pointers; no wrapper, no runtime check, zero cost. | The `&` in every signature states the contract, and the compiler proves it. | No additional types. | Borrow syntax is the language's own read-only statement. |
| Rust C2 (Wrapper struct) | Reads add a method call that inlines away; construction moves data into the wrapper. | The type name states the contract. | A parallel type wraps what a borrow states. | An extra layer around standard slice syntax. |
| Rust C3 (compile_error! shims) | No runtime cost; the error is a compile-time constant. | The named message states exactly which lowering is forbidden. | Shims exist only to fail; they are generated, never called. | The error text names the violated contract at the offending line. |

## Ruling

Read-only data crosses the pipeline as a contract carried by the types
on every platform, and each platform enforces it at the earliest point it can state:

- Haxe source exposes decoded collections as the `ReadOnlyArray<T>` abstract
  and decoded records as all-`final` typedefs. The abstract provides the
  signal the generator consumes; mutation does not typecheck, and no new
  rejection row is required.
- TypeScript decode returns carry `readonly` members and `readonly` array
  types, and every decode boundary applies `DecodeBoundaryFreeze`: each
  record object, its nested objects, and the array become frozen before
  return. Mutation throws `TypeError` in strict mode at the mutation
  site. Encode and every read-only consumer accept `readonly` inputs; the
  sort runtime sorts its input array in place, so callers pass owned mutable
  storage and decoded output never enters it, per
  `docs/specs/features/17-sorting.md`.
- Kotlin decode returns `List<GlyphMetrics>` built by `ArrayInitializerFill`
  and exposed through `AsListReadView`; record classes declare `val`
  properties only. `add` and `remove` on the view throw
  `UnsupportedOperationException`; element writes have no pathway through
  the interface.
- Rust relies on borrows: read-only consumption takes `&[GlyphMetrics]` and
  `&GlyphMetrics`, and mutation fails compilation in the consumer. Where a
  lowering would emit a mutation of a value whose Haxe type is read-only,
  the generator plants a `compile_error!` with the named message
  `mutation of read-only value has no Rust lowering`; mutable access is
  never generated.

Mutation failure identity is not part of the shared error taxonomy of
`docs/specs/features/06-errors-and-results.md`: the platform's own failure
(TypeError, UnsupportedOperationException, compile error) is the observable,
and tests assert its class, never a message string.

## Test hooks

- `tests/ts/read-only.test.ts` asserts that slot assignment and `push` on a
  decoded vector throw `TypeError`, that field assignment on a decoded
  record throws `TypeError`, and that the JSON boundary output is frozen the
  same way.
- The Kotlin read-only contract is enforced at compile time: `decode` returns
  `List<GlyphMetrics>`, which carries no `add` or `remove`, and
  `tests/kotlin/Main.kt` consuming the decoded value through that type is
  the proof. The runtime `UnsupportedOperationException` of the underlying
  view is reachable only through casts or Java callers; the tree bans casts,
  so no test exercises it.
- The Haxe tree enforces at compile time; `bun run test:haxe` compiling the
  `ReadOnlyArray` type is the positive proof, and the cast pathway is
  rejection `V05`.
- Rust enforces at compile time through borrows in the signatures shown
  above; no runtime hook exists by design.
