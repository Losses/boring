# Macro spec 03: Group by idiom

## Scope

This specification adds `groupBy` to the closed list of
`docs/specs/macros/01-functional-idiom-expansion.md`, with one ruling that
differs from the source semantics of the engine port: the product iterates
in boring's key-ascending order. The engine port audit carries 7 uses.
The mechanism is the typed common-layer expansion pass of `macros/01`,
with the recognition rules, position rule, and mint naming unchanged.

## Ruling: product and order

`arr.groupBy(entry -> { key: k, value: v })` produces
`std.SortedMap<K, Array<V>>`. The lambda body is a structure literal with
exactly the fields `key` and `value`, declared through a named typedef,
the same shape `associate` requires. Keys ascend by the `stdlib/07` key
domain of `K`, and each bucket keeps receiver order.

The Kotlin source construct returns an insertion-ordered map. The port
accepts key order in its place: every site that iterates the product
reads groups in ascending key order, and a site that depends on
first-seen order rewrites its source during the port. This ruling was chosen over an insertion-ordered product because
`std.SortedMap` is the only keyed collection with a ruled contract, and
building a second map semantics for 7 sites adds a runtime module without
verification value.

## Expansion

The product is a loop over the receiver that reads or creates the bucket
for the entry key and pushes the entry value:

```haxe
var pipeline_builder = new SortedMapBuilder<K, Array<V>>();
for (item in arr) {
    var pipeline_entry = /* the lambda structure literal */;
    var pipeline_bucket = pipeline_builder.get(pipeline_entry.key);
    if (pipeline_bucket == null) {
        pipeline_bucket = new Array<V>();
        pipeline_builder.put(pipeline_entry.key, pipeline_bucket);
    }
    pipeline_bucket.push(pipeline_entry.value);
}
return pipeline_builder.build();
```

The builder exposes `get(key):Null<V>` over its pending state;
`docs/specs/stdlib/07-sorted-keyed-tables.md` records the member in the
builder declaration. The key obeys the `stdlib/07` key domain gate: a key
domain without a ruled comparison is rejected exactly as a direct builder
use is. Receiver items with equal keys share one bucket, and the bucket
keeps receiver order; no entry is dropped.

## Stage-one oracle

The Haxe standard library holds no ordered multimap, so the stage-one side
runs a handwritten implementation injected in the `TestCollector`
bootstrap, the same tier as `associate` and `mapNotNull`; this
specification records that tier honestly. The handwritten body stores
buckets in a plain array and sorts the keys once at read time, so the
stage-one reads observe the same ascending order as the built tables.

## Test hooks

- A sample module groups items whose keys arrive in non-ascending order,
  includes duplicate keys, and asserts the ascending key order through the
  index-range iteration of `stdlib/07` plus each bucket's contents in
  receiver order.
- The four-side consistency run of `docs/specs/features/19-testing.md`
  compares the jsonl output.
- `tests/ts/` tree assertions pin the products: generated trees contain
  no `groupBy` call sites, and each product appears as the builder loop
  above.
- The mutation checks for this module live in the dispatch task file.
