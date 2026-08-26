# Feature spec 05: Generics

## Scope

This specification rules the translation of Haxe parameterized types, generic functions, and type parameter constraints into Rust and TypeScript. In the current codebase, generic collections appear as `Array<GlyphMetrics>` in `haxe/src/boring/VectorCodec.hx`, as `Vec<GlyphMetrics>`, `&[GlyphMetrics]`, and `take_n<const N: usize>` in `rust/src/lib.rs`, and as `readonly GlyphMetricsRecord[]` in `ts/src/vector-format.ts`.

## Haxe construct

Haxe supports parameterized classes and functions with optional type constraints:

```haxe
interface Serializable {
	function byteLength():Int;
}

class RecordContainer<T:Serializable> {
	final items:Array<T>;

	public function new(items:Array<T>) {
		this.items = items;
	}

	public function totalBytes():Int {
		var sum = 0;
		for (item in items) {
			sum += item.byteLength();
		}
		return sum;
	}
}
```

By default on JavaScript targets, Haxe erases type parameters at runtime. When decorated with `@:generic`, the Haxe compiler monomorphizes the class or method, generating specialized implementations for each concrete type argument.

In the Haxe typed AST, generic types are represented by `haxe.macro.Type.TInst(t:Ref<ClassType>, params:Array<Type>)` where the class defines `params:Array<TypeParameter>`. Constraints are stored in `TypeParameter.t` bounds. Function-level generics are represented in `haxe.macro.Type.TFun` with corresponding `TypeParameter` lists.

## Current translations

### Haxe (`haxe/src/boring/VectorCodec.hx`)

```haxe
public static function encode(records:Array<GlyphMetrics>):Bytes {
	final writer = new BinaryWriter();
	writer.writeAscii(MAGIC);
	writer.writeU32(records.length);
	for (record in records) {
		writer.writeU32(record.codePoint);
		writer.writeF64(record.advanceEm);
		writer.writeF64(record.bounds.xMin);
		writer.writeF64(record.bounds.yMin);
		writer.writeF64(record.bounds.xMax);
		writer.writeF64(record.bounds.yMax);
	}
	return writer.finish();
}
```

### Rust (`rust/src/lib.rs`)

```rust
fn take_n<const N: usize>(&mut self) -> Result<[u8; N], VectorError> {
    match self.bytes[self.offset..].split_first_chunk::<N>() {
        Some((head, _)) => {
            self.offset += N;
            Ok(*head)
        }
        None => Err(VectorError::UnexpectedEof),
    }
}

pub fn encode_vector(records: &[GlyphMetrics]) -> Result<Vec<u8>, VectorError> {
    let count = u32::try_from(records.len()).map_err(|_| VectorError::CountOverflow)?;
    let mut bytes = Vec::with_capacity(8 + records.len() * RECORD_BYTE_LENGTH);
    // ...
    Ok(bytes)
}
```

### TypeScript (`ts/src/vector-format.ts`)

```ts
export function encodeVector(records: readonly GlyphMetricsRecord[]): Uint8Array {
  const writer = new BinaryWriter();
  writer.writeAscii(VECTOR_MAGIC);
  writer.writeU32(records.length);
  for (const record of records) {
    writer.writeU32(record.codePoint);
    writer.writeF64(record.advanceEm);
    writer.writeF64(record.bounds.xMin);
    writer.writeF64(record.bounds.yMin);
    writer.writeF64(record.bounds.xMax);
    writer.writeF64(record.bounds.yMax);
  }
  return writer.finish();
}
```

## Candidate translations

### Rust Candidate 1: Monomorphized static generics with trait bounds

```rust
pub trait WireRecord {
    fn write_to(&self, writer: &mut Vec<u8>);
}

pub fn encode_records<T: WireRecord>(records: &[T]) -> Vec<u8> {
    let mut buffer = Vec::new();
    for record in records {
        record.write_to(&mut buffer);
    }
    buffer
}
```

### Rust Candidate 2: Dynamic trait objects

```rust
pub trait WireRecord {
    fn write_to(&self, writer: &mut Vec<u8>);
}

pub fn encode_records(records: &[Box<dyn WireRecord>]) -> Vec<u8> {
    let mut buffer = Vec::new();
    for record in records {
        record.write_to(&mut buffer);
    }
    buffer
}
```

### TypeScript Candidate 1: Erased generic functions with interface constraints

```ts
export interface WireRecord {
  readonly byteLength: number;
}

export function totalRecordBytes<T extends WireRecord>(records: readonly T[]): number {
  let sum = 0;
  for (const record of records) {
    sum += record.byteLength;
  }
  return sum;
}
```

### TypeScript Candidate 2: Untyped unknown arrays with type assertions

```ts
export function totalRecordBytes(records: readonly unknown[]): number {
  let sum = 0;
  for (const record of records) {
    const item = record as { readonly byteLength: number };
    sum += item.byteLength;
  }
  return sum;
}
```

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Rust Candidate 1 (Static generics) | Monomorphized functions inline specialized instructions with zero virtual dispatch overhead. | Trait bounds declare expected interface capabilities explicitly at compile time. | Trait declarations are defined once and reused across record structures. | Standard generic syntax communicates specialized type handling directly to Rust engineers. |
| Rust Candidate 2 (Trait objects) | Dynamic trait dispatch incurs virtual table lookups and heap pointer indirection. | Trait objects conceal underlying concrete memory layouts from compiler optimizations. | Boxing requires auxiliary heap allocation code for every item in a sequence. | Trait object syntax introduces unnecessary dynamic polymorphism into static record processing. |
| TS Candidate 1 (Erased generics) | Generics are completely erased by the TypeScript compiler and run at native JavaScript speed. | Type constraints provide static type validation without runtime type inspection overhead. | Shared generic algorithms prevent duplicating container logic across record variants. | Generic parameter constraints document type requirements directly in function signatures. |
| TS Candidate 2 (Unknown arrays) | Type assertions incur zero runtime cost in compiled JavaScript output. | Unchecked assertions bypass compiler validation and invite runtime type mismatches. | Every call site requires manual type narrowing and validation logic. | Untyped signatures hide parameter requirements and violate repository typing rules. |

## Ruling

Generic types in Haxe translate to monomorphized static generics with trait bounds in Rust, and to erased generic type parameters with interface bounds in TypeScript. Runtime type reflection on type parameters is forbidden.

This ruling guarantees zero-cost abstractions across all three languages without incurring runtime type discovery overhead or dynamic dispatch penalties.

## Test hooks

Generic collections are verified by:
- `tests/rust/vector.rs` (lines 54-70)
- `tests/ts/codec.test.ts` (lines 56-64)
- `tests/haxe/Main.hx` (lines 78-88)
