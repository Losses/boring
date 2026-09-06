# Standard library spec 18: narrowed Std.string operands

Status: Implemented. This specification rules the synthesized narrowing
exception of the `Std.string` rejection and amends ruling 4 of
[33-record-collection-fields.md](../features/33-record-collection-fields.md)
and the rejection paragraph of
[12-std-string.md](12-std-string.md).

## Scope

This specification rules how a nullable collection or enum record field
renders without lifting the `Null<T>` operand rejection of stdlib spec
12, on all five source targets (ts, kotlin, swift, dart, rust) and the
stage 1 Haxe reference build. The only consumer is the record member
synthesis of feature spec 31 (`samples/std/RecordShape.hx`,
`nullableStdStringValue`).

## Contract

`Std.string` rejects an operand typed `Null<T>` on every target
(stdlib spec 12; the owner's terminal ruling). The rejection applies to
an operand whose source position lies inside the source roots
(`Intercept.sourceRoots()`, `samples` and `packages/registry/src`;
`PolicyQueries.inSourceScope`). The record member synthesis builds its
members with unknown positions, so its operands are outside the source
scope: a nullable collection or enum record field renders through the
null comparison ternary of the member synthesis (a null field prints
`null`, a present field prints the `Std.string` form of the field
read), and each target compiler narrows the synthesized nullable
operand in the present branch by its own mechanism:

| Target | Narrowing of the synthesized nullable operand |
| --- | --- |
| TypeScript | the operand expression unchanged; the target's control-flow narrowing after the null comparison types the present branch |
| Kotlin | `(operand)!!` at the bare uses (no synthesized member is emitted today, spec 31 ruling 1) |
| Swift | `(operand)!` at the bare uses; a payload enum operand renders through its constructor switch, whose `case .none` arm performs the narrowing |
| Dart | `(operand)!` at the bare uses |
| Rust | no assertion; the operand's rendering is `match operand { Some(ref v) => <content>, None => "null".to_string() }` |

A hand-written source narrows a nullable operand only through the
explicit null comparison path of stdlib spec 12; there is no callable
narrowing helper. Two earlier drafts of this specification were
replaced for verified reasons. The first draft used a
`std.NonNull.require` call as the narrowing marker: the call typed a helper module
into every target tree whose dead body could not satisfy all five
target compilers (a `Null<T>` to `T` return is a compile error on
Kotlin, Rust, Swift, and Dart and a strict-mode TypeScript error); the
enum-carrying exception required by V04 for its stage 1 body entered
the target module graph and turned record `toString` functions into
throwing functions through the backends' exception propagation; and
expression metadata as a replacement marker is stripped before the
generators run, which a probe of the typed output confirmed. The second
draft lowered the synthesized operand to the target's non-null
assertion on every target uniformly; the assertion was removed from
Rust (whose operand rendering already narrows through its `Null` match
form, so the assertion stripped the `Option` before the match and broke
its typing) and made conditional on Swift (where a payload enum operand
renders through its constructor switch, whose `case .none` arm performs
the narrowing, so asserting such an operand removed the case the switch
needs).

## Ruling

1. A nullable collection or enum record field renders through the null
   comparison ternary of the member synthesis: a null field prints
   `null`, a present field prints the `Std.string` form of the field
   read narrowed per the Contract table. This replaces the
   sentence of feature spec 33 ruling 4 that stopped the compilation
   for a nullable collection field.
2. stdlib spec 12 gains: the `Null<T>` operand rejection applies to
   operands whose position lies in the source roots; operands of the
   member synthesis carry unknown positions and render through the
   null comparison ternary narrowed per the Contract table.

## Samples and tests

- `samples/std/RecordShape.hx` `nullableStdStringValue`: the synthesis
  of the guarded present branch.
- `samples/tests/StdNullStringProbes.hx`: the `nullScalar` and
  `nullCollection` probes, stopped by the rejection.
- `tests/ts/std-string.test.ts`: the rejection message asserted for all
  five target compilations.
- `samples/boring/PrintedCollection.hx`
  `PrintedNullableCollection`: the printed form stays
  `PrintedNullableCollection(words=[a, b])` and
  `PrintedNullableCollection(words=null)` on every target; the Rust
  tree narrows the operand through its `Null` match form, and the Swift
  tree narrows a payload enum operand through the constructor switch
  and asserts every other operand shape.
