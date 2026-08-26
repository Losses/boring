# Feature spec 15: Plain control flow

## Scope

This specification rules the translation of Haxe statement-level control flow (`if`/`else`, `switch`, `while`, `do`/`while`, `for`, `break`, `continue`, and early `return`) into Rust and TypeScript, and the constructs control flow must never translate into. In the current codebase, guard clauses with early exit appear in `haxe/src/boring/VectorCodec.hx` (lines 31-33, 49-51), `rust/src/lib.rs` (lines 101-103), and `ts/src/vector-format.ts` (lines 33-35, 48-50); loops appear in `rust/src/lib.rs` (lines 89, 108) and `ts/src/vector-format.ts` (lines 19, 38); an exhaustive `match` appears in `rust/src/lib.rs` (lines 37-47); and an early-return guard appears in `ts/src/codec.ts` (line 64).

## Haxe construct

Haxe provides the following statement-level control flow:

```haxe
if (reader.remaining() != 0) {
	throw new haxe.Exception('trailing bytes');
}

final magic = switch (error) {
	case BadMagic: "bad vector magic";
	case TrailingBytes(remaining): 'trailing bytes in vector: $remaining';
};

while (reader.remaining() > 0) {
	reader.readU32();
}

do {
	records.pop();
} while (records.length > 0);

for (record in records) {
	writer.writeU32(record.codePoint);
}

for (index in 0...count) {
	if (index == 3) continue;
	if (index == 9) break;
}
```

Haxe `switch` has no fallthrough: each case body ends at the next case marker without an explicit `break`. Haxe has no labeled `break` or `continue`; multi-level loop exit uses guard conditions, flag variables, or early `return` from a dedicated function. In the Haxe typed AST, control flow maps to `haxe.macro.TypedExprDef.TIf(econd, eif, eelse)`, `TSwitch(e, cases, edef)`, `TWhile(econd, e, normalWhile)` where `normalWhile` set to false encodes `do`/`while`, `TFor(v, e1, e2)`, `TBreak`, `TContinue`, and `TReturn(e)`.

## Current translations

### Haxe (`haxe/src/boring/VectorCodec.hx`)

```haxe
final magic = reader.readAscii(MAGIC.length);
if (magic != MAGIC) {
	throw new haxe.Exception('bad vector magic: $magic');
}
```

### Rust (`rust/src/lib.rs`)

```rust
if bytes.len() < 4 || &bytes[..4] != VECTOR_MAGIC {
    return Err(VectorError::BadMagic);
}

for record in records {
    bytes.extend_from_slice(&record.code_point.to_be_bytes());
}
```

### TypeScript (`ts/src/vector-format.ts`, `ts/src/codec.ts`)

```ts
if (magic !== VECTOR_MAGIC) {
  throw new Error(`bad vector magic: ${magic}`);
}

private ensure(extra: number): void {
  const required = this.length + extra;
  if (required <= this.buffer.length) return;
}
```

## Candidate translations

### Rust Candidate 1: Direct statement mapping with match

`if`/`while`/`for`/`break`/`continue`/`return` translate statement for statement; `switch` translates to `match` with exhaustiveness checking; `do`/`while` translates to `loop` with a trailing `if !cond { break; }`.

```rust
match error {
    VectorError::BadMagic => "bad vector magic",
    VectorError::TrailingBytes { .. } => "trailing bytes in vector",
}

loop {
    records.pop();
    if records.is_empty() {
        break;
    }
}
```

### Rust Candidate 2: Iterator combinators replacing loops

Loop bodies become adapter chains over iterators.

```rust
let bytes: Vec<u8> = records
    .iter()
    .flat_map(|record| record.code_point.to_be_bytes())
    .collect();
```

### TypeScript Candidate 1: Direct statement mapping with exhaustiveness assertion

`if`/`while`/`do`/`while`/`for`/`break`/`continue`/`return` translate statement for statement; `switch` translates to a `switch` where every case body ends in `return` or `throw`, otherwise to an `if`/`else` chain on the discriminant; the final branch assigns the discriminant to `never` so the compiler rejects missing variants.

```ts
function describeKind(kind: VectorError["kind"]): string {
  if (kind === "BadMagic") {
    return "bad vector magic";
  }
  if (kind === "TrailingBytes") {
    return "trailing bytes in vector";
  }
  const exhausted: never = kind;
  return exhausted;
}
```

### TypeScript Candidate 2: Dictionary of handler closures

Branch selection becomes a lookup of function values stored in an object.

```ts
const HANDLERS: Record<string, () => string> = {
  BadMagic: () => "bad vector magic",
};

const description = HANDLERS[kind]();
```

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Rust Candidate 1 (Direct mapping and match) | Branches compile to conditional jumps; exhaustive `match` permits the compiler to omit tag re-tests. | Every case states its variant binding explicitly, and exhaustiveness is compiler-enforced. | One construct in, one construct out. | Statement-level translation reads the same in source and target. |
| Rust Candidate 2 (Iterator combinators) | Adapter chains allocate closures and intermediate collections per stage, as ruled in features/09. | Error propagation points hide inside chain stages. | Chain machinery replaces plain statements that need none. | Stacked stages obscure the write order that the wire format fixes. |
| TS Candidate 1 (Direct mapping with never assertion) | Direct branches run as conditional jumps with no allocation. | The `never` assignment turns a missed variant into a compile error. | One construct in, one construct out. | Statement-level translation reads the same in source and target. |
| TS Candidate 2 (Handler dictionary) | Closure values allocate at module initialization and force indirect calls through property lookups. | Closure captures and key strings decouple behavior from the type system's variant checking. | Every branch needs a closure plus a registration entry. | Indirection through string keys hides which code runs for which variant. |

## Ruling

`if`/`else`, `while`, `do`/`while`, `break`, `continue`, and early `return` translate statement for statement in all three languages. Rust renders `do`/`while` as `loop` with a trailing conditional `break` because it has no `do`/`while` syntax.

Haxe `switch` translates to Rust `match`. A `match` over an enum declares no catch-all arm, so the compiler enforces exhaustiveness; a `match` over non-enum values adds a catch-all arm and documents the uncovered cases in a comment.

Haxe `switch` translates to TypeScript as a `switch` statement only when every case body ends in `return` or `throw`, which makes JavaScript fallthrough unreachable. When a case body must fall through to shared logic, the translation uses an `if`/`else` chain on the discriminant instead. The final branch of either form assigns the discriminant value to `never`, so adding an enum variant without extending the branch chain fails to compile.

Multi-level exit from nested loops in Haxe source is restructured before translation: the body moves into a dedicated function and exits through early `return`, or the loop conditions gain explicit guard expressions. Rust labeled `break` (`break 'outer`) and JavaScript labeled `break` are permitted renderings of the same restructure when the enclosing function cannot be split; Haxe source never contains labels, so labels appear only in generated target code.

Control flow never translates into exceptions used as jumps, handler-closure dictionaries, or functional combinators. Exceptions carry errors only, as ruled in `docs/specs/features/06-errors-and-results.md`; loop translation follows `docs/specs/features/09-iterators.md`.

## Test hooks

Branch outcomes and loop exits are asserted in:
- `tests/rust/vector.rs` (lines 73-96): every error path is one guard clause exercised by a test.
- `tests/ts/codec.test.ts` (lines 66-80): wrong magic and trailing byte guards.
- `tests/haxe/Main.hx` (lines 97-103): the bad magic guard.

Exhaustiveness itself is compile-time behavior; a missed variant fails the build of the affected tree, and no runtime test needs to cover it.
