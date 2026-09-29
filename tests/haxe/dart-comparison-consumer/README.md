# Dart comparison consumer

Run from this checkout with the pinned toolchain:

```sh
nix develop -c bash tests/haxe/dart-comparison-consumer/run.sh
```

The fixture checks source field order, nullable fields and nullable sequence
elements, lexicographic sequence order, a recursive record edge, nested
records whose declarations share the same short name in separate modules, and
a null-guarded sequence of cross-module records, so the null, sequence, and
cross-module edges are exercised in one composition. The fixture writes the
element type as the fully qualified `dartcomparison.left.Same` because an
unqualified cross-module type path does not resolve in the macro pass.
The native Dart program calls only generated comparator functions. It asserts
the sign of each result and prints the authored observations in
`expected.stdout`.

Each run creates a fresh directory under `out/dart-comparison-consumer/runs`.
It retains exact command arguments in `*.argv`, printable commands in
`*.command`, separate raw `*.stdout` and `*.stderr` streams, numeric
`*.status` files, and source input hashes before and after. The runner
analyzes the entire generated Dart tree and the native program before it runs
the program.

A comparator for a generic key declaration takes one `int Function(T, T)`
callback parameter for each demanded type parameter, named `compareArg0` and
onward. The builder call binds each demanded slot to a concrete witness: an
integer or string slot binds the native `compareTo`, a record slot binds the
generated comparator of that record with its own callbacks, and null and
sequence wrappers compose the element witness. A declaration whose plan demands
no parameter callback, such as an unused parameter, emits a comparator without
callback parameters.

The retained negative runs in this directory show the failure sides the
procedure discriminates. `attempt-eYyKflHQ` skips the emission of a comparator
that demands a parameter callback while the builder keeps the reference; the
Dart analyzer rejects the generated tree with `undefined_function` on each
generic comparator name and exits 3 before the program stage. The source
comparison result still owns the admissibility and ordering decisions for
concrete record fields.

## Payload enum representation regression

The original PrintedCollection, PrintedEnumOps and PrintedSortedFields modules
are generated and analyzed unchanged. Native enums retain index reads; payload
enums use exhaustive constructor switches. Record field ordering follows
stdlib/16 kind 3. The same-constructor observation checks ordinal equality only;
the equality conflict documented in a-enum-comparison-review remains unresolved.

Runtime controls cover direct and cross-module payload fields, both constructor
orders, different payloads of one constructor, nullable absence and presence,
sequence elements and prefixes, native enum fields, and generic record callbacks
bound to payload and native enums. The previous thirteen output lines remain.

Retained attempts: y4zwTxBV reproduces the original six index errors; 41Qs53BC
restores the invalid index operation and fails analysis; CopiLbWD omits the first
constructor arm and fails sealed exhaustiveness. wxcGI4U4 observes an independent
typedef field emission failure (undefined MarkAlias); typedef-field support is
not established by this repair. Direct payload enum keys remain out of scope.

