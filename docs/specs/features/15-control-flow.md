# Feature spec 15: Plain control flow

## Scope

This specification rules the translation of Haxe control-flow statements (`if`/`else`, `switch`, `while`, `do`/`while`, `for`, `break`, `continue`, and early `return`) into Rust, TypeScript, and Kotlin, and the constructs control flow must never translate into. In the current codebase, guard clauses with early exit appear in `samples/boring/VectorCodec.hx`, `reference/rust/src/lib.rs`, `reference/ts/src/vector-format.ts`, and `reference/kotlin/src/boring/VectorCodec.kt`; loops appear in `reference/rust/src/lib.rs` and `reference/ts/src/vector-format.ts`; a counted fill through the Kotlin array initializer appears in `reference/kotlin/src/boring/VectorCodec.kt`; and an exhaustive `match` appears in `reference/rust/src/lib.rs`.

## Haxe construct

Haxe provides the following control-flow statements:

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

Haxe `switch` has no fallthrough: each case body ends at the next case marker without an explicit `break`. Haxe has no labeled `break` or `continue`; leaving an outer loop from inside a nested one uses guard conditions, flag variables, or early `return` from a dedicated function. In the Haxe typed AST, control flow maps to `haxe.macro.TypedExprDef.TIf(econd, eif, eelse)`, `TSwitch(e, cases, edef)`, `TWhile(econd, e, normalWhile)` where `normalWhile` set to false encodes `do`/`while`, `TFor(v, e1, e2)`, `TBreak`, `TContinue`, and `TReturn(e)`.

## Current translations

### Haxe (`samples/boring/VectorCodec.hx`)

```haxe
final magic = reader.readAscii(MAGIC.length);
if (magic != MAGIC) {
	throw new haxe.Exception('bad vector magic: $magic');
}
```

### Rust (`reference/rust/src/lib.rs`)

```rust
if bytes.len() < 4 || &bytes[..4] != VECTOR_MAGIC {
    return Err(VectorError::BadMagic);
}

for record in records {
    bytes.extend_from_slice(&record.code_point.to_be_bytes());
}
```

### TypeScript (`reference/ts/src/vector-format.ts`, `reference/ts/src/codec.ts`)

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

`if`, `while`, `for`, `break`, `continue`, and `return` exist on Rust directly and render unchanged; `switch` translates to `match` with exhaustiveness checking; `do`/`while` translates to `loop` with a trailing `if !cond { break; }`.

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

`if`, `while`, `do`/`while`, `for`, `break`, `continue`, and `return` exist on TypeScript directly and render unchanged; `switch` translates to a `switch` where every case body ends in `return` or `throw`, otherwise to an `if`/`else` chain on the discriminant; the final branch assigns the discriminant to `never` so the compiler rejects missing variants.

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

### Kotlin Candidate 1: Direct statement mapping with when

`if`, `while`, `do`/`while`, `for`, `break`, `continue`, and `return` exist on Kotlin directly and render unchanged; `switch` translates to a `when` expression that is exhaustive over sealed subjects without `else`.

```kotlin
fun describeKind(error: VectorError): String = when (error) {
    is VectorError.BadMagic -> "bad vector magic"
    is VectorError.TrailingBytes -> "trailing bytes in vector"
}

do {
    records.removeAt(records.lastIndex)
} while (records.isNotEmpty())
```

### Kotlin Candidate 2: Exceptions as control flow

Branch selection becomes a thrown exception caught by an enclosing handler.

```kotlin
try {
    if (index == 9) throw LoopExitException()
} catch (exit: LoopExitException) {
    // continue after the loop
}
```

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Rust Candidate 1 (Direct mapping and match) | Branches compile to conditional jumps; exhaustive `match` permits the compiler to omit tag re-tests. | Every case states its variant binding explicitly, and exhaustiveness is compiler-enforced. | Zero wrapper machinery: no closures, no dispatch tables, no intermediate state. | The branch structure follows the wire format's guard order directly. |
| Rust Candidate 2 (Iterator combinators) | Adapter stages are lazy and allocate nothing until a terminal operation, but each stage adds a trait call that inlines only after monomorphization. | Error propagation points hide inside chain stages. | Chain machinery replaces plain statements that need none. | Stacked stages obscure the write order that the wire format fixes. |
| TS Candidate 1 (Direct mapping with never assertion) | Direct branches run as conditional jumps with no allocation. | The `never` assignment turns a missed variant into a compile error. | Zero wrapper machinery: no closures, no dispatch tables, no intermediate state. | The guard chain follows the decode order a reader of the format expects. |
| TS Candidate 2 (Handler dictionary) | Closure values allocate at module initialization and force indirect calls through property lookups. | Closure captures and key strings decouple behavior from the type system's variant checking. | Every branch needs a closure plus a registration entry. | Indirection through string keys hides which code runs for which variant. |
| Kotlin Candidate 1 (Direct mapping and when) | Branches compile to conditional jumps; exhaustive `when` over sealed subjects permits the compiler to omit tag re-tests. | Every branch states its variant binding, and exhaustiveness is compiler-enforced without `else`. | Zero wrapper machinery: no closures, no dispatch tables, no intermediate state. | The `when` arms follow the variant order of the sealed hierarchy. |
| Kotlin Candidate 2 (Exceptions as jumps) | Throw and catch allocate exception instances and unwind stack frames for non-error exits. | The happy path and the exit path separate across two syntactic blocks. | A dedicated exception type exists only to leave a loop. | Readers must scan the catch block to learn the loop exit condition. |

