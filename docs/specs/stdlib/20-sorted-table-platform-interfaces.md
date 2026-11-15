# Standard library specification 20: sorted table platform interfaces

## Scope

This specification answers whether the Kotlin target presents
`std.SortedMap<K, V>` and `std.SortedSet<K>` as the platform interfaces
`Map<K, V>` and `Set<K>`, or keeps the resident table classes
`SortedMapTable<K, V>` and `SortedSetTable<K>` as the public types. It
amends [07-sorted-keyed-tables.md](07-sorted-keyed-tables.md). The question
comes from the Kotlin public-API comparison recorded with the tiqian engine
port: the hand-written platform facade declared `Set<String>` and
`Map<String, Float>`, and the generated tree declared the table types.

The ruled answer is Candidate B: the resident Kotlin classes implement
`Map` and `Set`, the public type stays the table, and the backing arrays
stay the ruled parallel arrays. A consumer assigns a table to the interface
with no conversion and no element copy. The storage, the shared Haxe
runtime source, and the other four targets are untouched.

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

## The three conflicts

Before the conformance, the Kotlin face of the map class was:

```kotlin
class SortedMapTable<K, V>(private val keys: MutableList<K>, private val values: MutableList<V>, private val compare: (K, K) -> Int) {
    fun get(key: K): V?
    fun has(key: K): Boolean
    fun size(): Int
    fun keyAt(index: Int): K
    fun valueAt(index: Int): V
}
```

Each conflict is one file compiled with `kotlinc 2.4.10`.

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

## Candidates

### Candidate A: remap the externs to `Map` and `Set`

`KotlinType.hx` emits `Map<K, V>` and `Set<K>` for the two externs, the
resident classes implement the interfaces, and the Kotlin emitter
re-renders every index member at its call site. The public signature
becomes the interface.

### Candidate B: conform the resident class and keep the table type

The public type stays `SortedMapTable<K, V>`, which implements
`Map<K, V>`; `SortedSetTable<K>` implements `Set<K>`. A consumer assigns
a table to the interface at a boundary with no conversion and no element
copy, and the index members stay. This is the ruling.

### Candidate C: a separate Kotlin facade class

A new Kotlin runtime class holds a table and implements `Map`/`Set`; the
externs lower onto the facade. The facade repeats the read-only view work
of B and adds one Kotlin-only declaration per flavor. Not chosen: B already
reaches the interface from the ruled type.

### Candidate D: keep the table type and convert at the boundary

No conformance; a consumer that needs a platform collection copies. Not
chosen: the boundary copy is avoidable, so it is not a cost to pay.

## The emitted conformance

The Kotlin emitter carries the conformance for the two resident classes
only:

- `KotlinDecl.hx` adds `Map<K, V>` or `Set<K>` to the class header and
  renames the backing arrays to `_keys` and `_values`.
- The `size` member renders as `override val size: Int get()`; every
  generated call site renders `.size`.
- The map `get` renders as an override; `has`, `keyAt`, `valueAt`, and
  `at` stay as extra members.
- `keys`, `values`, and `entries` are read-only views over the backing
  arrays. The set gains `contains`, `iterator`, and `containsAll`.
- `KotlinComparisonPlan.hx` and the record hash render `.size`.

The emitted shape, validated with `kotlinc 2.4.10`, is:

```kotlin
class SortedMapTable<K, V>(private val _keys: MutableList<K>, private val _values: MutableList<V>, private val compare: (K, K) -> Int) : Map<K, V> {
    override val size: Int get() = this._keys.size
    override val keys: Set<K> = object : AbstractSet<K>() {
        override val size: Int get() = this@SortedMapTable.size
        override fun contains(element: K): Boolean = this@SortedMapTable.containsKey(element)
        override fun iterator(): Iterator<K> = object : Iterator<K> {
            private var index = 0
            override fun hasNext(): Boolean = index < this@SortedMapTable.size
            override fun next(): K = this@SortedMapTable.keyAt(index++)
        }
    }
    override val values: Collection<V> = object : AbstractCollection<V>() { /* the same index walk over valueAt */ }
    override val entries: Set<Map.Entry<K, V>> = object : AbstractSet<Map.Entry<K, V>>() { /* the same index walk over both arrays */ }
    override fun isEmpty(): Boolean = this._keys.isEmpty()
    override fun containsKey(key: K): Boolean = this.locate(key) >= 0
    override fun containsValue(value: V): Boolean = this._values.contains(value)
    override fun get(key: K): V? { /* binary search through locate */ }
    fun has(key: K): Boolean = this.locate(key) >= 0
    fun keyAt(index: Int): K = this._keys[index]
    fun valueAt(index: Int): V = this._values[index]
    // contentEquals, toString, and the private locate stay
}

class SortedSetTable<K>(private val _keys: MutableList<K>, private val compare: (K, K) -> Int) : Set<K> {
    override val size: Int get() = this._keys.size
    override fun isEmpty(): Boolean = this._keys.isEmpty()
    override fun contains(element: K): Boolean = this.locate(element) >= 0
    override fun containsAll(elements: Collection<K>): Boolean = elements.all { this.contains(it) }
    override fun iterator(): Iterator<K> = object : Iterator<K> { /* the index walk over at */ }
    fun has(key: K): Boolean = this.locate(key) >= 0
    fun at(index: Int): K = this._keys[index]
    // contentEquals, toString, and the private locate stay
}
```

