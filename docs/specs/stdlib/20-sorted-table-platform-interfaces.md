# Standard library specification 20: sorted table platform interfaces

## Scope

This specification answers whether the Kotlin target presents
`std.SortedMap<K, V>` and `std.SortedSet<K>` as the platform interfaces
`Map<K, V>` and `Set<K>`, or keeps the resident table classes
`SortedMapTable<K, V>` and `SortedSetTable<K>` as the public types. It
amends [07-sorted-keyed-tables.md](07-sorted-keyed-tables.md). The question
comes from the Kotlin public-API comparison recorded with the tiqian engine
port: the hand-written platform facade declared `Set<String>` and
`Map<String, Float>`, and the generated tree declares the table types.

The scope is the type a generated signature names and the members reachable
through that type. The storage stays the parallel sorted arrays of 07. The
task that produced this specification changes no compiler, runtime, or
tiqian source; it fixes the decision and the measurements that support it.

## Current state

Each target lowers the two extern faces onto the resident classes:

- `packages/compiler/reflaxe/kotlin/kotlincompiler/KotlinType.hx:63-78`
- `packages/compiler/reflaxe/ts/tscompiler/TsType.hx:55-66`
- `packages/compiler/reflaxe/dart/dartcompiler/DartType.hx:71-74`
- `packages/compiler/reflaxe/swift/swiftcompiler/SwiftType.hx:109-128`
- `packages/compiler/reflaxe/rust/rustcompiler/RustType.hx:209-220`, with
  the class names fixed in `RustImports.hx:26-32`.

`packages/compiler/RuntimeResidents.hx:22-28` compiles
`runtime.SortedTable` into each target's runtime, and
`RuntimeResidents.hx:54-64` binds the four externs to it. The one Haxe
source is `packages/compiler/runtime/SortedTable.hx`; the committed Rust
runtime `packages/registry/gen-rust/runtime/sorted_table.rs` is its
generated face, with `pub keys: Vec<K>` and `pub values: Vec<V>` at
lines 63-66 and `has`/`size`/`key_at`/`value_at` at lines 98-112.

The Kotlin face of one resident class is emitted as:

```kotlin
class SortedMapTable<K, V>(private val keys: MutableList<K>, private val values: MutableList<V>, private val compare: (K, K) -> Int) {
    fun get(key: K): V?
    fun has(key: K): Boolean
    fun size(): Int
    fun keyAt(index: Int): K
    fun valueAt(index: Int): V
}
```

## The three conflicts (minimal reproductions)

Each reproduction is one file compiled with `kotlinc 2.4.10`.

### Conflict 1: the private field names meet the interface properties

```kotlin
class P1<K, V>(private val keys: MutableList<K>, private val values: MutableList<V>) : Map<K, V> {
    override val entries: Set<Map.Entry<K, V>> get() = throw UnsupportedOperationException()
    override val size: Int get() = keys.size
    override fun containsKey(key: K): Boolean = false
    override fun containsValue(value: V): Boolean = false
    override fun get(key: K): V? = null
    override fun isEmpty(): Boolean = keys.isEmpty()
}
```

`kotlinc` reports `'keys' hides member of supertype 'Map' and needs an
'override' modifier` on the constructor, and the same error for
`values`.

### Conflict 2: `fun size(): Int` meets `Map.size`

```kotlin
class P2b<K, V> : Map<K, V> {
    override val entries: Set<Map.Entry<K, V>> get() = throw UnsupportedOperationException()
    override val keys: Set<K> get() = throw UnsupportedOperationException()
    override val values: Collection<V> get() = throw UnsupportedOperationException()
    override fun containsKey(key: K): Boolean = false
    override fun containsValue(value: V): Boolean = false
    override fun get(key: K): V? = null
    override fun isEmpty(): Boolean = true
    override val size: Int get() = 0
    fun size(): Int = 0
}
```

`kotlinc` reports `accidental override: The following declarations have
the same JVM signature (size()I)`. With the `override val size` line
removed, it instead reports the class as not implementing `val size: Int`,
because a function does not satisfy the interface property.

### Conflict 3: the index members have no interface counterpart

```kotlin
fun useMap(m: Map<String, Int>) {
    m.has("a")
    m.keyAt(0)
    m.valueAt(0)
}

fun useSet(s: Set<Int>) {
    s.at(0)
    s.has(1)
}
```

`kotlinc` reports `unresolved reference` for `has`, `keyAt`,
`valueAt`, and `at`. The members exist on the table classes only.

The three errors together are the reason the mapping in `KotlinType.hx`
is not a one-line change.

## Candidates

### Candidate A: remap the externs to `Map` and `Set`

