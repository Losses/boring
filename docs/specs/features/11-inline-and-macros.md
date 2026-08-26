# Feature spec 11: Inline and macros

## Scope

This specification rules the translation of Haxe `inline` variable declarations, `inline` member functions, and compile-time macro transformations into Rust and TypeScript. In the current codebase, inline constants appear in Haxe as `VectorCodec.MAGIC` in `haxe/src/boring/VectorCodec.hx` (line 11), in Rust as `VECTOR_MAGIC` and `RECORD_BYTE_LENGTH` in `rust/src/lib.rs` (lines 24, 25), and in TypeScript as `VECTOR_MAGIC` and `RECORD_BYTE_LENGTH` in `ts/src/vector-format.ts` (lines 10, 11). Macro architecture for binary schema generation is defined in `docs/specs/binary/02-binary-meta-abstraction.md`.

## Haxe construct

Haxe provides the `inline` keyword for constant variables and functions:

```haxe
public static inline var MAGIC:String = "BRG1";

public static inline function recordByteLength():Int {
	return 44;
}
```

The Haxe compiler replaces inline variables and inline function calls with their literal values or inlined expression bodies during typing.

Haxe macros execute during compilation within an embedded Neko or eval interpreter. Macros read, analyze, and construct typed AST nodes (`haxe.macro.Expr`, `haxe.macro.Type`, `haxe.macro.Context`). As defined in `docs/specs/binary/02-binary-meta-abstraction.md`, build-time macros consume strongly typed `FormatDef` schema instances and construct AST definitions for encoders and decoders before target code emission via Reflaxe.

In the Haxe typed AST, inline member functions are marked by `FieldKind.FMethod(MethodKind.MethInline)` on `haxe.macro.Type.ClassField`; inline variables are substituted during typing, and call sites expand directly to the inlined expression `TypedExpr`. Macro expressions are represented in the macro AST by `haxe.macro.Expr.ExprDef.EMeta` and macro execution contexts.

## Current translations

### Haxe (`haxe/src/boring/VectorCodec.hx`)

```haxe
class VectorCodec {
	public static inline var MAGIC:String = "BRG1";
	// ...
}
```

### Rust (`rust/src/lib.rs`)

```rust
pub const VECTOR_MAGIC: &[u8; 4] = b"BRG1";
pub const RECORD_BYTE_LENGTH: usize = 44;
```

### TypeScript (`ts/src/vector-format.ts`)

```ts
export const VECTOR_MAGIC = "BRG1";
export const RECORD_BYTE_LENGTH = 44;
```

## Candidate translations

### Rust Candidate 1: const items and const fn

```rust
pub const VECTOR_MAGIC: &[u8; 4] = b"BRG1";
pub const RECORD_BYTE_LENGTH: usize = 44;

pub const fn record_byte_length() -> usize {
    RECORD_BYTE_LENGTH
}
```

### Rust Candidate 2: Runtime procedural macro dependency in crate tree

```rust
#[derive(BinaryCodec)]
#[wire(magic = "BRG1")]
pub struct GlyphMetricsRecord {
    pub code_point: u32,
    pub advance_em: f64,
}
```

### TypeScript Candidate 1: Top-level const bindings with const assertions

```ts
export const VECTOR_MAGIC = "BRG1";
export const RECORD_BYTE_LENGTH = 44;
```

### TypeScript Candidate 2: Dynamic runtime schema evaluation function

```ts
export function getCodecConfig(): Record<string, unknown> {
  return eval("({ magic: 'BRG1', recordLength: 44 })");
}
```

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Rust Candidate 1 (const items and const fn) | Values fold into binary text segments with zero runtime compute or allocation overhead. | Exact types and integer widths are verified by the compiler at build time. | Constants are declared once and referenced directly across encoder functions. | Standard const declarations communicate compile-time values directly. |
| Rust Candidate 2 (Procedural macro) | Macro expansion generates inline code during crate compilation. | Hidden code generation within macro attributes obscures wire serialization logic. | Code generation logic is duplicated between Haxe Reflaxe generators and Rust proc macros. | Attribute macros conceal field encoding mechanics from readers inspecting the file. |
| TS Candidate 1 (Top-level const) | Top-level constants compile to direct primitive loads with zero object overhead. | Explicit primitive types prevent reassignment and mutations. | Single constant definitions serve all modules in the package. | Standard const statements express immutable module values directly. |
| TS Candidate 2 (Runtime eval evaluation) | Dynamic evaluation forces interpreter parsing overhead during module execution. | Untyped dynamic code evaluation bypasses TypeScript static type checking. | Dynamic logic forces redundant runtime validation of fixed schema structures. | Dynamic evaluation introduces indirect reflection into straightforward codecs. |

## Ruling

Haxe `inline var` constants translate to top-level `pub const` items in Rust and top-level `export const` bindings in TypeScript, while Haxe `inline` accessor functions translate to `const fn` or `#[inline]` functions in Rust and direct functions in TypeScript.

Haxe compile-time macros operate exclusively at build time within the Reflaxe compiler pipeline to generate target source code. No runtime behavior in the generated Rust and TypeScript codebases may depend on macro interpreters or dynamic runtime code evaluation.

## Test hooks

Constants and wire dimensions are asserted in:
- `tests/rust/vector.rs` (lines 7, 73-78)
- `tests/haxe/Main.hx` (lines 45-50, 79-82)
- `tests/ts/codec.test.ts` (lines 6, 38-39)
- `tests/ts/vector.test.ts` (lines 1-25)
