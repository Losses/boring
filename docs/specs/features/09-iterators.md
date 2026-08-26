# Feature spec 09: Iterators

## Scope

This specification rules the translation of Haxe loop constructs, iterator interfaces, range iterations, the functional iteration forms permitted in codec code, and the closure allocation rules for translated loop bodies on the JavaScript target. In the current codebase, iteration appears in Haxe in `haxe/src/boring/VectorCodec.hx` (lines 17, 36), `haxe/src/boring/BinaryReader.hx` (line 43), and `haxe/src/boring/BinaryWriter.hx` (line 39), in Rust in `rust/src/lib.rs` (lines 89, 108), and in TypeScript in `ts/src/vector-format.ts` (lines 19, 38) and `ts/src/codec.ts` (lines 48, 103). No Kotlin implementation exists yet; the Kotlin rulings bind generated code.

## Haxe construct

Haxe defines the iteration protocol using `Iterator<T>` and `Iterable<T>` types:

```haxe
typedef Iterator<T> = {
	function hasNext():Bool;
	function next():T;
}

typedef Iterable<T> = {
	function iterator():Iterator<T>;
}
```

The `for (item in collection)` loop desugars to `var _it = collection.iterator(); while (_it.hasNext()) { var item = _it.next(); ... }`. Numeric range loops `for (i in 0...count)` construct an `IntIterator(min, max)` instance that increments an integer cursor on each step.

Haxe also offers functional iteration forms: the `Lambda` module functions and the array methods accepting arrow functions such as `array.map(item -> item.codePoint)` and `array.filter(...)`. These forms allocate a closure per invocation and one intermediate collection per stage; this specification bans them in codec code as ruled below.

In the Haxe typed AST, loops are represented by `haxe.macro.TypedExprDef.TFor(v:TVar, e1:TypedExpr, e2:TypedExpr)` and `haxe.macro.TypedExprDef.TWhile(econd:TypedExpr, e:TypedExpr, normalWhile:Bool)`. Range creation `min...max` produces `haxe.macro.TypedExprDef.TBinop(OpInterval, e1, e2)`.

## Current translations

### Haxe (`haxe/src/boring/VectorCodec.hx`)

```haxe
public static function encode(records:Array<GlyphMetrics>):Bytes {
	final writer = new BinaryWriter();
	writer.writeAscii(MAGIC);
	writer.writeU32(records.length);
	for (record in records) {
		writer.writeU32(record.codePoint);
		writer.writeF64(record.advanceEm);
		writer.writeF64(record.bounds.xMin);
		writer.writeF64(record.bounds.yMin);
		writer.writeF64(record.bounds.xMax);
		writer.writeF64(record.bounds.yMax);
	}
	return writer.finish();
}

public static function decode(bytes:Bytes):Array<GlyphMetrics> {
	// ...
	final records = new Array<GlyphMetrics>();
	for (index in 0...count) {
		final codePoint = reader.readU32();
		// ...
		records.push({
			codePoint: codePoint,
			advanceEm: advanceEm,
			bounds: { xMin: xMin, yMin: yMin, xMax: xMax, yMax: yMax }
		});
	}
	return records;
}
```

### Rust (`rust/src/lib.rs`)

```rust
pub fn encode_vector(records: &[GlyphMetrics]) -> Result<Vec<u8>, VectorError> {
    // ...
    for record in records {
        bytes.extend_from_slice(&record.code_point.to_be_bytes());
        bytes.extend_from_slice(&record.advance_em.to_bits().to_be_bytes());
        bytes.extend_from_slice(&record.bounds.x_min.to_bits().to_be_bytes());
        bytes.extend_from_slice(&record.bounds.y_min.to_bits().to_be_bytes());
        bytes.extend_from_slice(&record.bounds.x_max.to_bits().to_be_bytes());
        bytes.extend_from_slice(&record.bounds.y_max.to_bits().to_be_bytes());
    }
    Ok(bytes)
}

pub fn decode_vector(bytes: &[u8]) -> Result<Vec<GlyphMetrics>, VectorError> {
    // ...
    let mut records = Vec::with_capacity(capacity);
    for _ in 0..count {
        let code_point = reader.read_u32()?;
        let advance_em = reader.read_f64()?;
        let x_min = reader.read_f64()?;
        let y_min = reader.read_f64()?;
        let x_max = reader.read_f64()?;
        let y_max = reader.read_f64()?;
        records.push(GlyphMetrics {
            code_point,
            advance_em,
            bounds: BoundsEm {
                x_min,
                y_min,
                x_max,
                y_max,
            },
        });
    }
    Ok(records)
}
```

