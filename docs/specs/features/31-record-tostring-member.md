# Feature spec 31: record `toString` member synthesis

Status: Implemented. This specification amends one sentence of ruling 1 in
[27-class-members-and-records.md](27-class-members-and-records.md)
("No target synthesizes record members"); everything else in 27 stands.

## Current state

Feature 27 made the printed form a call-site macro: `std.RecordStr.str(r)`
expands into the concatenation `Name(field=value, ...)`, and `@:dataClass`
renders `data class` on Kotlin so the native synthesis prints the same
text. No target synthesizes a record member, so a `@:dataClass` class
without an explicit zero-argument `toString` has no printed form outside
Kotlin: on TS, Swift, Dart, Rust, and in stage 1, `x.toString()` does not
resolve and `Std.string(x)` / `"" + x` print the default object text.

The engine port is the consumer that pays. Its tree carries 40
hand-written zero-argument `toString` members, four of them on
`@:dataClass` classes that also wanted the marker; its trace goldens pin
`Name(field=value, ...)` byte for byte, so the printed form is behavior.
Every ported class adds another member by hand, and the remaining port
waves would add dozens more. The macros cannot take over the call sites:
`Std.string(expected)` over a dynamic receiver cannot expand a macro, and
the member syntax is what the port's own code and hand-written Kotlin
consumers read.

## Haxe construct

```haxe
@:dataClass
class Size {
	public final width:Float;
	public final height:Float;

	public function new(width:Float, height:Float) {
		this.width = width;
		this.height = height;
	}
}

// no explicit toString anywhere; all three lines print
// "Size(width=1.5, height=2.0)"
final a = size.toString();
final b = Std.string(size);
final c = "" + size;
```

A class that declares its own zero-argument `toString` keeps it and gets
no synthesis, matching the Kotlin rule that an explicit member wins over
the `data class` synthesis.

## Current translations

| Feature | TS | Kotlin | Swift | Dart | Rust | stage 1 |
| --- | --- | --- | --- | --- | --- | --- |
| explicit `toString` member | rendered (27 ruling 7: plain method) | rendered with `override` | rendered | rendered | rendered | rendered |
| `@:dataClass` without explicit member | no printed form | native `data class` synthesis | no printed form | no printed form | no printed form | no printed form |
| `RecordStr.str` call site | expansion rendered | expansion rendered | expansion rendered | expansion rendered | expansion rendered | macro runs |

## Candidate translations

### Where the member comes from

**S1: the compiler synthesizes the member where the class has none.**
`@:dataClass` without an explicit zero-argument `toString` gains the
member on TS, Swift, Dart, Rust, and in stage 1. Kotlin emits nothing
extra: the `data class` synthesis already supplies the identical text,
and the port's `.toString()` call sites resolve against it.

- performance: the synthesized body is the same concatenation AST the
  hand-written member compiled to; no runtime difference.
- ambiguity: the text has one definition (see T1 below) and one
  cross-check (the goldens that pin it byte for byte).
- redundancy: one synthesis in the compiler plus one build macro for
  stage 1.
- readability: call sites keep member syntax everywhere.

**S2: status quo plus `RecordStr.str` at every call site.** Rejected:
dynamic receivers (`Std.string(expected)` in the port's assertion layer)
cannot expand a macro, and rewriting the port's call sites to a macro
name is churn without removing any hand-written member.

**S3: keep hand-writing members.** Rejected: the per-class repetition is
the maintenance cost this feature exists to remove; it grows with every
port wave.

### Where the text comes from

**T1: one assembly routine.** `RecordShape` gains a local-class entry,
and the field concatenation is built by one routine shared by
`RecordStr.str` and the member synthesis. boring translates that one AST
through the per-target `+` and member lowerings that already exist; no
emitter writes its own format string or field list. A record-typed field
prints through that field's own printed form (the synthesized or explicit
member); where the current `+` lowering has no object arm, the routine
emits the explicit member call for that operand. Float operands go
through the same conversion the `String + Float` lowering uses; no
target-default interpolation is introduced.

**T2: each emitter formats independently.** Rejected: five texts that
nothing keeps equal.

## Ruling

1. **A `@:dataClass` class without an explicit zero-argument `toString`
   gets a synthesized member on TS, Swift, Dart, Rust, and in stage 1.**
   The member is public, zero-argument, returns `String`, and produces
   the same text as `RecordStr.str` on the same receiver and as the
   Kotlin `data class` synthesis; 27's text-identity guarantee extends to
   it. Kotlin emits no member.
