# Feature spec 09: Iterators

## Scope

This specification rules the translation of Haxe loop constructs, iterator interfaces, range iterations, the iteration forms permitted in codec code and generated code, the ban on iterator-protocol loops on the JavaScript target, and the closure allocation rules for translated loop bodies. In the current codebase, iteration appears in Haxe in `haxe/src/boring/VectorCodec.hx`, `haxe/src/boring/BinaryReader.hx`, and `haxe/src/boring/BinaryWriter.hx`, in Rust in `rust/src/lib.rs`, in TypeScript in `ts/src/vector-format.ts` and `ts/src/codec.ts`, and in Kotlin in `kotlin/src/boring/VectorCodec.kt`, where the counted fill renders as the array initializer and the traversals render as `indices` loops.

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

The `for (item in collection)` loop desugars to `var _it = collection.iterator(); while (_it.hasNext()) { var item = _it.next(); ... }`. Numeric range loops `for (i in 0...count)` construct an `IntIterator(min, max)` instance that increments an integer cursor on each step. The Haxe compiler lowers array and range loops to indexed loops on the JavaScript target when the subject is statically an `Array` or a range; a subject typed `Iterator<T>` or `Iterable<T>` lowers to the iterator protocol on every target.

The translatable subset restricts loops as ruled below: array iteration is written `for (i in 0...array.length)` with `array[i]` access, and a `for (item in collection)` loop whose subject is not an integer range is rejected before generation by the interception defined in `docs/specs/style/01-haxe-style-standard.md`.

Haxe also offers functional iteration forms: the `Lambda` module functions and the array methods accepting arrow functions such as `array.map(item -> item.codePoint)` and `array.filter(...)`. These forms allocate a closure per invocation and one intermediate collection per stage; this specification bans them in codec code as ruled below.

In the Haxe typed AST, loops are represented by `haxe.macro.TypedExprDef.TFor(v:TVar, e1:TypedExpr, e2:TypedExpr)` and `haxe.macro.TypedExprDef.TWhile(econd:TypedExpr, e:TypedExpr, normalWhile:Bool)`. Range creation `min...max` produces `haxe.macro.TypedExprDef.TBinop(OpInterval, e1, e2)`. The subject type of a `TFor` over anything except an `OpInterval` range is the signal the interception uses to reject iterator-protocol loops.

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
		records[index] = {
			codePoint: codePoint,
			advanceEm: advanceEm,
			bounds: { xMin: xMin, yMin: yMin, xMax: xMax, yMax: yMax }
		};
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
  const count = records.length;
  writer.writeU32(count);
  for (let i = 0; i < count; i += 1) {
    const record = records[i]!;
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
  const records: GlyphMetricsRecord[] = new Array<GlyphMetricsRecord>(count);
  for (let i = 0; i < count; i += 1) {
    const codePoint = reader.readU32();
    const advanceEm = reader.readF64();
    const xMin = reader.readF64();
    const yMin = reader.readF64();
    const xMax = reader.readF64();
    const yMax = reader.readF64();
    const bounds = { xMin, yMin, xMax, yMax };
    records[i] = { codePoint, advanceEm, bounds };
  }
  return records;
}
```

## Candidate translations

### Rust Candidate 1: Direct for-in loop over slices and range expressions (selected)

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

### TypeScript Candidate 1: Indexed for loop as the only array iteration form (selected)

```ts
const count = records.length;
for (let i = 0; i < count; i += 1) {
  writeRecord(writer, records[i]!);
}

const records = new Array<T>(count);
for (let i = 0; i < count; i += 1) {
  records[i] = readRecord(reader);
}
```

### TypeScript Candidate 2: for-of loop over arrays

```ts
for (const record of records) {
  writeRecord(writer, record);
}
```

### TypeScript Candidate 3: Generator function yielding decoded items lazily

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

### Kotlin Candidate 1: Range and indices loops with indexed access (selected)

```kotlin
for (i in records.indices) {
    writeRecord(writer, records[i])
}

for (i in 0 until count) {
    records.add(readRecord(reader))
}
```

### Kotlin Candidate 2: Direct for-in over collections and ranges

```kotlin
for (record in records) {
    writeRecord(writer, record)
}