`KotlinType.hx` emits `Map<K, V>` and `Set<K>` for the two externs, the
resident classes implement the interfaces, and the Kotlin emitter
re-renders every index member at its call site: `has` to
`containsKey`, `size` to the `size` property, `keyAt` to
`keys.elementAt`, `valueAt` to `values.elementAt`, `at` to
`elementAt`. The generated comparison helpers
(`KotlinComparisonPlan.hx:99-108`), the record hash
(`KotlinDecl.hx:427`), and `Std.string` (`KotlinExpr.hx:5481-5491`)
carry the same rendering. The public signature becomes the interface.

### Candidate B: conform the resident class and keep the table type

The public type stays `SortedMapTable<K, V>`; the class adds
`: Map<K, V>` and `SortedSetTable<K>` adds `: Set<K>`, so a value is
assignable to the platform interface at a boundary. The index members
stay. The cost is one Kotlin-only clause beside the Haxe interfaces that
`KotlinDecl.hx:228-238` renders, plus the read-only interface members
(`keys`, `values`, `entries`, `containsValue`, `isEmpty` for the map;
`contains`, `iterator`, `containsAll`, `isEmpty` for the set), plus the
`size` property rename of conflict 2.

### Candidate C: a separate Kotlin facade class

A new Kotlin runtime class holds a table and implements `Map`/`Set`; the
externs lower onto the facade. The public type is the facade, which still
exposes the index members. The facade repeats the read-only view work of
B and adds one Kotlin-only declaration per flavor.

### Candidate D: keep the table type and convert at the boundary

No type change. A consumer that needs a platform collection calls one
explicit conversion. The shape is a copy, because 07 rules that no member
modifies the collection and a live `keys` view would hand the backing
`MutableList` to the caller as `Collection`, where a Kotlin cast can
mutate it.

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| A | Member re-rendering is compile-time; the running tables are unchanged. | A `std.SortedMap` parameter rendered as Kotlin `Map` accepts every Kotlin `Map`, including a hash map with no key order, and the index members drop out of the static type. | One Kotlin-only member-rendering rule in the emitter plus the comparison, hash, and `Std.string` sites listed above. | The emitted Kotlin reads like Kotlin, while the ordering rule of 07 is invisible at the type and the five targets no longer agree on the shape. |
| B | Assignability is free; the interface members need read-only views or copies over the backing lists, so `keys` and `entries` allocate or hold a cache. | The type is the table and also a `Map`, so both member sets are reachable; the ordering rule stays visible in the type name. | One Kotlin-only interface clause and the view members; the shared runtime source is untouched, so the other four targets keep the current shape. | The class declaration states both the table members and the interface conformance. |
| C | One wrapper allocation per built table on Kotlin; the facade still needs the read-only views or a storage copy. | The consumer sees one named class and no merge with the hash map lowering. | A second declaration per flavor on the Kotlin runtime only. | The facade name and its `Map`/`Set` conformance state the intent at the boundary. |
| D | Nothing changes; a conversion copies once at the call. | The public type names the ruled collection, so no caller misreads the ordering rule. | None; the conversion is one function per flavor when a consumer asks for it. | The consumer passes a table to a Kotlin API after one documented conversion call. |

## Five-target impact

The shared runtime is one Haxe source compiled by all five emitters
(`RuntimeResidents.hx:22-28`). Renaming `keys`/`values` or turning
`size()` into a property in that source changes the committed Rust runtime
(`packages/registry/gen-rust/runtime/sorted_table.rs:63-66,98-112`), the
TypeScript, Dart, and Swift faces, and the stage-1 assembly together. A and
B avoid that by editing the Kotlin emitter only, which makes the Kotlin
shape differ from the other four; the alternative edits every target.

- **Kotlin**: the mapping in `KotlinType.hx:63-78`; the comparison
  helpers in `KotlinComparisonPlan.hx:99-108`; the record hash in
  `KotlinDecl.hx:427`; `Std.string` in `KotlinExpr.hx:5481-5491`; the
  builder call sites in `KotlinExpr.hx:6392-6420`. `KotlinDecl.hx:361`
  records the rule that a resident keeps the shape the other targets see,
  which A and B both set aside for Kotlin.
- **TypeScript**: `TsType.hx:55-66` emits the concrete table. The Haxe
  `Map` abstract already lowers to `Map<...>` at `TsType.hx:50`, so the
  same identity merge of Candidate A applies.
- **Rust**: `RustType.hx:209-220` emits the concrete table. The runtime
  struct exposes `keys`/`values` publicly and `size` returns `i32`,
  while the standard collections use `usize`; conformance to
  `HashMap`/`BTreeMap` is not a type-system fit. No Rust change is
  proposed.
