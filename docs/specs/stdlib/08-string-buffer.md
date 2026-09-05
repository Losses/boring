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
- `add(part:String):Void` appends a string. When the current content
  ends with an unpaired lead surrogate and the argument is nonempty and
  does not start with the matching trail surrogate, the call throws
  `std.UStringException` carrying `UnpairedSurrogate(unit)`.
- `addChar(codeUnit:Int):Void` appends one UTF-16 code unit. A trail
  surrogate is accepted only when the current content ends with an
  unpaired lead; a lead surrogate or a non-surrogate unit is accepted
  only when the content does not end with an unpaired lead. A rejected
  call throws `std.UStringException` carrying `UnpairedSurrogate(unit)`.
- `get length():Int` returns the UTF-16 code-unit count of the current
  content, including a lead surrogate whose trail has not arrived yet.
- `toString():String` returns the current content as a well-formed
  string; when the content ends with an unpaired lead surrogate, the
  call throws the same fault. Later `add` calls extend the buffer and a
  later `toString` returns the extended content.

The fault payload names the unpaired unit: the argument when it is a
trail surrogate with no preceding lead, and the trailing lead already
held in every other case. The variant lives in `std.UStringFault`
alongside `InvalidCodePoint`, because both name an ill-formed Unicode
value crossing the string subsystem.

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

- Rust: the buffer renders as `Vec<u16>` holding UTF-16 code units.
  `new` emits `Vec::<u16>::new()`. `add` emits the boundary check and
  `extend(part.encode_utf16())`. `addChar` emits the pairing check and
  `push(unit as u16)`. `length` emits `len() as u32`, a constant-time
  read of the unit vector. `toString` emits the dangling-lead check and
  `String::from_utf16(&buf).map_err(...)` returning through the
  enclosing function's `Result`, so a buffer operation sites its
  fallibility in `std.UStringFault` like a `std.UString` construction
  check. The checks read the trailing unit with `buf.last()`, so the
  buffer content itself carries the pairing state.
- TypeScript: the buffer renders as a `string` variable accumulated with
  `+=`. `addChar` emits the pairing check reading
  `buf.charCodeAt(buf.length - 1)` and `String.fromCharCode(codeUnit)`.
  `add` and `toString` emit the matching checks. The fault constructs
  the compiled `std.UStringException`, imported like any compiled std
  module. `length` emits the `.length` property. JavaScript engines
  amortize string append through rope chains, and the haxe JavaScript target
  lowers its own `StringBuf` to the same `+=` form, so the oracle and the
  generated code share the mechanism.
- Kotlin: the buffer renders as `StringBuilder`. `add` emits the
  boundary check and `append`. `addChar` emits the pairing check reading
  the trailing unit and `append(codeUnit.toChar())`. The fault
  constructs the compiled `std.UStringException`, which consumer builds
  write through stdlib/06's guaranteed-module list. `length` emits the
  `.length` property. `toString` emits the dangling-lead check and
  `toString()`.
- Haxe stage 1: the wrapper that binds the standard `StringBuf` applies
  the same three checks against the wrapped buffer's content before
  delegating. Reading the trailing unit costs one `toString()` snapshot
  per checked call, which is quadratic in the buffer length; the
  stage-1 Haxe run is the test oracle, so this cost is accepted there and
  rules nothing about the generated targets.

## Samples and tests

A sample module builds strings by parts, appends supplementary characters
through `add` as whole string parts, exercises `addChar` on
basic-multilingual-plane code units, asserts the content and the
code-unit length, and exercises the unpaired-surrogate fault paths: a
trail without a preceding lead, a lead completed by the immediately
following `addChar`, and a dangling lead observed by `toString`. The
four-side consistency run of
`docs/specs/features/19-testing.md` compares the jsonl output. `tests/ts/`
tree assertions pin the native forms: `extend` over `encode_utf16` on
Rust, `+=` accumulation on
TypeScript, `append` on Kotlin, with no builder call sites beyond the routed
module.

An unpaired surrogate half pair has one behavior on every target: the
call that would create or observe it throws `std.UStringException`
carrying `UnpairedSurrogate(unit)`. Samples feed half of a
surrogate pair and assert the fault identity, never a message.

### Swift target rulings

#### String buffer (`stdlib/08`)

The buffer is `Array<UInt16>`, the same ruling as the Rust `Vec<u16>`:
a native `String` cannot store the unpaired lead the fault paths must
observe. `add` and `addChar` emit the boundary and pairing checks
reading the last unit by integer subscript; `toString` emits the
dangling-lead check and `String(decoding: buf, as: UTF16.self)`.

### Dart target rulings

#### String buffer (`stdlib/08`)

The buffer is `List<int>` over the UTF-16 units: the dangling unit is
`buf[buf.length - 1]`, `add` emits the pairing check of `stdlib/08` and
appends through `addAll(part.codeUnits)`, `addChar` emits the trail
check and appends one unit, and `toString` emits the dangling-lead
check and builds through `String.fromCharCodes(buf)`. The fault is the
sealed `UStringFault` hierarchy above.
