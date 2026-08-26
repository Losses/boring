# Feature spec 10: Static extension

## Scope

This specification rules the translation of Haxe static extensions (`using Module;`) into Rust and TypeScript. In the current codebase, static extensions do not appear in `haxe/src/boring/`, which uses direct static method calls such as `haxe.io.FPHelper.doubleToI64(value)` in `haxe/src/boring/BinaryWriter.hx` (line 31) and `Bytes.ofHex` in `tests/haxe/Main.hx` (line 83). In Rust, methods appear as struct `impl` blocks in `rust/src/lib.rs` (lines 56-82), and in TypeScript, methods appear as class member functions in `ts/src/codec.ts` (lines 21-70) or free module functions in `ts/src/vector-format.ts` (lines 15, 30).

## Haxe construct

Haxe static extensions allow static methods to be invoked with member-call dot syntax on the first argument type. The directive `using Module;` brings the module's static functions into scope as extension methods:

```haxe
class StringExt {
	public static function parseHex(value:String):Bytes {
		return Bytes.ofHex(value);
	}
}

using StringExt;

class Example {
	public static function run():Bytes {
		return "42524731".parseHex();
	}
}
```

The Haxe compiler transforms the member call expression `e.method(a, b)` into the static invocation `Module.method(e, a, b)`.

In the Haxe typed AST, static extensions resolve during typing into `haxe.macro.TypedExprDef.TCall(e:TypedExpr, el:Array<TypedExpr>)`, where `e` is a `haxe.macro.TypedExprDef.TField(e_static, FStatic(c, cf))` targeting the static class field and `el` contains the receiver expression as the first element.

## Current translations

### Haxe (`haxe/src/boring/BinaryWriter.hx`, `tests/haxe/Main.hx`)

Absent in `haxe/src/boring/`. Haxe uses direct static method calls:

```haxe
final bits = haxe.io.FPHelper.doubleToI64(value);
```

In `tests/haxe/Main.hx` (line 83):

```haxe
final decoded = VectorCodec.decode(Bytes.ofHex(EXPECTED_HEX));
```

### Rust (`rust/src/lib.rs`)

Absent as extension traits. Rust uses inherent `impl` blocks on structs and free functions for module-level operations:

```rust
impl<'a> VectorReader<'a> {
    pub fn new(bytes: &'a [u8]) -> Self {
        VectorReader { bytes, offset: 0 }
    }

    pub fn read_u32(&mut self) -> Result<u32, VectorError> {
        Ok(u32::from_be_bytes(self.take_n::<4>()?))
    }
}

pub fn encode_vector(records: &[GlyphMetrics]) -> Result<Vec<u8>, VectorError> {
    // ...
}
```

### TypeScript (`ts/src/codec.ts`, `ts/src/vector-format.ts`)

Absent as declaration merging. TypeScript uses class member methods and free module functions:

```ts
export class BinaryReader {
  readU32(): number {
    const value = this.view.getUint32(this.offset, false);
    this.offset += 4;
    return value;
  }
}

export function encodeVector(records: readonly GlyphMetricsRecord[]): Uint8Array {
  // ...
}
```

## Candidate translations

### Rust Candidate 1: Free functions taking receiver as first parameter

```rust
pub fn vector_byte_length(record_count: usize) -> usize {
    8 + record_count * 44
}
```

### Rust Candidate 2: Inherent impl methods for crate-owned types

```rust
impl GlyphMetrics {
    pub fn byte_length(&self) -> usize {
        44
    }
}
```

### Rust Candidate 3: Extension trait with blanket implementation for foreign types

```rust
pub trait SliceExt {
    fn remaining_bytes(&self, offset: usize) -> usize;
}

impl<T> SliceExt for [T] {
    fn remaining_bytes(&self, offset: usize) -> usize {
        self.len().saturating_sub(offset)
    }
}
```

### TypeScript Candidate 1: Standalone exported module functions

```ts
export function vectorByteLength(recordCount: number): number {
  return 8 + recordCount * 44;
}
```

### TypeScript Candidate 2: Prototype augmentation via declaration merging

```ts
declare global {
  interface Uint8Array {
    readU32Be(offset: number): number;
  }
}

Uint8Array.prototype.readU32Be = function (offset: number): number {
  return new DataView(this.buffer, this.byteOffset, this.byteLength).getUint32(offset, false);
};
```

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Rust Candidate 1 (Free functions) | Free functions compile to direct static calls that optimize through inline passes. | Function calls name the defining module and avoid trait scope pollution. | Functions require zero trait declarations or companion wrapper types. | Standalone functions state transformations directly to Rust engineers. |
| Rust Candidate 2 (Inherent impl methods) | Inherent methods dispatch with zero indirection and inline directly. | Method resolution associates behavior directly with the struct type. | Methods live inside the single canonical struct module. | Method syntax provides direct object-oriented ergonomics for crate types. |
| Rust Candidate 3 (Extension trait) | Monomorphized trait dispatch incurs zero runtime overhead. | Traits must be brought into lexical scope across caller modules. | Trait definitions duplicate signatures between trait blocks and impl blocks. | Foreign trait implementations add boilerplate around simple operations. |
| TS Candidate 1 (Exported module functions) | Standalone functions call directly with zero prototype chain traversal. | Module imports determine exact function origin without global namespace pollution. | Functions declare their implementation once in their host module. | Explicit function calls present standard idiomatic TypeScript architecture. |
| TS Candidate 2 (Prototype augmentation) | Prototype property lookups introduce runtime dispatch penalties on every invocation. | Global interface merging creates collision risks across independent libraries. | Augmentation requires matching ambient declarations and runtime prototype mutations. | Monkey-patching prototypes obscures method definitions from readers and linters. |

## Ruling

Haxe `using` static extensions translate to inherent `impl` methods for crate-owned types in Rust, free functions in Rust for foreign types or multi-argument operations, and standalone exported functions in TypeScript modules taking the receiver as the first parameter.

Global prototype augmentation and declaration merging are banned in TypeScript. All extension functionality lives in explicit module namespaces.

## Test hooks

Module function calls and method invocations are verified in:
- `tests/rust/vector.rs` (lines 54-70)
- `tests/ts/codec.test.ts` (lines 9, 62)
- `tests/haxe/Main.hx` (lines 79-88)
