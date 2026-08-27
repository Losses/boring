# Feature spec 12: Classes, interfaces, and access

## Scope

This specification rules the translation of Haxe classes, member variables, properties, interfaces, and access modifiers (`public`, `private`, `static`, `inline`) into Rust, TypeScript, and Kotlin. In the current codebase, classes appear in Haxe in `samples/boring/BinaryReader.hx` (lines 11-57), `samples/boring/BinaryWriter.hx` (lines 11-47), and `samples/boring/VectorCodec.hx` (lines 10-54), extern classes appear in `samples/std/Process.hx` (lines 8-10) and `samples/std/Console.hx` (lines 8-10), structs and `impl` blocks appear in Rust in `reference/rust/src/lib.rs` (lines 9-22, 51-82), and classes and interfaces appear in TypeScript in `reference/ts/src/codec.ts` (lines 10-117) and `reference/ts/src/records.ts` (lines 7-18). In Kotlin, classes appear in `reference/kotlin/src/boring/BinaryReader.kt`, `reference/kotlin/src/boring/BinaryWriter.kt`, and `reference/kotlin/src/boring/VectorException.kt`; the codec API is the `VectorCodec` object in `reference/kotlin/src/boring/VectorCodec.kt`.

## Haxe construct

Haxe defines object-oriented classes with fields, methods, properties, and interfaces:

```haxe
interface IReader {
	function readU32():Int;
	function remaining():Int;
}

class BinaryReader implements IReader {
	final bytes:Bytes;
	var offset:Int;

	public function new(bytes:Bytes) {
		this.bytes = bytes;
		this.offset = 0;
	}

	public function readU32():Int {
		final value = (bytes.get(offset) << 24)
			| (bytes.get(offset + 1) << 16)
			| (bytes.get(offset + 2) << 8)
			| bytes.get(offset + 3);
		offset += 4;
		return value;
	}

	public function remaining():Int {
		return bytes.length - offset;
	}
}
```

Haxe supports property accessors `(get, set)`, visibility modifiers (`public`, `private`), and static modifiers.

In the Haxe typed AST, class declarations are represented by `haxe.macro.Type.TClassDecl(c:Ref<ClassType>)`, where `ClassType` contains `fields:Ref<Array<ClassField>>`, `statics:Ref<Array<ClassField>>`, `constructor:Null<Ref<ClassField>>`, and `interfaces:Array<{t:Ref<ClassType>, params:Array<Type>}>`. Member access maps to `haxe.macro.TypedExprDef.TField(e:TypedExpr, fa:FieldAccess)`.

## Current translations

### Haxe (`samples/boring/BinaryReader.hx`, `samples/boring/BinaryWriter.hx`)

```haxe
class BinaryReader {
	final bytes:Bytes;
	var offset:Int;

	public function new(bytes:Bytes) {
		this.bytes = bytes;
		offset = 0;
	}

	public function readU32():Int {
		// ...
		offset += 4;
		return value;
	}

	public function remaining():Int {
		return bytes.length - offset;
	}
}
```

### Rust (`reference/rust/src/lib.rs`)

```rust
pub struct VectorReader<'a> {
    bytes: &'a [u8],
    offset: usize,
}

impl<'a> VectorReader<'a> {
    pub fn new(bytes: &'a [u8]) -> Self {
        VectorReader { bytes, offset: 0 }
    }

    pub fn read_u32(&mut self) -> Result<u32, VectorError> {
        Ok(u32::from_be_bytes(self.take_n::<4>()?))
    }

    pub fn remaining(&self) -> usize {
        self.bytes.len() - self.offset
    }
}
```

### TypeScript (`reference/ts/src/codec.ts`, `reference/ts/src/records.ts`)

```ts
export class BinaryReader {
  private readonly view: DataView;
  private offset: number;

  constructor(bytes: Uint8Array) {
    this.view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    this.offset = 0;
  }

  readU32(): number {
    const value = this.view.getUint32(this.offset, false);
    this.offset += 4;
    return value;
  }

  remaining(): number {
    return this.view.byteLength - this.offset;
  }
}

export interface GlyphMetricsRecord {
  readonly codePoint: number;
  readonly advanceEm: number;
  readonly bounds: BoundsEmRecord;
}
```

## Candidate translations

### Rust Candidate 1: Structs with private fields, pub constructors, and methods in impl blocks

```rust
pub struct VectorReader<'a> {
    bytes: &'a [u8],
    offset: usize,
}

impl<'a> VectorReader<'a> {
    pub fn new(bytes: &'a [u8]) -> Self {
        VectorReader { bytes, offset: 0 }
    }

    pub fn read_u32(&mut self) -> Result<u32, VectorError> {
        Ok(u32::from_be_bytes(self.take_n::<4>()?))
    }
}
```

### Rust Candidate 2: Trait objects with Box dynamic dispatch