for (i in 0 until count) {
    records.add(readRecord(reader))
}
```

### Kotlin Candidate 3: Functional collection pipeline

```kotlin
val bytes: List<Int> = records.flatMap { record ->
    record.toByteArray().toList()
}
```

### Kotlin Candidate 4: Array initializer for counted fills (selected for fills)

```kotlin
val records = Array(count) { index ->
    readRecord(reader)
}
```

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Rust Candidate 1 (Direct loop and range) | The compiler unrolls bounded loops and optimizes slice bounds checks in place. | Control flow and error propagation points remain visible in source code. | Loop bodies execute directly without helper closures or trait machinery. | Standard Rust loop syntax communicates sequential processing directly. |
| Rust Candidate 2 (Iterator collect) | Range and slice adapters monomorphize into the same loop the direct form writes; the runtime cost equals the direct loop. | Error state handling inside iterator chains obscures the exact failure point. | Adapter chains require additional error wrapping and mapping types. | Functional iterator pipelines introduce chain layers into procedural codecs. |
| TS Candidate 1 (Indexed loop) | Indexed loops lower to a counter, a bounds compare, and a direct element load; the cost is fixed by the statement itself on every engine. | Loop index bounds and collection access are stated explicitly. | Index iterations map directly across arrays without wrapper objects. | Standard loop constructs state traversal order directly. |
| TS Candidate 2 (for-of) | The loop head dispatches through the iterator protocol: a `Symbol.iterator` lookup, an iterator object, and a result object per step. Engines optimize plain arrays, and the optimization covers none of typed arrays, `arguments`, DOM lists, or subclassed arrays uniformly, so the guaranteed cost is the protocol, and the fast path is engine discretion. | The loop variable hides the index, so index-dependent work needs a manual counter alongside. | The protocol path repeats at every loop. | The element-focused head reads well and hides the mechanics. |
| TS Candidate 3 (Generator function) | Generator state machines allocate context objects on the heap for each step. | Suspended execution defers input validation until caller consumption. | Callers must manage iterator consumption and error handling across consumer boundaries. | Generator syntax adds coroutine semantics to straightforward array decoding. |
| Kotlin Candidate 1 (Range and indices) | `0 until n` and `indices` lower to index arithmetic with no iterator allocation on JVM, Android, and JS targets. | Loop bounds and collection access stay explicit in source. | No wrapper objects or lambda parameters are required. | Standard loop constructs state traversal order directly. |
| Kotlin Candidate 2 (Direct for-in) | Over `Array<T>` and ranges the compiler lowers to index arithmetic; over `Iterable<T>` including `List`, every iteration allocates one iterator object, and Kotlin/JS collections follow the same split. The element type of the subject decides the cost, so the guaranteed cost is not visible at the loop head. | The loop variable hides the index for index-dependent work. | The form is uniform with the range loops it duplicates. | The element-focused head reads well and hides the mechanics. |
| Kotlin Candidate 3 (Functional pipeline) | Each pipeline stage allocates an intermediate collection even when lambdas inline. | Error propagation points hide inside stage boundaries. | The pipeline replaces plain statements with chained calls. | Chained stages obscure the write order that the wire format fixes. |
| Kotlin Candidate 4 (Array initializer) (selected for fills) | One exact-size backing array allocation; the initializer lambda is inlined into the construction, so no growth check and no residual `add` path survives on any JVM. | The constructor argument states the element count at the allocation site, and the lambda parameter names the fill index. | The loop, its counter, and its store statement are expressed as one construction. | The declaration states the final array and how every element is computed. |

## Ruling

Array and collection iteration translates to indexed loops whose cost is fixed by the statement itself:

- Rust keeps `for item in slice` over borrowed slices and `for i in 0..count` ranges; both lower to direct iteration with no protocol dispatch and no allocation. Iterator adapters over ranges and slices carry no runtime cost over the direct loop; the direct loop stays the emitted form because the translatable subset contains loop statements only, and the loop keeps every fallible read visible at its line.
- TypeScript generated code, and all code under `ts/src`, read the iteration bound into a local before the loop and iterate with direct indexed access, in every case. The bound's placement follows its readers: a `.length` bound with an earlier reader in the block becomes a `const` ahead of that reader, so the property is read once and shared (`const count = records.length; writer.writeU32(count); for (let i = 0; i < count; i += 1)`); a bound read only by the loop declares itself in the `for` init next to the counter (`for (let i = 0, count = records.length; i < count; i += 1)`), which reads the property exactly once and keeps the name out of the block scope. Both placements are the single-read rule; the loop condition never evaluates a property access. `for...of` and `for...in` are banned. `for...of` dispatches through the iterator protocol whose fast path is engine discretion; `for...in` enumerates string keys including inherited ones and is additionally incorrect for array traversal. Millisecond-level performance budgets in the consumers of this output leave no room for a loop form whose cost an engine choice can change. A `.length` read inside the loop head executes on every iteration; keeping it out of the head is the same rule applied to the bound: the loop statement itself fixes the cost. Element reads carry a non-null assertion (`records[i]!`): the loop bound establishes the invariant, `noUncheckedIndexedAccess` stays on for every other access, and the assertion is the one place the invariant is stated. A fill whose count is known before the loop pre-allocates the destination and stores by index: `const records = new Array<T>(count); for (let i = 0; i < count; i += 1) { records[i] = readRecord(); }`, one allocation and no growth copies, per the allocation ruling in `docs/specs/stdlib/04-haxe-ds-vector.md`. A fill bound that is not structurally non-negative (a `.length` read or a non-negative integer constant) clamps the allocation as `new Array<T>(Math.max(count, 0))` while the loop condition keeps the plain bound: `new Array(n)` throws `RangeError` for a negative `n`, but the counted loop `i < n` skips, so an unclamped allocation would replace the Haxe behavior with a platform crash. The reachable case is a decoded count of -1 (0xFFFFFFFF read as a signed Int32), where Haxe skips the fill and surfaces the trailing-bytes check; the clamp preserves exactly that.
- Kotlin generated code iterates by the static subject type. Over `Array<T>` and primitive arrays, `for (item in array)` is the required form: the compiler lowers it to an indexed loop with no iterator allocation, and the contiguous traversal lets the JIT eliminate bounds checks. Over `List<T>` and other `Iterable` subjects, generated code uses `for (i in 0 until count)` with indexed access, because the element loop would otherwise allocate one `Iterator` per traversal. A fill whose count is known before the loop constructs the destination with the Kotlin array initializer `val records = Array(count) { index -> ... }` when the surface is a fixed-size array; `ArrayList(count)` with `add` remains only where the API requires a mutable list, because HotSpot eliminates part of the `add` path and not all of it, per the allocation ruling in `docs/specs/stdlib/04-haxe-ds-vector.md`.
- Haxe translatable source iterates arrays through `for (i in 0...array.length)` with `array[i]` access. A `for (item in collection)` loop whose subject is not an integer range is rejected before generation by the interception defined in `docs/specs/style/01-haxe-style-standard.md`, because its translation would require the iterator protocol on the JavaScript target.

Functional iteration is banned in Haxe source by the style standard (`V02`), so no functional construct enters the translatable subset and the generator never lowers one; generated code and the reference trees keep the direct loop forms ruled above. The cost ground is per platform: eager collection methods on JavaScript arrays and Kotlin lists materialize one intermediate collection per stage, and in a loop over records this multiplies allocations by the record count. Rust iterator adapters and Kotlin `inline` iteration functions carry no allocation; they never appear in generated code because the subset holds no functional iteration to lower. Sorting is the one exit: it goes through the named strategies of the sort runtime ruled in `docs/specs/features/17-sorting.md`. Lambda invocation cost alone is platform-dependent, because the JVM and current JavaScript engines inline monomorphic calls, and it is never the stated reason. Where a platform holds a construct with identical behavior and no intermediate allocation, such as the Kotlin array initializer for counted fills, that construct is selected on its own platform merits; the structure test encodes the per-language decisions of the judgment table.

Generator functions are banned on the decode hot path. Decoders must eagerly validate headers, parse records, and verify the trailing byte boundary before returning complete collections.

JavaScript closure lifecycle rules for translated loop bodies:

1. Loop bodies contain no function expressions, arrow functions, or bound method references. A callback that cannot be avoided is hoisted to module scope and receives all state as parameters.
2. No closure captures a loop variable. When a closure captures a `let` binding of a `for` loop, the engine allocates a fresh context object per iteration; the translation passes the index as a function parameter instead.
3. Loop bodies write into bindings declared once in the enclosing function scope. Per-iteration allocation is permitted only for the record values the wire format itself requires.

These rules exist because the JavaScript target is performance sensitive: a closure allocated inside a loop body converts a bounded, allocation-free loop into per-iteration context allocation, and the resulting garbage collection pauses dominate the runtime of the decoded payload.

## Test hooks

Loop execution and record array round trips are verified in:
- `tests/rust/vector.rs` (lines 54-70)
- `tests/haxe/Main.hx` (lines 63-68, 87-90)
- `tests/ts/codec.test.ts` (lines 42-53, 57-64)
- `tests/ts/vector.test.ts` (lines 13-25)

The ruling is guarded by:

- `tools/eslint/rules/no-functional-iteration.ts`, the `boring/no-functional-iteration` rule, banning the callback iteration methods and comparator `sort` on all files under `ts/src` (scoped in `eslint.config.ts`; tests and tools may use any form). The comparator inside the sort runtime module `ts/src/vector-sort.ts` is the features/17 exit and stays sanctioned there.
- `tests/ts/loop-structure.test.ts`, a structure test scanning every file under `ts/src`, `ts/gen`, `haxe/src`, `rust/src`, and `kotlin/src` and asserting three properties: no `.map(`, `.filter(`, `.reduce(`, `.forEach(`, `.flatMap(`, `.some(`, `.every(`, `.fold(`, or `.sortedBy(` call site exists; no function expression, arrow function, or lambda appears inside a `for` or `while` body; and every `for (` loop head under the TypeScript trees binds an index counter, matched textually by the absence of ` of ` and ` in ` inside the loop head; the head's condition section also contains no property access, so the bound evaluates per iteration as a local. The init section is exempt so it can declare the hoisted bound next to the counter; the declaration executes once, at loop entry. Comments are blanked before the scan and the loop-body check matches each language through its closure token, so doc text never reads as code. This test is the guard for generated output, where the behavior tests cannot see the shape of the code.
