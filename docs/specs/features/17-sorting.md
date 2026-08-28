# Feature spec 17: Sorting runtime

## Scope

This specification rules sorting. Comparator sort is banned in codec code and generated code (`docs/specs/features/09-iterators.md`, `V02 FunctionalIteration` in `docs/specs/style/01-haxe-style-standard.md`), so the library provides the exit itself: a sort runtime with a fixed set of named strategies. Codec code calls a named strategy; it never writes a comparator, a key selector, or a hand-rolled sort loop. The sorting needs of the downstream consumers are fixed and few, so the strategy set is small and each strategy is a named function with a concrete key. Adding a strategy is a specification amendment, so the set cannot grow silently.

The spec defines the strategy set, the Haxe API, the per-platform bodies, the stability contract that fixes behavior across languages, and the structure tests that keep comparator sorting out of codec code.

## Haxe construct

The runtime is one class with one static function per strategy. The initial set has one member:

```haxe
class VectorSort {
	/**
		Sorts records in place by code point, ascending, stable. Returns the
		same array. The Haxe body is the semantic reference; every platform
		body must produce the identical output array for the identical input.
	**/
	public static function byCodePoint(records:Array<GlyphMetrics>):Array<GlyphMetrics> {
		for (write in 1...records.length) {
			final record = records[write];
			var read = write - 1;
			while (read >= 0 && records[read].codePoint > record.codePoint) {
				records[read + 1] = records[read];
				read -= 1;
			}
			records[read + 1] = record;
		}
		return records;
	}
}
```

Two rules bind every strategy:

1. **Named key, concrete type.** A strategy names the record type and the key; there is no key-selector parameter. A function value at the strategy boundary would reintroduce the closure allocation and the review burden the comparator ban removed.
2. **In place, ascending, stable.** The function sorts the given array and returns that array. Stability is the cross-language contract: for equal keys, output order equals input order, so every implementation produces the identical array without sharing code.

## Current translations

No sort exists in the current codebase. `samples/boring/VectorCodec.hx`, `reference/rust/src/lib.rs`, and `reference/ts/src/vector-format.ts` all iterate records in stored order. The Kotlin tree does not exist yet; its rulings bind generated code.

## Candidate translations

The platform body is runtime code, so translation maps a strategy call to the platform function and never translates the Haxe body. The decision below is the JavaScript body; the other platforms have one candidate each because the platform stable sort is the known-best implementation.

### JavaScript Candidate 1: Decorate, comparator sort, undecorate

```ts
export function vectorSortByCodePoint(records: GlyphMetricsRecord[]): GlyphMetricsRecord[] {
  const count = records.length;
  const indices = new Array<number>(count);
  for (let i = 0; i < count; i += 1) {
    indices[i] = i;
  }
  indices.sort((a, b) => records[a].codePoint - records[b].codePoint || a - b);
  const output = new Array<GlyphMetricsRecord>(count);
  for (let i = 0; i < count; i += 1) {
    output[i] = records[indices[i]];
  }
  return copyInto(records, output);
}

function copyInto(target: GlyphMetricsRecord[], source: GlyphMetricsRecord[]): GlyphMetricsRecord[] {
  const count = source.length;
  for (let i = 0; i < count; i += 1) {
    target[i] = source[i];
  }
  return target;
}
```

One code path for every size. The comparator closure runs twice per comparison through the engine's generic call machinery, and the `sort` entry point with a comparator takes the engine's generic path.

### JavaScript Candidate 2: Size tiers, packed numeric sort for integer keys (selected)

```ts
export function vectorSortByCodePoint(records: GlyphMetricsRecord[]): GlyphMetricsRecord[] {
  const count = records.length;
  if (count <= 32) {
    insertionSortByCodePoint(records, count);
    return records;
  }
  // Code points below 2^21 with indices below 2^32 pack exactly into one
  // float64: key * 2^32 + index < 2^53. A Float64Array sort with no
  // comparator runs the engine's native numeric sort, and the index in the
  // low bits breaks ties in input order, which is stability.
  const packed = new Float64Array(count);
  let packable = true;
  for (let i = 0; i < count; i += 1) {
    const key = records[i]!.codePoint;
    if (key >= 2097152) {
      packable = false;
      break;
    }
    packed[i] = key * 4294967296 + i;
  }
  if (packable) {
    packed.sort();
    const source = records.slice();
    for (let i = 0; i < count; i += 1) {
      records[i] = source[packed[i] % 4294967296];
    }
    return records;
  }
  return decoratedSortByCodePoint(records, count);
}
```

Three tiers. At most 32 elements: insertion sort on the records, zero allocation. Integer keys in range: one `Float64Array`, one comparator-free numeric sort in engine-native code, one permutation pass. Keys outside the pack range, from a future strategy with unbounded integer or float keys: the decorated fallback keeps the function total without a new error variant. The bodies of `insertionSortByCodePoint` and `decoratedSortByCodePoint` live in the runtime module `reference/ts/src/vector-sort.ts`.