A consumer passes a table where the interface is expected with no call:

```kotlin
fun acceptsMap(m: Map<String, Int>): Int = m.size
fun acceptsSet(s: Set<Int>): Int = s.size

fun exercise(t: SortedMapTable<String, Int>, u: SortedSetTable<Int>): Int {
    val m: Map<String, Int> = t
    val s: Set<Int> = u
    return acceptsMap(t) + acceptsSet(u) + m.keys.size + m.values.size + m.entries.size + s.size
        + t.keyAt(0).length + u.at(0) + t.valueAt(0)
}
```

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| A | Member re-rendering is compile-time; the running tables are unchanged. | A `std.SortedMap` parameter rendered as Kotlin `Map` accepts every Kotlin `Map`, including a hash map with no key order, and the index members drop out of the static type. | One Kotlin-only member-rendering rule in the emitter plus the comparison, hash, and `Std.string` sites. | The emitted Kotlin reads like Kotlin, while the ordering rule of 07 is invisible at the type and the five targets no longer agree on the shape. |
| B | The interface members are views over the backing arrays, so no element copy; one small view object per table property. | The type is the table and also a `Map`, so both member sets are reachable; the ordering rule stays visible in the type name. | One Kotlin-only interface clause and the view members; the shared runtime source is untouched, so the other four targets keep the current shape. | The class declaration states both the table members and the interface conformance. |
| C | One wrapper allocation per built table per flavor; the facade still needs the views of B. | The consumer sees one named class and no merge with the hash map lowering. | A second declaration per flavor on the Kotlin runtime only. | The facade name and its `Map`/`Set` conformance state the intent at the boundary. |
| D | A conversion copies at the call. | The public type names the ruled collection. | None; the conversion is one function per flavor. | The consumer passes a table to a Kotlin API after one conversion call. |

## Five-target impact

The shared runtime is one Haxe source compiled by all five emitters
(`RuntimeResidents.hx:22-28`). Candidate B edits only the Kotlin
emitter: `KotlinDecl.hx`, `KotlinExpr.hx`, and
`KotlinComparisonPlan.hx`. The Haxe runtime source does not change, so
the committed Rust runtime
(`packages/registry/gen-rust/runtime/sorted_table.rs`), the TypeScript,
Dart, and Swift faces, and the stage-1 assembly keep the current shape.
The Kotlin class carries the extra interface members and the `size`
property, so the Kotlin face differs from the other four; the difference
is Kotlin-only by construction.

- **Kotlin**: the mapping in `KotlinType.hx:63-78` still names the
  table, so the generated signatures name the table; the class now also
  implements the interface. The comparison helpers
  (`KotlinComparisonPlan.hx:99-108`), the record hash
  (`KotlinDecl.hx:427`), and `Std.string` (`KotlinExpr.hx:5481-5491`)
  render `.size`.
- **TypeScript**: `TsType.hx:55-66` emits the concrete table. The Haxe
  `Map` abstract lowers to `Map<...>` at `TsType.hx:50`, so the remap
  of Candidate A would merge two Haxe types; B does not.
- **Rust**: `RustType.hx:209-220` emits the concrete table. The runtime
  struct exposes `keys`/`values` publicly and `size` returns `i32`,
  while the standard collections use `usize`; no Rust change is proposed.
- **Dart**: `DartType.hx:71-74` emits the concrete table.
  `DartDecl.hx:351-380` already special-cases `runtime.SortedTable` for
  `==` and `hashCode`, the precedent for a Kotlin-only resident
  emission.
- **Swift**: `SwiftType.hx:109-128` emits the concrete table.

## tiqian migration cost

Measured on the tree `tiqian/engine-haxe/out/kotlin-f64/gen`:

- 84 type positions written `: Sorted(Map|Set)Table<` under `org/`, 88
  with `runtime/`; 54 in `gen-tests`; 172 lines carry the token overall.
  The quoted 89 signature positions sit in this bucket; the tree is
  regenerated per pin, so the count moves by a few between revisions.