2. **An explicit zero-argument `toString` suppresses the synthesis on
   every target and in stage 1.** The explicit member wins, as in Kotlin.
3. **The field set is the constructor parameters held by fields, in
   constructor parameter order**, the class-record set of 27 ruling 1.
   A class whose constructor parameters are not all held by fields stops
   the compilation with the existing macro error; a class with no
   constructor parameters stops it with the existing marker validation.
4. **One assembly routine builds the body.** `RecordStr.str` and the
   member synthesis construct the concatenation through the same
   function over `RecordShape`; per-target text knowledge stays confined
   to the existing `+` and member lowerings. The synthesized AST differs
   from a hand-written member's compiled form in nothing a target can
   observe. A nullable record-typed field prints through an explicit
   null comparison around the member call: `null` prints `"null"` and a
   present value prints the field's member text, the same two states the
   Kotlin `data class` synthesis prints. A non-nullable record-typed
   field carries no comparison; Swift and Rust have no valid nil or
   None comparison for a non-optional operand. The Rust target lowers the
   comparison on a nullable operand to `is_none()` / `is_some()`
   because Option equality against `None` would require `PartialEq` on
   the inner type; a member call on a nullable receiver lowers through
   the optional unwrap the field read already uses; a nullable
   constructor parameter wraps every non-null argument in `Some`; and a
   lone string literal beside an owned-String member-call branch of a
   conditional converts to `.to_string()`, because Rust rejects the
   `&str` and `String` pair as one expression.
5. **Stage 1 wires the member through one global-metadata line.** The
   consumer's hxml adds
   `--macro haxe.macro.Compiler.addGlobalMetadata('<package>', '@:build(std.RecordMember.build())')`;
   the build macro adds the member to marked classes only and returns
   unmarked classes unchanged.
6. **Regeneration stays byte-identical for classes outside the
   feature.** Classes without the marker, and marked classes that keep an
   explicit member, regenerate exactly as before. A marked class without
   an explicit member is inside the feature: its TS, Swift, Dart, Rust,
   and stage-1 trees gain the member on regeneration, and its Kotlin
   tree stays byte-identical because Kotlin emits no member either way.
   Pre-existing sample classes in that state, `ValueRecord` today,
   change their TS, Swift, Dart, and Rust trees once this feature is
   implemented; that change is how the feature takes effect on those
   classes.

## Test hooks

- `samples/boring/PrintedRecord.hx`: a `@:dataClass` class with no
  explicit member and an int field, a float field, a field of another
  record type, and a nullable field of that record type; the tests
  assert the null and present states of the nullable field.
  `samples/boring/PrintedCustom.hx`: a `@:dataClass` class
  that declares an explicit `toString` printing custom text. Both are
  entered in the entry lists of all eight generation hxml files.
- `samples/std/RecordMember.hx`: the stage-1 build macro beside
  `RecordCopy` / `RecordEq` / `RecordStr`, sharing the assembly routine.
- `tests/PrintedRecordTests.hx` asserts: the member text equals
  `RecordStr.str` on the same receiver; `Std.string(x)` and `"" + x`
  equal the member text; the nested field prints the inner record's
  `Name(...)` form; `PrintedCustom` prints its custom text.
- Tree assertions per target: the TS, Swift, Dart, and Rust trees carry
  the synthesized member with the constructor parameter order; the
  Kotlin tree carries the `data class` prefix and no explicit member for
  `PrintedRecord`, and the explicit `override fun toString` for
  `PrintedCustom`.
- Mutations: removing the marker from `PrintedRecord` drops the member
  from the four trees; adding an explicit member to `PrintedRecord`
  suppresses the synthesis on the four trees; the Kotlin tree gains
  exactly that explicit member (`override fun toString`, occurring once)
  and nothing else, because the explicit member wins on Kotlin too.
- The samples hxml gains the global-metadata line of ruling 5;
  `bun run test:haxe` covers stage 1.
- Coverage: the eight generation steps and the full `bun run verify` of
  feature 27's hooks.

## Port follow-through

Once this feature is implemented and the vendored pointer advances, the
port deletes the mechanical `toString` members in a dedicated mechanical
pass: an unchanged golden output is the acceptance, and any class whose
hand-written field order or field set differs from the constructor
parameters keeps its explicit member, named by the golden diff.