### TypeScript (`ts/src/vector-format.ts`)

```ts
export function encodeVector(records: readonly GlyphMetricsRecord[]): Uint8Array {
  const writer = new BinaryWriter();
  writer.writeAscii(VECTOR_MAGIC);
  writer.writeU32(records.length);
  for (const record of records) {
    writer.writeU32(record.codePoint);
    writer.writeF64(record.advanceEm);
    writer.writeF64(record.bounds.xMin);
    writer.writeF64(record.bounds.yMin);
    writer.writeF64(record.bounds.xMax);
    writer.writeF64(record.bounds.yMax);
  }
  return writer.finish();
}

export function decodeVector(bytes: Uint8Array): GlyphMetricsRecord[] {
  // ...
  const count = reader.readU32();
  const records: GlyphMetricsRecord[] = [];
  for (let i = 0; i < count; i += 1) {
    const codePoint = reader.readU32();
    const advanceEm = reader.readF64();
    const xMin = reader.readF64();
    const yMin = reader.readF64();
    const xMax = reader.readF64();
    const yMax = reader.readF64();
    const bounds = { xMin, yMin, xMax, yMax };
    records.push({ codePoint, advanceEm, bounds });
  }
  return records;
}
```

## Candidate translations

### Rust Candidate 1: Direct for-in loop over slices and range expressions

```rust
for record in records {
    encode_record(&mut bytes, record);
}

for _ in 0..count {
    records.push(decode_record(&mut reader)?);
}
```

### Rust Candidate 2: Lazy iterator adapter pipeline with collect

```rust
let records: Result<Vec<GlyphMetrics>, VectorError> = (0..count)
    .map(|_| decode_record(&mut reader))
    .collect();
```

### TypeScript Candidate 1: Standard for-of loop and indexed for loop

```ts
for (const record of records) {
  writeRecord(writer, record);
}

for (let i = 0; i < count; i += 1) {
  records.push(readRecord(reader));
}
```

### TypeScript Candidate 2: Generator function yielding decoded items lazily

```ts
export function* decodeVectorLazy(
  reader: BinaryReader,
  count: number,
): IterableIterator<GlyphMetricsRecord> {
  for (let i = 0; i < count; i += 1) {
    yield readRecord(reader);
  }
}
```

### Kotlin Candidate 1: for-in loop over collections and ranges

```kotlin
for (record in records) {
    writeRecord(writer, record)
}

for (i in 0 until count) {
    records.add(readRecord(reader))
}
```

### Kotlin Candidate 2: Functional collection pipeline