```rust
pub trait ReaderTrait {
    fn read_u32(&mut self) -> Result<u32, VectorError>;
}

pub struct VectorReader<'a> {
    reader: Box<dyn ReaderTrait + 'a>,
}
```

### TypeScript Candidate 1: Stateful classes with access modifiers, data interfaces, and function type aliases for interface methods

```ts
export type ReadU32Fn = () => number;
export type RemainingFn = () => number;

export interface ReaderShape {
  readonly readU32: ReadU32Fn;
  readonly remaining: RemainingFn;
}

export class BinaryReader {
  private readonly view: DataView;
  private offset: number;

  constructor(bytes: Uint8Array) {
    this.view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    this.offset = 0;
  }

  public readU32(): number {
    const value = this.view.getUint32(this.offset, false);
    this.offset += 4;
    return value;
  }
}
```

### TypeScript Candidate 2: Interfaces with direct method signatures

```ts
export interface BinaryReaderInterface {
  readU32(): number;
  remaining(): number;
}
```

### Kotlin Candidate 1: Class with private val state and an interface with methods

```kotlin
interface Reader {
    fun readU32(): Int
    fun remaining(): Int
}

class BinaryReader(bytes: ByteArray) : Reader {
    private val buffer: ByteArray = bytes
    private var offset: Int = 0

    override fun readU32(): Int {
        val value = (buffer[offset].toInt() and 0xFF shl 24) or
            (buffer[offset + 1].toInt() and 0xFF shl 16) or
            (buffer[offset + 2].toInt() and 0xFF shl 8) or
            (buffer[offset + 3].toInt() and 0xFF)
        offset += 4
        return value
    }

    override fun remaining(): Int = buffer.size - offset
}
```

### Kotlin Candidate 2: Public mutable state fields

```kotlin
class BinaryReader(var bytes: ByteArray, var offset: Int)
```

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Rust Candidate 1 (Struct with impl) | Inherent method calls inline directly and avoid virtual table indirection. | Struct field visibility rules enforce state encapsulation within the crate module. | Method signatures exist once in the canonical struct impl block. | Standard struct and impl declarations express object behavior directly to Rust engineers. |
| Rust Candidate 2 (Trait object Box) | Dynamic virtual table dispatch and heap allocations reduce throughput on hot paths. | Dynamic trait objects obscure concrete storage layout behind pointer wrappers. | Boilerplate trait definitions duplicate signatures across trait and impl blocks. | Dynamic boxing adds indirection to simple cursor structures. |
| TS Candidate 1 (Class and data interface) | Direct prototype method calls execute with optimized V8 inline caches. | Explicit public and private member modifiers guard internal buffer state. | Data shapes and classes separate structural typing from stateful mechanics cleanly. | Standard TypeScript classes and data interfaces state intent directly. |
| TS Candidate 2 (Interface with methods) | Interface methods compile away at runtime with zero direct performance impact. | Direct method declarations in interfaces violate repository rules in AGENT.md. | Method declarations must be rewritten to conform to repository lint constraints. | Banned syntax fails repository lint checks in tools/eslint. |
| Kotlin Candidate 1 (Class with interface) | Direct class method calls dispatch through monomorphic inline caches with zero boxing. | `private val` and `private var` guard the cursor state, and the interface names the contract. | One class declaration carries state and methods together. | Standard Kotlin class and interface syntax states the boundary directly. |
| Kotlin Candidate 2 (Public mutable fields) | Field access itself is fast, with the cursor invariant left unguarded. | Any caller can mutate `offset` and break the reader invariant. | Every consumer must revalidate cursor bounds defensively. | Public mutable state conceals which operations maintain the invariant. |

## Ruling

Stateful Haxe classes translate to Rust `struct` declarations with private fields and `impl` blocks, to TypeScript `class` declarations with explicit `private`, `public`, and `readonly` field modifiers, and to Kotlin `class` declarations with `private val` and `private var` state. Pure data classes and typedefs translate to Rust public structs with derived traits, TypeScript `interface` declarations declaring data shapes only, and Kotlin `data class` declarations per `docs/specs/features/03-structures-and-typedefs.md`.

When an interface specifies callable properties in TypeScript, method signatures are banned under the `boring/no-interface-methods` rule in `AGENT.md`; such properties must be declared as properties whose types are named function type aliases. The `boring/no-interface-methods` rule is TypeScript-specific: Kotlin interfaces declare methods directly, and generated Kotlin code uses interface methods where the Haxe source declares an interface. Pure static utility classes translate to free functions within target modules.

## Test hooks

Stateful reader and writer classes, struct methods, and interface shapes are verified in:
- `tests/rust/vector.rs` (lines 54-70)
- `tests/ts/codec.test.ts` (lines 12-54)
- `tests/haxe/Main.hx` (lines 89-96)
- `tools/eslint/` rules enforcing interface shape constraints
