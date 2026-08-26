# Binary spec 02: Binary meta-abstraction

## Scope

This specification rules the architecture for defining binary wire formats as typed metadata. It establishes how a single canonical schema definition in Haxe generates target encoders, decoders, and structural validators for Haxe, Rust, and TypeScript.

This document rules the design approach. The compile-time macro generator described here does not exist in the repository yet.

## Current state

Today, format synchronization relies on manual coordination across three files:
- `haxe/src/boring/VectorCodec.hx`
- `rust/src/lib.rs`
- `ts/src/vector-format.ts`

Format validation and test descriptions are declared in:
- `tests/vectors/roundtrip.json`
- `ts/src/vector-json.ts`

Any change to field width, field order, or numerical types requires manual edits to each encoder and decoder.

## Target schema shape

In the target architecture, Haxe holds the schema definition as strongly typed data structures. A format definition specifies header fields, record collections, primitive wire types, byte widths, endianness, and validation bounds.

A schema definition takes the following typed shape:

```haxe
package boring.meta;

enum WireType {
	WireU8;
	WireU16Be;
	WireU32Be;
	WireF64Be;
	WireAscii(length:Int);
}

typedef FieldDef = {
	final name:String;
	final wireType:WireType;
}

typedef RecordDef = {
	final name:String;
	final fields:Array<FieldDef>;
}

typedef FormatDef = {
	final name:String;
	final header:Array<FieldDef>;
	final records:Array<RecordDef>;
}
```

The glyph metrics format is declared as an immutable instance of `FormatDef`:

```haxe
package boring.meta;

class GlyphMetricsSchema {
	public static final SCHEMA:FormatDef = {
		name: "GlyphMetricsVector",
		header: [
			{ name: "magic", wireType: WireAscii(4) },
			{ name: "recordCount", wireType: WireU32Be }
		],
		records: [
			{
				name: "GlyphMetrics",
				fields: [
					{ name: "codePoint", wireType: WireU32Be },
					{ name: "advanceEm", wireType: WireF64Be },
					{ name: "xMin", wireType: WireF64Be },
					{ name: "yMin", wireType: WireF64Be },
					{ name: "xMax", wireType: WireF64Be },
					{ name: "yMax", wireType: WireF64Be }
				]
			}
		]
	};
}
```

## Reflaxe integration and generator pipeline

Haxe compile-time macros process `FormatDef` declarations at build time. The typed schema metadata integrates with Reflaxe as follows:

1. Macro expansion reads `FormatDef` during compilation.
2. The generator constructs the typed AST (`haxe.macro.Type` and `haxe.macro.Expr`) for codecs, readers, and writers.
3. The Reflaxe compiler target framework transforms the typed AST into target language AST nodes:
   - Rust code emission produces structs with `#[derive(Debug, Clone, Copy, PartialEq)]`, `VectorReader`, `encode_vector`, and `decode_vector`.
   - TypeScript code emission produces typed interfaces with `readonly` properties, `BinaryReader`, `BinaryWriter`, `encodeVector`, and `decodeVector`.
   - Haxe compilation produces typed classes with inline serialization routines.

This pipeline replaces manual cross-language synchronization with deterministic code generation from the Haxe typed AST.