- B keeps those signatures and adds the interface as a supertype, so the
  generated call sites need no hand edit: the table members stay, and
  the emitter renders the table `size` call sites as `.size`. The
  measured generated call sites are `.has(` 111, `.size()` 108, `.at(`
  45, `.keyAt(` 19, `.valueAt(` 19. Hand-written Kotlin is not
  regenerated, so its `size()` calls stop compiling; the tiqian tree
  held two, and they are counted under the cost of the ruling.
- The consumer side gains the assignment: the platform facade can take
  `Map`/`Set` and receive a table with no conversion and no copy.
- Verification: regenerate and compile the boring reference tree, the
  tiqian Kotlin trees, and the protocol tree, then run
  `bun run test:kotlin`, `bun run test:stage1:kotlin`,
  `bun run test:driver:cross-target`, and
  `bun test tests/ts/kotlin-api-fidelity.test.ts`.

## Ruling

1. The resident Kotlin classes `SortedMapTable<K, V>` and
   `SortedSetTable<K>` implement `Map<K, V>` and `Set<K>` (Candidate
   B). The public type stays the table, which is the interface as a
   supertype, so `val m: Map<K, V> = table` needs no conversion and no
   copy.
2. The backing arrays rename to `_keys` and `_values` in the Kotlin
   emission, and `size` renders as the interface property. The ordered
   index members `has`, `keyAt`, `valueAt`, and `at` stay.
3. Candidate A is rejected. A `std.SortedMap` parameter rendered as a
   Kotlin `Map` accepts every Kotlin `Map`, and the ordered index
   members drop out of the static type.
   `docs/specs/features/14-type-system-mapping.md:174` rules that two
   distinct named Haxe types stay distinct target types, and the Haxe
   `Map` already lowers to `MutableMap` (`KotlinType.hx:43,95-96`), so
   the remap merges the two.
   `docs/specs/stdlib/07-sorted-keyed-tables.md:35-41` rules the index
   iteration that the platform interface does not carry.
4. Candidate C is recorded and not chosen: B already reaches the
   interface from the ruled type.
5. The conformance is emitted by the Kotlin backend only. The one Haxe
   runtime source and the other four targets are untouched.

### Cost of the ruling

- The generated signatures still name `SortedMapTable<K, V>` or
  `SortedSetTable<K>`; the interface is a supertype, and the spelling
  stays the table name. The tiqian tree holds 84 such positions under
  `org/` today.
- The `size` member is a property, so a hand-written Kotlin caller that
  writes `table.size()` stops compiling. The emitted class cannot keep
  `fun size(): Int`: Kotlin's `Map` is a mapped type over
  `java.util.Map`, whose `size` is the method `size()I`, and a Kotlin
  property that overrides it emits the same `size()I`. A function beside
  that property collides on the signature, which is conflict 2 above;
  removing the property to keep the function leaves the interface
  unimplemented, because a function does not satisfy an interface
  property. The emitted member is `override val size: Int`, and the
  emitter rewrites every generated call site to `.size`
  (`KotlinExpr.hx:6036-6037`). Hand-written Kotlin is outside that
  rewrite: a direct call reports that the `Int` from `size` cannot be
  invoked as a function, and a callable reference `table::size` yields a
  `KProperty0<Int>`, which a parameter of type `() -> Int` no longer
  accepts. A Java caller keeps `size()`, because the property overrides
  the Java method, and the four other targets keep the function. The
  tiqian tree held two such call sites,
  `TiqianAndroidFontBackend.kt:849` and `:852`; both read `size` after
  the repin.
- The view properties allocate one small object per table property
  (`keys`, `values`, `entries`); the set allocates its iterator per
  walk. No element array is copied.
- Iterating `entries` allocates one entry object per element.
- The Kotlin table class carries members the other four tables do not,
  so the five emitted shapes differ on Kotlin.

### Problem the ruling removes

The boundary copy of Candidate D. A consumer passes a generated table to
a Kotlin API that takes `Map<K, V>` or `Set<K>` directly; no conversion
function and no element copy stands between the two.

## Documentation

The Kotlin target ruling to add to
[07-sorted-keyed-tables.md](07-sorted-keyed-tables.md), beside the Swift
and Dart rulings at lines 154-179:

> #### Sorted tables (`stdlib/07`)
>
> The public Kotlin types are `SortedMapTable<K, V>` and
> `SortedSetTable<K>`, which implement `kotlin.collections.Map` and
> `Set`. A table is assignable to the interface at a boundary with no
> conversion and no element copy. The members `size`, `has`, `keyAt`,
> `valueAt`, and `at` remain part of the API; `size` is the interface
> property, and hand-written Kotlin reads `size` where the earlier shape
> took `size()`. The backing arrays are the ruled parallel arrays.

This specification stays as the record of the candidates, the three
`kotlinc` reproductions, the five-target impact, and the tiqian count.
