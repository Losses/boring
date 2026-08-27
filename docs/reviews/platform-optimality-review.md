# Platform-optimality review (2026-08-26)

## Verdict table

| spec | ruling | verdict | better construct | platforms affected |
| --- | --- | --- | --- | --- |
| `binary/01-wire-format.md` | Fixed 8-byte header and 44-byte record binary layout | OK | - | None |
| `binary/01-wire-format.md` | Big-endian network byte order for numeric fields | OK | - | None |
| `binary/01-wire-format.md` | Dyadic-rational test values for reproducible float bit patterns | OK | - | None |
| `binary/02-binary-meta-abstraction.md` | FormatDef macro schema and Reflaxe build-time code generation | OK | - | None |
| `binary/03-diff-localization.md` | Deterministic byte offset to field localization mapping | OK | - | None |
| `binary/04-key-index-retrieval.md` | Candidate 1 flat path-joined accessors with positional parameters | OK | - | None |
| `binary/04-key-index-retrieval.md` | Finite format tree constraint and RecursionInFormat error | OK | - | None |
| `features/01-enums-and-pattern-matching.md` | Rust tagged union enums with unboxed payloads | OK | - | None |
| `features/01-enums-and-pattern-matching.md` | TypeScript discriminated union interfaces with literal or symbol tags | OK | - | None |
| `features/01-enums-and-pattern-matching.md` | Kotlin sealed interface with data objects and data classes | OK | - | None |
| `features/01-enums-and-pattern-matching.md` | Pattern matching lowering via match, switch, and when | OK | - | None |
| `features/02-abstract-types.md` | Hot-path primitive type aliases across all platforms | OK | - | None |
| `features/02-abstract-types.md` | Ingestion boundaries: Rust newtype, TypeScript brand, Kotlin value class | OK | - | None |
| `features/03-structures-and-typedefs.md` | Rust structs with derived traits, TypeScript readonly interfaces, Kotlin data classes | OK | - | None |
| `features/04-null-safety-and-optionality.md` | Rust Option, TypeScript optional properties, Kotlin nullable types | OK | - | None |
| `features/04-null-safety-and-optionality.md` | Prohibition of in-band sentinel values | OK | - | None |
| `features/05-generics.md` | Monomorphized static generics in Rust; erased generics with bounds in TypeScript and Kotlin | OK | - | None |
| `features/05-generics.md` | Ban on runtime type inspection and Kotlin reified type parameters | OK | - | None |
| `features/06-errors-and-results.md` | Rust Result with closed error variants; TypeScript VectorException with union payload; Kotlin sealed VectorException | OK | - | None |
| `features/06-errors-and-results.md` | Closed error variant taxonomy; prohibition of message-string discrimination | OK | - | None |
| `features/07-numeric-tower.md` | Code points as 32-bit integers; metrics as 64-bit floats | OK | - | None |
| `features/07-numeric-tower.md` | Fixed wire type table; prohibition of BigInt and Long for 32-bit values | OK | - | None |
| `features/08-strings-and-unicode.md` | Unicode code points as 32-bit unsigned integers; ASCII markers as byte arrays or ASCII strings | OK | - | None |
| `features/08-strings-and-unicode.md` | Ban on Kotlin Char and Rust char for 32-bit code points | OK | - | None |
| `features/09-iterators.md` | TypeScript indexed loop with pre-bound length and index store | OK | - | None |
| `features/09-iterators.md` | Ban on direct for-in iteration over Kotlin Array subjects | IMPOSED-VALUE | `for (item in array)` direct array iteration | Kotlin |
| `features/09-iterators.md` | Blanket ban on functional iteration across all four languages | SUBOPTIMAL | Zero-cost Rust iterator adapters; inline Kotlin collection functions | Rust, Kotlin |
| `features/10-static-extension.md` | Rust impl blocks; TypeScript exported module functions; Kotlin extension functions | OK | - | None |
| `features/10-static-extension.md` | Prohibition of TypeScript prototype augmentation | OK | - | None |
| `features/11-inline-and-macros.md` | Rust pub const and const fn; TypeScript export const; Kotlin const val and inline fun | OK | - | None |
| `features/11-inline-and-macros.md` | Compile-time Reflaxe code generation; ban on runtime macros and reflection | OK | - | None |
| `features/12-classes-interfaces-access.md` | Stateful classes with private members and public constructors | OK | - | None |
| `features/12-classes-interfaces-access.md` | TypeScript interface method signature ban; data-only interfaces | OK | - | None |
| `features/13-metadata-and-reflection.md` | Build-time metadata processing; ban on runtime reflection across all targets | OK | - | None |
| `features/14-type-system-mapping.md` | Fixed type mapping table and nominal type identity preservation | OK | - | None |
| `features/15-control-flow.md` | Direct control flow mapping to native jumps, match, switch, and when | OK | - | None |
| `features/15-control-flow.md` | Judgment table Redundancy and Readability cells citing one-to-one construct correspondence | IMPOSED-VALUE | Direct platform jump efficiency justification | All |
| `features/16-static-object-access.md` | Direct property access on native record shapes; monomorphic hidden classes | OK | - | None |
| `features/16-static-object-access.md` | Ban on string-keyed bracket access and dynamic property mutations | OK | - | None |
| `features/17-sorting.md` | Named sort strategies in VectorSort with ascending, in-place, stable contract | OK | - | None |
| `features/17-sorting.md` | JavaScript three-tier sort with packed Float64Array numeric sort | OK | - | None |
| `features/17-sorting.md` | Rust slice sort_by_key and Kotlin platform sort | OK | - | None |
| `features/18-immutability.md` | Haxe ReadOnlyArray abstract over Array with zero runtime overhead | OK | - | None |
| `features/18-immutability.md` | TypeScript DecodeBoundaryFreeze Object.freeze( calls on every decoded object | SUBOPTIMAL | Static readonly type annotations without runtime Object.freeze( | TypeScript |
| `features/18-immutability.md` | Kotlin asList view allocation over decoded backing Array | SUBOPTIMAL | Return Array<T> directly or use unboxed arrays | Kotlin |
| `features/18-immutability.md` | Rust compile_error! mutator shims | IMPOSED-VALUE | Native Rust borrow checker compiler diagnostics | Rust |
| `stdlib/01-haxe-io-bytes.md` | Rust &[u8] and Vec<u8>; TypeScript Uint8Array; Kotlin ByteArray | OK | - | None |
| `stdlib/02-haxe-io-buffers-and-inputs.md` | Rust from_be_bytes with split_first_chunk; TypeScript DataView big-endian false; Kotlin shift assembly | OK | - | None |
| `stdlib/03-haxe-exception.md` | haxe.Exception translation to Result, VectorException union, and sealed exceptions | OK | - | None |
| `stdlib/04-haxe-ds-vector.md` | Rust Vec::with_capacity; TypeScript new Array(count); Kotlin Array(count) initializer | OK | - | None |
| `stdlib/04-haxe-ds-vector.md` | Build-time constant array unrolling and literal integer folding | OK | - | None |
| `stdlib/04-haxe-ds-vector.md` | Kotlin ArrayList(count) residual rule for mutable list requirements | OK | - | None |
| `stdlib/05-haxe-int64.md` | Rust u64/i64; TypeScript bigint use-case standard; Kotlin Long standard | OK | - | None |
| `stdlib/05-haxe-int64.md` | Floating-point bit conversions via from_bits, to_bits, and DataView | OK | - | None |
| `style/01-haxe-style-standard.md` | Style standard rules 1-7 and interception table V01-V15 | OK | - | None |

## Findings

### F1 Blanket functional-iteration ban on zero-cost platforms
- Spec and line: `docs/specs/features/09-iterators.md`, lines 265-266, and `docs/specs/style/01-haxe-style-standard.md`, line 51 (`V02 FunctionalIteration`).
- Quoted ruling: "Functional iteration is banned in codec code and generated code on every path in all four languages. Banned constructs: `map`, `filter`, `reduce`, `forEach`, `flatMap`, `find`, `some`, `every`, and comparator-closure `sort` in Haxe and TypeScript; iterator adapter chains such as `.iter().map(...).filter(...).collect()` in Rust; `map`, `filter`, `forEach`, `flatMap`, `fold`, `sortedBy`, and comparator lambdas over collections in Kotlin. Every such construct rewrites to a plain `for` or `while` loop before translation ... The ground of the ban is allocation: every pipeline stage materializes one intermediate collection regardless of platform, and in a loop over records this multiplies allocations by the record count."
- Verdict: SUBOPTIMAL and IMPOSED-VALUE.
- Evidence:
  1. Rust iterator adapters (`.iter()`, `.map()`, `.filter()`, `.take()`) are lazy zero-cost combinators implementing the `Iterator` trait. The LLVM compiler backend monomorphizes and inlines adapter pipelines into identical loop headers, vectorizing SIMD operations where possible. Zero heap allocations or intermediate collections occur before `.collect()`. The statement that "every pipeline stage materializes one intermediate collection regardless of platform" is mechanically incorrect for Rust.
  2. Kotlin standard library functions such as `forEach`, `first`, `any`, `all`, `none`, `count`, `minOrNull`, and `maxOrNull` are declared with the `inline` modifier (`inline fun <T> Iterable<T>.forEach(action: (T) -> Unit)`). The Kotlin compiler inlines the lambda body directly into the caller bytecode, creating zero closure allocations, zero interface dispatch overhead, and zero intermediate collections. Kotlin `Sequence` chains (`asSequence().map { ... }.filter { ... }`) also perform single-pass lazy element processing without intermediate collection allocations.
  3. Intermediate collection allocation occurs on eager JavaScript array methods (`Array.prototype.map`, `Array.prototype.filter`) and eager Kotlin `List` transformations. Imposing a blanket ban across Rust and Kotlin because JavaScript allocates collections forces cross-language shape uniformity and deprives Rust and Kotlin of their fastest sound idioms.
- Proposed replacement ruling text:
  "Functional iteration is governed per platform by allocation and inlining behavior:
  - TypeScript and Haxe: Eager collection methods that materialize intermediate arrays (`map`, `filter`, `flatMap`, `reduce`, `concat`) are banned on codec hot paths. Direct procedural indexed loops remain the required emission form.
  - Rust: Iterator adapter pipelines (`.iter()`, `.map()`, `.filter()`, `.enumerate()`) compile through monomorphization to zero-allocation native loops and are permitted. Terminal collection into heap vectors via `.collect()` is permitted when a newly allocated container is explicitly required.
  - Kotlin: Inline standard library iteration functions (`forEach`, `any`, `all`, `none`, `count`, `first`) inline their lambdas at the call site with zero allocation and are permitted. Eager transformations on `Iterable` that allocate intermediate `List` instances (`map`, `filter`) are banned in codec loops; lazy single-pass processing via `Sequence` or direct indexed loops must be used."

### F2 Ban on direct `for (item in collection)` for Kotlin array subjects
- Spec and line: `docs/specs/features/09-iterators.md`, line 262, and `docs/specs/style/01-haxe-style-standard.md`, line 50 (`V01 IteratorLoop`).
- Quoted ruling: "Kotlin generated code uses `for (i in 0 until count)` and `for (i in collection.indices)` with indexed access. Direct `for (item in collection)` is banned in generated code because its cost depends on the static subject type: index arithmetic over arrays and ranges, one iterator allocation per loop over `Iterable`. The indices form states the same cost on every subject."
- Verdict: IMPOSED-VALUE.
- Evidence:
  1. For subjects statically typed as Kotlin `Array<T>`, `ByteArray`, or other primitive arrays, the Kotlin compiler lowers `for (item in array)` directly to bytecode equivalent to `for (int i = 0; i < array.length; i++) { T item = array[i]; }`. It emits zero `Iterator` object allocations and zero virtual calls.
  2. Lowering to `for (i in collection.indices)` on an `Array<T>` generates an index range check on every element load `collection[i]`. Direct element iteration `for (item in array)` allows HotSpot and ART JIT compilers to eliminate bounds checks across the contiguous array traversal.
  3. The ruling states as its justification: "The indices form states the same cost on every subject." This is an explicit appeal to cross-construct uniformity and reviewability.
- Proposed replacement ruling text:
  "Kotlin iteration lowers according to the static subject type:
  - When the subject is an `Array<T>`, `ByteArray`, or primitive array, direct iteration `for (item in array)` is the required emission form, compiling to direct indexed bytecode with zero iterator allocation and optimal JIT bounds-check elimination.
  - When the subject is a `List<T>` or general `Iterable<T>`, iteration uses `for (i in 0 until collection.size)` or `collection.forEach { item -> ... }` to avoid `java.util.Iterator` allocation."

### F3 Decode boundary `Object.freeze(` overhead in TypeScript
- Spec and line: `docs/specs/features/18-immutability.md`, lines 221-224.
- Quoted ruling: "TypeScript decode returns carry `readonly` members and `readonly` array types, and every decode boundary applies `DecodeBoundaryFreeze`: each record object, its nested objects, and the array become frozen before return. Mutation throws `TypeError` in strict mode at the mutation site."
- Verdict: SUBOPTIMAL.
- Evidence:
  1. Executing `Object.freeze(` on every decoded record object, every nested `bounds` object, and the enclosing array requires `2 * N + 1` function calls per decode operation of `N` records.
  2. In V8 (Node.js, Bun, Chromium), calling `Object.freeze(` transitions an object map from a fast monomorphic struct shape to a dictionary shape descriptor. This mutation prevents TurboFan from applying optimized contiguous object allocations and degrades subsequent property read performance across consuming applications.
  3. TypeScript `readonly` type modifiers provide compile-time immutability verification across the entire TypeScript codebase with zero runtime performance cost. In Haxe, `ReadOnlyArray` is an abstract type that erases to a plain JavaScript `Array` with zero runtime locking. In Rust, immutability is enforced via static compile-time borrow checks (`&[T]`) without runtime memory protection. Requiring runtime `Object.freeze(` on TypeScript imposes a runtime penalty on the JavaScript hot path for a defensive boundary absent from the other language targets.
- Proposed replacement ruling text:
  "TypeScript enforces read-only data statically through `readonly` interface properties and `readonly T[]` return signatures. `Object.freeze(` is omitted from the hot-path decode loop, preserving fast monomorphic V8 hidden classes and zero-overhead object creation. Codebases requiring runtime isolation at untrusted host boundaries invoke `Object.freeze(` externally outside the codec hot path."

### F4 Redundant `compile_error!` mutator shims in Rust
- Spec and line: `docs/specs/features/18-immutability.md`, lines 235-238.
- Quoted ruling: "Where a lowering would emit a mutation of a value whose Haxe type is read-only, the generator plants a `compile_error!` with the named message `mutation of read-only value has no Rust lowering`; mutable access is never generated."
- Verdict: IMPOSED-VALUE.
- Evidence:
  1. Rust enforces immutability through its affine type system and borrow checker. Exposing decoded data as borrowed slices (`&[T]`) and records as shared references (`&T`) ensures that any attempt to mutate the data fails compilation with standard compiler diagnostic `E0596` (cannot borrow as mutable).
  2. Emitting synthetic mutator functions containing `compile_error!` macros adds dead scaffolding to generated Rust source. The Rust compiler rejects mutable calls on shared references without synthetic shims.
- Proposed replacement ruling text:
  "Rust enforces read-only access through borrowed references (`&[T]`, `&T`). Read-only data is exposed through non-mutable borrows, and mutation attempts are rejected directly by the native Rust borrow checker at compile time without synthetic mutator shims."

### F5 Statement-correspondence justification framing in Control Flow judgment
- Spec and line: `docs/specs/features/15-control-flow.md`, lines 168, 170, 172.
- Quoted ruling: Judgment table Redundancy cells cite "One construct in, one construct out" and Readability cells cite "Statement-level translation reads the same in source and target" for Rust Candidate 1, TS Candidate 1, and Kotlin Candidate 1.
- Verdict: IMPOSED-VALUE.
- Evidence:
  1. The project yardstick establishes that statement-level correspondence between source and target is not a requirement, and cross-language uniformity of generated shapes is not a valid justification. Citing "One construct in, one construct out" and "Statement-level translation reads the same in source and target" relies on 1:1 structural correspondence.
  2. The semantic choices themselves (lowering `if`, `while`, `match`, `when` to direct platform branches) are platform-optimal because they compile directly to native conditional jump instructions without closure or exception overhead. The judgment table entries must reflect machine instruction efficiency.
- Proposed replacement ruling text:
  Update the Judgment table for `features/15-control-flow.md` across Rust, TypeScript, and Kotlin candidate rows:
  - Redundancy: "Zero wrapper functions, dispatch tables, or intermediate jump objects."
  - Readability: "Native control flow keywords convey branch execution flow directly to platform engineers."

### F6 Kotlin `asList()` wrapper view allocation over decoded Array
- Spec and line: `docs/specs/features/18-immutability.md`, lines 228-232, and `docs/specs/stdlib/04-haxe-ds-vector.md`, line 111.
- Quoted ruling: "Kotlin decode returns `List<GlyphMetrics>` built by `ArrayInitializerFill` and exposed through `AsListReadView`; record classes declare `val` properties only. `add` and `remove` on the view throw `UnsupportedOperationException`; element writes have no pathway through the interface."
- Verdict: SUBOPTIMAL.
- Evidence:
  1. The decode operation constructs an `Array<GlyphMetrics>` via `Array(count) { ... }`, and then executes `records.asList()`. In the Kotlin standard library on the JVM, `asList()` allocates an instance of `java.util.Arrays$ArrayList` wrapping the underlying array.
  2. Every decode invocation pays an extra heap allocation for the view wrapper. Furthermore, consuming elements through `List.get(index)` requires an interface dispatch (`invokeinterface`), whereas array indexing performs a direct JVM element load (`aaload`).
  3. A Kotlin `Array<T>` has fixed length and direct indexed read access. Exposing `Array<T>` directly or wrapping in a zero-cost `@JvmInline value class` provides direct array access without allocating a `List` wrapper object on every decode call.
- Proposed replacement ruling text:
  "Kotlin decode returns `Array<GlyphMetrics>` directly, retaining the single allocation from `Array(count) { ... }` and providing direct JVM array indexing (`aaload`) without wrapper object allocation or interface dispatch overhead. Where a `List` interface is strictly required by external APIs, callers invoke `.asList()` at the API boundary."

## Central adjudication (2026-08-26)

Each finding was re-verified against the spec text and decided centrally.

- F1 (blanket functional-iteration ban): ADOPTED in part. The paragraph's
  claim that every stage materializes one intermediate collection
  regardless of platform was false for Rust iterator adapters and Kotlin
  `inline` iteration functions. features/09 now states the cost ground per
  platform and grounds the absence of functional forms in generated code
  on the translatable subset (V02 rejects them at the source). The
  proposed permission for adapters and inline functions in codec code was
  rejected: the Haxe subset holds no functional iteration to lower.
- F2 (Kotlin direct `for (item in collection)` ban): ADOPTED. The old
  reasoning appealed to one form stating the same cost on every subject.
  features/09 now rules by static subject type: direct iteration over
  arrays and primitive arrays, indexed loops over `Iterable` subjects.
  The Haxe-source interception V01 is a separate layer and stays.
- F3 (decode-boundary `Object.freeze(`): REJECTED. The repository owner
  directed the frozen-boundary design for the TypeScript tree. The
  judgment cell already states the boundary pass cost; the V8
  dictionary-shape claim does not hold for current engines, which keep
  frozen objects on fast maps.
- F4 (Rust `compile_error!` mutator shims): REJECTED. The repository
  owner named `compile_error!` as the Rust enforcement tool. The ruling
  plants shims only where a lowering would emit a mutation of a
  read-only-typed value; borrow checking covers consumer-side mutation
  and stays the first line of defense.
- F5 (control-flow judgment cells citing construct correspondence):
  ADOPTED. Six cells in features/15 carried statement-correspondence
  justifications; they now cite machine-level cost and the absence of
  wrapper machinery. The Rust Candidate 2 performance cell also claimed
  per-stage allocation for lazy adapters and was corrected.
- F6 (Kotlin `asList()` view): REJECTED as a ruling change, ADOPTED as a
  wording fix. Returning `Array<T>` removes the read-only return type that
  features/18 rules for decoded data. The one view-object allocation and
  the interface reads are now stated in the judgment cell with their JIT
  inlining behavior.
