# Feature spec 38: Rust value semantics of records and array parameters

## Scope

This specification rules three Rust renderings that keep value-typed data
usable across several reads and calls: a field read of a record field
whose type is not `Copy`, an argument that passes a local of non-`Copy`
type to a function, and a re-pass of an array parameter to another
function. The four structural targets hold references at these positions
and need no rule. The registry tool under `tools/registry` is the
consumer: its generated tree today stops compilation at these positions
with E0382, E0508, and E0596. The f32 configurations inherit the rules.

## Current state

| Position | Rust today |
| --- | --- |
| whole array element read, non-`Copy` element | renders `(<expr>).clone()` (the TArray arm of `RustExpr.hx`) |
| field read of a non-`Copy` field on a local or parameter | renders the bare move `subject.field`; a later use of the subject stops with E0382 |
| argument passing a non-`Copy` local | moves the value; a second call with the same local stops with E0382 |
| re-pass of an array parameter | moves the `&mut [T]` binding; the call stops with E0596 |

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Clone at the read and at the pass | One copy per read or pass whose source is used again; the element-read rule already pays this shape | One rule for every non-`Copy` value position; the element read, the field read, and the argument pass behave alike | No runtime helper; the derive set of the record lowering supplies `Clone` | Generated sites read as ordinary value code |
| Borrow at every position | Zero copies | Records would need lifetime annotations at every signature; the emitter holds no borrow checker | One borrowing scheme per shape | Generated signatures grow lifetimes |
| Source-side rewrites in consumers | No compiler work | Every consumer re-spells copies by hand | The registry tool and the port repeat the pattern at each site | Consumer source drifts from the original shape |

## Ruling

1. A field read whose field type is not `Copy` renders as
   `(<subject>.<field>).clone()` when the subject is a local or a
   parameter. A `String`-typed field read already renders this way; the
   rule extends the same form to every non-`Copy` field type. A field
   read whose subject has no later use may render bare.
2. An argument whose expression is a bare local of non-`Copy` type
   renders as `(local).clone()`; the local stays usable after the call.
   `Copy` scalars and `String` arguments keep their current forms.
3. An array parameter passed onward as an argument renders as the
   reborrow `&mut *param`; the parameter binding stays valid.
4. Records (anonymous structures and `@:dataClass` instances) carry
   value semantics on the Rust target: every read and every pass yields
   an independent copy, and `Clone` comes from the record derive set.
   Mutation of one structure through two aliases in the same scope is
   outside the translatable subset.

## Samples and tests

- `samples/boring/ValuePassingOps.hx`: a record with a `String` field,
  an `Array<String>` field, and a nested record field; read two fields of
  one local; pass one record local to two calls; forward an array
  parameter; push through an array parameter; read `String.length` into
  `Int` arithmetic.
- `samples/tests/ValuePassingTests.hx`: the field values survive both
  reads; both calls receive equal copies; the forwarded array sees the
  push; the pushed element is readable through the caller's array; the
  length arithmetic yields the expected `Int`.
- Both modules are entered in all eight generation hxml files.