### JavaScript Candidate 3: Hand-written merge sort

A bottom-up merge sort over the records with a scratch array, no engine `sort` at any size. Full algorithmic control and identical code on every engine, at the cost of JavaScript-level merge loops competing with the engine's native sort implementation.

### Rust candidate: Platform stable sort

```rust
pub fn vector_sort_by_code_point(records: &mut [GlyphMetrics]) -> &mut [GlyphMetrics] {
    records.sort_by_key(|record| record.code_point);
    records
}
```

### Kotlin candidate: Platform stable sort

```kotlin
fun vectorSortByCodePoint(records: MutableList<GlyphMetrics>): MutableList<GlyphMetrics> {
    records.sortBy { it.codePoint }
    return records
}
```

`MutableList.sortBy` is the common multiplatform declaration; the JVM actual lowers to TimSort and the JS actual to the stable array sort. The container type follows the data model the Kotlin tree settles on in its implementation; the ruling below binds behavior, with the container shape an implementation detail.

## Judgment

| Candidate | Performance | Ambiguity | Redundancy | Readability |
|---|---|---|---|---|
| JavaScript C1 (Decorate + comparator) | One code path for every size; the comparator closure executes twice per comparison through generic call machinery, and the engine takes its generic sort path. | None; a single deterministic algorithm. | The comparator is the one sanctioned closure in the runtime, a standing exception to audit. | The decorate and undecorate passes state the mechanism plainly. |
| JavaScript C2 (Size tiers, packed numeric) | Insertion sort at 32 elements and below allocates nothing; the packed tier runs the engine's native numeric sort with no comparator calls and one `Float64Array`; only the out-of-range fallback pays the comparator cost. | Three tiers means three behaviors to verify; the identity test below fixes the observable behavior to one output array. | The packing arithmetic and the 2^21 domain check exist only for speed. | The packing comment states the domain and the stability argument in place. |
| JavaScript C3 (Hand-written merge sort) | JavaScript-level merge loops against the engine's native sort implementation; the extra scratch array allocates on every call. | None; a single deterministic algorithm. | A second sort implementation to maintain beside the engine's. | Merge structure reads plainly but adds a page of code the engine already provides. |
| Rust (Platform stable sort) | `sort_by_key` is the standard library stable sort; no allocation, no protocol dispatch. | None. | None; one line. | Standard library call, self-describing. |
| Kotlin (Platform stable sort) | `MutableList.sortBy` lowers to TimSort on JVM and to the stable array sort on the JS target; one selector invocation per comparison. | None. | None; one line. | Standard library call, self-describing. |

## Ruling

1. The sort runtime is the only legal sorting path in codec code and generated code. A call to a named strategy of `VectorSort` translates to the platform function; the Haxe body is the semantic reference and is never translated. The comparator ban of `docs/specs/features/09-iterators.md` and the `V02` rejection both point here as the exit.
2. The JavaScript body is Candidate 2. The performance values decide: the comparator-free numeric sort is the fastest sort primitive JavaScript exposes, the insertion tier removes all allocation from the small case, and the fallback tier keeps the function total. Candidate 1 is the fallback tier's algorithm, so the fallback stays exercised through the same identity suite once a strategy with unbounded keys joins the set; `byCodePoint` keys stay in the scalar value domain and never reach the fallback.
3. Rust and Kotlin reuse the platform stable sort, per the standing values: the platform implementations are already the fastest stable sorts available on those trees, so the runtime adds no algorithm of its own.
4. Every strategy on every platform is ascending, in place, and stable. Stability is the identity contract: for the same input array, the four trees produce the same output array, verified by the test hooks below without shared code.
5. A new sorting need is a new named strategy and a specification amendment to this file. The set starts with `byCodePoint` because that is the one need the downstream consumers have named.
6. The `sortedBy` expansion of `docs/specs/macros/01-functional-idiom-expansion.md` is the one exception to the named-strategy set: its comparator is generated from the key expression at expansion time and never exists as a source value, so the "no key-selector parameter" boundary of rule 1 holds at the source level while the generated code carries the platform sort with the inlined key. The sort is stable, ascending, and returns a new array on every platform, including the haxe stage-1 shim.

## Test hooks

- `tests/ts/vector-sort.test.ts` sorts a fixed shuffled input array and a fixed equal-key input array (both inline constants) and asserts the sorted key sequence, the stability of equal-key runs, and that the return value is the input array instance.
- `tests/haxe/Main.hx` runs the same two input arrays against `VectorSort.byCodePoint` and asserts the same expectations.
- `tests/rust/vector.rs` runs the same two input arrays against `vector_sort_by_code_point` and asserts the same expectations.
- An identity test runs the same shuffled input through the Haxe, TypeScript, and Rust trees and asserts the three output code point sequences are equal element for element.
- A structure test scans `reference/ts/src` and asserts the only `sort(` call sites with a comparator are inside `reference/ts/src/vector-sort.ts`.