## Ruling

Observable behavior is identical on every platform, and each platform emits its own fastest sound construct; statement-by-statement correspondence with the Haxe source is not a requirement. `if`/`else`, `while`, `break`, `continue`, and early `return` exist on all four targets and render unchanged; Kotlin has native `do`/`while`; Rust renders `do`/`while` as `loop` with a trailing conditional `break` because it has no `do`/`while` syntax. Constructs also merge or change shape when a platform holds a faster form with identical behavior: a counted fill loop lowers to the Kotlin array initializer and the pre-allocated constructor forms ruled in `docs/specs/stdlib/04-haxe-ds-vector.md`, and the fill stops existing as a loop on that platform.

Haxe `switch` translates to Rust `match`. A `match` over an enum declares no catch-all arm, so the compiler enforces exhaustiveness; a `match` over non-enum values adds a catch-all arm and documents the uncovered cases in a comment.

Haxe `switch` translates to TypeScript as a `switch` statement only when every case body ends in `return` or `throw`, which makes JavaScript fallthrough unreachable. When a case body must fall through to shared logic, the translation uses an `if`/`else` chain on the discriminant instead. The final branch of either form assigns the discriminant value to `never`, so adding an enum variant without extending the branch chain fails to compile.

Haxe `switch` translates to Kotlin `when`. Kotlin `when` has no fallthrough between branch bodies. A `when` over a sealed subject declares no `else` branch, so the compiler enforces exhaustiveness; a `when` over non-sealed subjects adds an `else` branch and documents the uncovered cases in a comment.

Exit from nested loops in Haxe source is restructured before translation: the body moves into a dedicated function and exits through early `return`, or the loop conditions gain explicit guard expressions. Rust labeled `break` (`break 'outer`), JavaScript labeled `break`, and Kotlin labeled `break` (`break@outer`) are permitted renderings of the same restructure when the enclosing function cannot be split; Haxe source never contains labels, so labels appear only in generated target code.

Control flow never translates into exceptions used as jumps, handler-closure dictionaries, or functional combinators. Exceptions carry errors only, as ruled in `docs/specs/features/06-errors-and-results.md`; loop translation follows `docs/specs/features/09-iterators.md`.

## Test hooks

Branch outcomes and loop exits are asserted in:
- `tests/rust/vector.rs` (lines 73-96): every error path is one guard clause exercised by a test.
- `tests/ts/codec.test.ts` (lines 66-80): wrong magic and trailing byte guards.
- `tests/haxe/Main.hx` (lines 97-103): the bad magic guard.

Exhaustiveness itself is compile-time behavior; a missed variant fails the build of the affected tree, and no runtime test needs to cover it.

## Switch subject positions (amendment filed 2026-09-01; status: Planned)

The base ruling maps Haxe `switch` onto each target's branch construct and
restricts only the exhaustiveness shape, never the subject's expression
form. The implementation is narrower than the recorded rule: the Kotlin
target renders an enum switch only when the Haxe typer hands the subject
over wrapped in `TEnumIndex` (comment at
`src/reflaxe/kotlin/kotlincompiler/KotlinExpr.hx` line 1110, rejection
`variant switch subject is not a variant value`), and when the typer
promotes a field-access or call subject to `TBlock([TVar _g, TSwitch ...])`
the expression lowering holds no `TBlock` case and the build fails
(reproduction: engine-port walk-through at `BopomofoReading.hx:63`, a
return-position enum switch over a call subject; the port hoists every
non-local switch subject into a named local before switching). The
rejection row `V15 EnumDefaultArm` of the style standard already detects a
subject "wrapped in `TEnumIndex` **or typed as an enum**". This amendment
records the sanctioned form and the lowering rule.

- A `switch` subject may be any expression (a local, a field access, or a
  call) whose static type is the enum (features/01) or the sealed
  interface (features/32) being switched.
- The common layer hoists a non-local subject into a synthetic local
  exactly once, before target emission, so every target receives the
  already-supported local-subject shape and no target holds
  subject-specific code. The synthetic name follows the minting rules of
  `src/PipelineExpander.hx` (function `mint`, line 154).
- A subject of type `Null<E>` keeps the existing guard-then-switch form:
  the source checks null explicitly, binds `final v:E = o;`, and switches
  `v`. Switching a `Null<E>` subject directly stays outside the
  translatable subset.
- Non-enum subjects keep the base ruling unchanged: exhaustive over sealed
  subjects with no else arm, and an else arm carrying the uncovered-cases
  comment over anything else.

Test hooks: a sample switches over one enum through a field subject and
through a call result; the tree assertions show the synthetic hoisted local
in every target tree; a mutation switching a `Null<E>` subject directly
keeps the existing rejection.