```kotlin
val bytes: List<Int> = records.flatMap { record ->
    record.toByteArray().toList()
}
```

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Rust Candidate 1 (Direct loop and range) | The compiler unrolls bounded loops and optimizes slice bounds checks in place. | Control flow and error propagation points remain visible in source code. | Loop bodies execute directly without helper closures or trait machinery. | Standard Rust loop syntax communicates sequential processing directly. |
| Rust Candidate 2 (Iterator collect) | Closure allocations and deferred error propagation through collect complicate inlining. | Error state handling inside iterator chains obscures the exact failure point. | Adapter chains require additional error wrapping and mapping types. | Functional iterator pipelines introduce closure layers into procedural codecs. |
| TS Candidate 1 (for-of and index loop) | Direct loops execute on JavaScript engines without iterator allocation overhead. | Loop index bounds and collection access are stated explicitly. | Index iterations map directly across arrays without wrapper objects. | Standard loop constructs state traversal order directly. |
| TS Candidate 2 (Generator function) | Generator state machines allocate context objects on the heap for each step. | Suspended execution defers input validation until caller consumption. | Callers must manage iterator consumption and error handling across consumer boundaries. | Generator syntax adds coroutine semantics to straightforward array decoding. |
| Kotlin Candidate 1 (for-in and range) | Direct loops compile to index arithmetic with no iterator allocation over arrays and ranges. | Loop bounds and collection access stay explicit in source. | No wrapper objects or lambda parameters are required. | Standard loop constructs state traversal order directly. |
| Kotlin Candidate 2 (Functional pipeline) | Each pipeline stage allocates an intermediate collection even when lambdas inline. | Error propagation points hide inside stage boundaries. | The pipeline replaces plain statements with chained calls. | Chained stages obscure the write order that the wire format fixes. |

## Ruling

Haxe collection loops translate to direct `for` loops in Rust over borrowed slices (`for item in slice`), `for (const item of array)` in TypeScript, and `for (item in array)` in Kotlin, while range loops translate to integer range loops `for _ in 0..count` in Rust, indexed `for (let i = 0; i < count; i += 1)` in TypeScript, and `for (i in 0 until count)` in Kotlin.

Functional iteration is banned in codec code and generated code on every path in all four languages. Banned constructs: `map`, `filter`, `reduce`, `forEach`, `flatMap`, `find`, `some`, `every`, and comparator-closure `sort` in Haxe and TypeScript; iterator adapter chains such as `.iter().map(...).filter(...).collect()` in Rust; `map`, `filter`, `forEach`, `flatMap`, `fold`, `sortedBy`, and comparator lambdas over collections in Kotlin. Every such construct rewrites to a plain `for` or `while` loop before translation. Each functional stage allocates a closure and an intermediate collection; in a loop over records this multiplies allocations by the record count and moves runtime into garbage collection. Kotlin standard library iteration functions inline their lambdas, which lowers the runtime cost on JVM; the ban holds anyway because the generated code shape stays uniform across languages and reviewable by the structure test below.

Generator functions are banned on the decode hot path. Decoders must eagerly validate headers, parse records, and verify the trailing byte boundary before returning complete collections.

JavaScript closure lifecycle rules for translated loop bodies:

1. Loop bodies contain no function expressions, arrow functions, or bound method references. A callback that cannot be avoided is hoisted to module scope and receives all state as parameters.
2. No closure captures a loop variable. When a closure captures a `let` binding of a `for` loop, the engine allocates a fresh context object per iteration; the translation passes the index as a function parameter instead.
3. Loop bodies write into bindings declared once in the enclosing function scope. Per-iteration allocation is permitted only for the record values the wire format itself requires.

These rules exist because the JavaScript target is performance sensitive: a closure allocated inside a loop body converts a bounded, allocation-free loop into per-iteration context allocation, and the resulting garbage collection pauses dominate the runtime of the decoded payload.

## Test hooks

Loop execution and record array round trips are verified in:
- `tests/rust/vector.rs` (lines 54-70)
- `tests/haxe/Main.hx` (lines 60-66, 79-88)
- `tests/ts/codec.test.ts` (lines 42-53, 57-64)
- `tests/ts/vector.test.ts` (lines 13-25)

The following guards are required by this specification and do not exist yet:

- An eslint rule named `boring/no-functional-iteration` bans the array iteration methods listed in the ruling on all files under `ts/src` (implemented in `tools/eslint`).
- A structure test scans every file under `ts/src`, `haxe/src`, `rust/src`, and `kt/src` and asserts two properties: no `.map(`, `.filter(`, `.reduce(`, `.forEach(`, `.flatMap(`, `.some(`, `.every(`, `.fold(`, or `.sortedBy(` call site exists, and no function expression, arrow function, or lambda appears inside a `for` or `while` body. This test is the guard for generated output, where the behavior tests cannot see the shape of the code.
