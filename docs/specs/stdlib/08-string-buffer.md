# Standard library spec 08: std.StringBuf

## Scope

This specification rules buffered string construction. The engine port audit
carries eight string-building sites (diagnostic messages and joined labels)
written against a mutable builder. The buffer holds mutable state, so each
platform renders its native mutable string accumulator; the mechanism is the
per-platform routing of `docs/specs/stdlib/06-std-modules.md`, the same
pattern as `std.SortedMap` in `docs/specs/stdlib/07-sorted-keyed-tables.md`.

## Contract

- `new StringBuf()` creates an empty buffer.
- `add(part:String):Void` appends a string.
- `addChar(codeUnit:Int):Void` appends one UTF-16 code unit.
- `get length():Int` returns the UTF-16 code-unit count of the current
  content.
- `toString():String` returns the current content; later `add` calls extend
  the buffer and a later `toString` returns the extended content.

## Haxe declarations and routing

`samples/std/StringBuf.hx` declares the extern following the `SortedMap`
pattern. The pipeline maps the module to the per-platform type below. On the
haxe stage-1 side the extern resolves to the haxe standard library `StringBuf`,
so the oracle is the haxe standard implementation.

The haxe JavaScript `StringBuf` declares every member `inline`, so the
compiled class carries a constructor but no prototype methods, and a
direct class binding cannot serve dynamic extern calls. The stage-1
runner therefore compiles a haxe wrapper class whose methods call the
standard `StringBuf` operations; the haxe compiler inlines those
operations into the wrapper bodies, and the bootstrap binds the wrapper
constructor to `globalThis.std.StringBuf`. This follows the
`FunctionalOracle` binding pattern, and no handwritten JavaScript
implementation stands in for the standard library.

## Per-platform shapes

- Rust: the buffer renders as `String`. `add` emits `push_str`. `addChar`
  maps the code unit through `char::from_u32` with
  `char::REPLACEMENT_CHARACTER` for an unpaired surrogate. `length` emits
  `encode_utf16().count()` cast to the `Int` domain, which renders as
  `as u32`. `toString` emits `clone()`.
- TypeScript: the buffer renders as a `string` variable accumulated with
  `+=`. `addChar` emits `String.fromCharCode(codeUnit)`. `length` emits the
  `.length` property. `toString` reads the variable. JavaScript engines
  amortize string append through rope chains, and the haxe JavaScript target
  lowers its own `StringBuf` to the same `+=` form, so the oracle and the
  generated code share the mechanism.
- Kotlin: the buffer renders as `StringBuilder`. `add` emits `append`.
  `addChar` emits `append(codeUnit.toChar())`. `length` emits the `.length`
  property. `toString` emits `toString()`.

## Samples and tests

A sample module builds strings by parts, appends supplementary characters
through `add` as whole string parts, exercises `addChar` on
basic-multilingual-plane code units, and asserts the content and the
code-unit length. The four-side consistency run of
`docs/specs/features/19-testing.md` compares the jsonl output. `tests/ts/`
tree assertions pin the native forms: `push_str` on Rust, `+=` accumulation on
TypeScript, `append` on Kotlin, with no builder call sites beyond the routed
module.

An unpaired surrogate code unit has no representation in the Rust `String`
buffer: `addChar` lowers it to `char::REPLACEMENT_CHARACTER` on Rust only,
while the other three targets keep the code unit. This divergence is
representational, so the consistency contract covers the inputs the engine
port builds and no sample feeds half of a surrogate pair.