- **Dart**: `DartType.hx:71-74` emits the concrete table.
  `DartDecl.hx:351-380` already special-cases `runtime.SortedTable` for
  `==` and `hashCode`, so a Kotlin-only resident emission has a
  precedent.
- **Swift**: `SwiftType.hx:109-128` emits the concrete table. A Swift
  `Dictionary` carries no key order, so a merged interface would misstate
  the ordering rule of 07.

A, B, and C are Kotlin-only, so the cross-target consistency runs compare
behavior and the type-name difference stays on one target. D changes no
target.

## tiqian migration cost

Measured on the current tree `tiqian/engine-haxe/out/kotlin-f64/gen`:

- 84 type positions written `: Sorted(Map|Set)Table<` under `org/`, 88
  with `runtime/`; 54 in `gen-tests`; 172 lines carry the token overall.
  The quoted 89 signature positions sit in this bucket; the tree is
  regenerated per pin, so the count moves by a few between revisions.
- Under A those positions flip in one place, because they are type
  positions of the externs. No Haxe source in tiqian changes. The member
  call sites in the generated Kotlin are re-rendered by the emitter:
  `.has(` 111, `.size()` 108, `.at(` 45, `.keyAt(` 19,
  `.valueAt(` 19, across the same tree.
- Under B and D the generated signatures stay; B adds assignability at the
  boundary and D adds an explicit conversion call.
- The consumer side is the deciding cost. The platform facade was
  hand-written against `Map`/`Set`; A matches it, while B and D need one
  conversion at the boundary or a facade signature that takes the table
  type.
- Verification for any of the three: regenerate and compile the boring
  reference trees, `tiqian/engine-haxe/out/kotlin-f64`,
  `out/kotlin-f32`, and `out/protocol-kotlin`, then run
  `bun run test:kotlin`, `bun run test:stage1:kotlin`,
  `bun run test:driver:cross-target`, and
  `bun test tests/ts/kotlin-api-fidelity.test.ts`.

## Ruling

1. The extern-facing type stays the resident table on all five targets
   (Candidate D). The public type names the ruled collection and keeps
   `size`, `has`, `keyAt`, `valueAt`, and `at`.
2. Candidate A is rejected. A `std.SortedMap` parameter rendered as a
   Kotlin `Map` accepts every Kotlin `Map`, and the ordered index members
   drop out of the static type.
   `docs/specs/features/14-type-system-mapping.md:174` rules that two
   distinct named Haxe types stay distinct target types, and the Haxe
   `Map` already lowers to `MutableMap` (`KotlinType.hx:43,95-96`), so
   the remap merges the two.
   `docs/specs/stdlib/07-sorted-keyed-tables.md:35-41` rules the index
   iteration that the platform interface does not carry.
3. Candidate B is the bounded option if a consumer needs assignability
   without a call. It is not a patch: `keys` and `values` must return
   read-only views or copies, because the backing `MutableList` reaches a
   caller as `Collection` and a cast can mutate the table, and the
   `size()` member must render as the `size` property, which touches the
   call sites listed above.
4. Candidate C is recorded and not chosen: it adds a Kotlin-only
   declaration per flavor and repeats the read-only view work of B.
5. A boundary conversion is the sanctioned shape for a consumer that needs
   a platform collection, and it copies. A follow-up implements it in the
   Kotlin runtime and records the copy.

### Cost of the ruling

Keeping the table type has four costs, and each one affects the public
API:

- A generated Kotlin signature names `SortedMapTable<K, V>` or
  `SortedSetTable<K>`. The tiqian tree holds 84 such positions under
  `org/` today, and they stay concrete.
- A consumer cannot pass a generated table to a Kotlin API that takes
  `Map<K, V>` or `Set<K>` without a conversion. The conversion copies.
- The hand-written platform facade declared `Set<String>` and
  `Map<String, Float>`, so the generated type does not match that
  spelling. The facade keeps its own types and converts, or it takes the
  table type.
- The index members are the reason the two spellings cannot both be the
  public type on Kotlin: `size`, `has`, `keyAt`, `valueAt`, and `at` are
  ruled by 07 and have no interface counterpart.

## Documentation

The Kotlin target ruling to add to
[07-sorted-keyed-tables.md](07-sorted-keyed-tables.md), beside the Swift
and Dart rulings at lines 154-179:

> #### Sorted tables (`stdlib/07`)
>
> The public Kotlin types are `SortedMapTable<K, V>` and
> `SortedSetTable<K>`; they are not `kotlin.collections.Map` or
> `Set`, and the ordered index members `size`, `has`, `keyAt`,
> `valueAt`, and `at` are part of the API. A consumer that needs a
> platform collection converts at the boundary, and the conversion
> copies.

This specification stays as the record of the candidates, the three
`kotlinc` reproductions, the five-target impact, and the tiqian count.
