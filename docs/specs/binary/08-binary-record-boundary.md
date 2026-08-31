# Binary spec 08: Binary record boundary

## Scope

This specification rules the boundary of a generated package: which declarations consumers outside the boring Haxe pipeline may name, which declarations stay inside the system, what the compiler converts where the two meet, and how one boring library consumes another. The buffer kinds and position types are ruled in `02-binary-record-io.md`; the rewrite whose signatures this boundary protects is ruled in `07-binary-record-optimization.md`.

This document rules the tiers, the conversions, and the emitted shapes. None of the boundary machinery exists in the repository yet.

## Requirement

Before this specification every target publishes every top-level declaration. `TsDecl.hx` writes `export` on each top-level declaration unconditionally (lines 67, 75, 105, 355), `RustDecl.hx` writes `pub` (lines 45, 102, 131, 240), `KotlinDecl.hx` emits classes with no modifier, which Kotlin reads as public (lines 82, 149), and `SwiftDecl.hx` writes no access modifier at all. The spec 24 exports map lists one wildcard per emitted directory and holds no root entry, so a consumer of a generated package imports by deep module path and reaches any internal name.

For the codec tree this is tolerable: the consumers are repository builds that name their own modules. For a library whose internal signatures the compiler rewrites, binary spec 07 threads implicit buffer parameters through them, a deep import path is a contract the compiler must break, and a position value that crosses out of the system names bytes its holder cannot resolve.

## Tiers

Every declaration of a compilation belongs to one of three tiers.

1. **Private members** stay internal to their declaring class, under the visibility mapping of `features/12-classes-interfaces-access.md`.
2. **System declarations** are the public declarations of the boring Haxe system. Another boring compilation may import them, and they may name buffer kinds and position types.
3. **Foreign-facing declarations** are the public declarations a consumer outside the boring pipeline may name. They are selected from the public declarations by the deep check below, and the package exports them through its root entry.

## The deep check

The check walks each public top-level declaration through every field and every signature, transitively, private members included. It excludes exactly the types the rewrite of binary spec 07 owns: buffer kinds (`GlyphMetricsBuffer`) and position types (`GlyphMetricsPos`). A declaration whose graph names a buffer kind or a position type at any depth is a system declaration; a declaration whose graph names none is foreign-facing.

Two reasons state the criterion. A consumer outside the boring pipeline cannot supply a buffer through the implicit threading, and a position without its buffer names bytes the consumer cannot resolve. A buffer reference held in a published object also keeps the whole block alive for the object's lifetime, while a copied record occupies its own bytes.

`haxe.io.Bytes` and the runtime class `RecordBuffer` pass the check: they hold bytes and carry no per-format identity, the property the rewrite keys on. A foreign-facing class may hold a `RecordBuffer` field; that holding is consumer-side ownership of the bytes. A foreign-facing class may not hold a buffer kind or a position value: the first stops the compilation with `foreign-facing class holds a record buffer member: hold haxe.io.Bytes or RecordBuffer, or keep the reader class internal and publish a value facade`, and the second with `foreign-facing class holds a record position member: materialize at the return and store the record`.

## Conversions at the boundary

1. **Materialization at returns.** At every return point of a foreign-facing function, the compiler converts the returned value to the declared return type. A declared record type receives one allocation built field by field from buffer reads, deep over all levels: a nested record field materializes recursively, and so does each element of a collection of records. A primitive type receives the value. A foreign-facing class return type receives the instance the body constructed: the author constructs published objects directly, and the compiler inserts nothing there. Materialization produces values; a class instance is never its output. The author writes no conversion code for records and primitives; the conversion is the `toRecord` copy of binary spec 02, inserted by the compiler.
2. **Re-entry is authored.** The compiler inserts nothing on entry. A foreign-facing function that receives record values and needs the buffer again performs a lookup by (buffer, key) that the library writes, for example an index from code point to position. A materialized record re-enters exactly when its meaning is a function of (buffer, key): the record carries a key field, the re-entry lookup holds the buffer internally, and the lookup restores the starting position. Everything an internal chain derived from the buffer is then recoverable regardless of chain length: each link is deterministic derivation from buffer content, the copy dropped the position only, and re-entry is recomputation. Inputs the chain consumed that do not come from the buffer re-enter as record fields or as parameters of the re-entry function, both of which are values; a record that carries no key and none of its inputs is terminal data. State that accumulates across calls belongs on a system declaration: an internal class holding a buffer field binds its position reads to that field (binary spec 07 ruling 4), keeps its private state, and never crosses the boundary, so nothing needs restoring. The optimization holds inside generated code; code the consumer writes by hand is outside the compiler's reach.
3. **The loaded-table shape.** A library that loads a block and serves lookups writes two declarations: a system declaration holding the buffer, the record count, and any key indices, and a foreign-facing facade holding plain values or nothing, forwarding calls and returning records. The author writes both; the compiler runs the deep check on the facade and inserts materialization at its returns. The facade shape with a constructor from `haxe.io.Bytes` builds its buffer internally, materializes what it stores, and drops the buffer reference when the constructor returns, so the block stays alive only while the facade needs it.

## Visibility lowering

| Target | Foreign-facing declaration | System declaration |
| --- | --- | --- |
| Rust | `pub` | `pub(crate)` |
| Kotlin | no modifier (public) | `internal` |
| Swift | `public` | no modifier (module-internal) |
| Dart | no modifier | `_` prefix (library-private) |
| TypeScript | module export under the source name, re-exported from the root entry | cross-module: export under the prefixed name; own module: no export |

`RustDecl.hx` line 547 holds the `pub(crate)` precedent. Kotlin, Swift, and Dart keep their native keyword or default, so the generated text states the split in the vocabulary each ecosystem already reads.

Two target rulings complete the table:

- **TypeScript cross-module prefix.** A system declaration referenced from another generated module keeps its module export under the name `internal` followed by the original name with its first character uppercased (`internalHashEntry`). Removing the prefix restores the source name, so a grep maps generated text back to source. A system declaration referenced only inside its own module loses the `export` keyword and keeps the source name.
- **Dart library assembly.** When the boundary is active, the emitted Dart tree becomes one library: the root library file holds the imports and the `part` directives, and every other emitted file begins with `part of`. The `_` prefix on system declarations is then private to the library and visible across all parts.

## Root entry

When foreign-facing declarations exist, each target gains a root entry generated from the derived set. TypeScript writes `index.ts` at the tree root, re-exporting every foreign-facing top-level name from its module; the spec 24 exports map then lists the root entry `.` plus `"./runtime"` when the compilation used the runtime, and nothing else, so deep module paths stop being part of the package contract. Rust adds one `pub use` per foreign-facing name to the crate root `lib.rs`. Swift needs no entry file: `public` on the foreign-facing names plus the one package target of spec 24 is the whole mechanism. Kotlin needs no entry file: package structure plus visibility is the mechanism. Dart uses the root library file of the Dart assembly ruling.

The entry re-exports names sorted by name, and the entry module set is a pure function of the derived foreign-facing set, following the spec 24 determinism rule: two identical compilations produce identical entries.

## Cross-library source packages

One boring library consumes another through the producer's package, which carries the producer's Haxe source tree beside the emitted target tree; this ruling replaces the earlier declaration-file design, which shipped signatures without general bodies. The consumer's compilation resolves its Haxe imports against the shipped source, runs every common-layer pass over the union of the producer's modules and the consumer's own, and emits only its own modules; the emitted references name the producer's package artifacts. The shipped source lets every pass see the whole program of both libraries, and no second description format restates what the source already states.

Because the consumer compiles the producer's modules, the passes of binary spec 07, of `features/22-default-argument-expansion.md`, and of `macros/01-functional-idiom-expansion.md` run over that union, and the signatures the consumer derives for the producer's functions match the signatures of the producer's already-emitted tree: same boring version, same passes, same result. A producer release that changes no public declaration can still change what the consumer's passes derive from the producer's bodies; the consumer pins the producer package version, so a producer change ships as a new package version and the consumer recompiles when it adopts it. The package manifest records the boring version of the compiler that emitted the tree; a consumer compilation running a different version refuses the package with `library source version mismatch: library A was emitted by boring X, this compilation runs boring Y`. The spec 24 package shell lists the shipped source modules in its write list, so the artifact step of spec 25 packs them.

`RecordBuffer` keeps one runtime identity in boring's shared support library, so the producer and the consumer link one implementation of it. Consumers outside the boring pipeline never compile the shipped source; they consume the root entry.

## Boundary selection compared

### Candidate 1: Derived foreign-facing set (selected)

The compiler computes the foreign-facing set from the declarations by the deep check.

- performance: no runtime cost; the check and the lowering are emission text.
- ambiguity: the criterion is the ownership of the threading rewrite, one rule for every declaration.
- redundancy: nothing restates the set; the entry and the lowering derive from it.
- readability: generated code states its visibility per target in the target's own vocabulary.

### Candidate 2: Author marker

Authors mark published declarations; the compiler derives the lowering and the entry from the marker set.

- performance: as Candidate 1.
- ambiguity: the marker sits on the governed declaration.
- redundancy: the marker restates a fact the compiler can compute; a signature change that adds a position parameter leaves the marker in place and the check unrun.
- readability: the published set reads from the source directly.

### Candidate 3: Status quo

Everything is public; consumers import deep module paths.

- performance: no runtime cost.
- ambiguity: every internal name is a contract in effect; rewrites in the common layer become visible breaking changes.
- redundancy: none.
- readability: consumers see the whole internal body with no stated contract.

### Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| C1 derived set | no runtime cost | one criterion, ownership of the threading | nothing restates the set | per-target vocabulary |
| C2 author marker | no runtime cost | marker on the declaration | marker restates a computable fact | published set reads from source |
| C3 status quo | no runtime cost | every internal name is a contract | none | no stated contract |

Principle application: the set is computed from information the compiler already holds, and the author states nothing (P4). Candidate 3 publishes constructs whose signatures the rewrite of binary spec 07 changes, the restriction this specification addresses; the sanctioned path for reaching internals is the generated root entry (P2). Candidate 2 keeps one advantage, stating a general published API with no record format; that need stays on the spec 24 exports map, and introducing it requires revising this specification first, so no marker rides along unused.

## Activation and compatibility

The tiers, the visibility lowering, the root entry, and the Dart assembly activate when the compilation declares at least one annotated record format (binary spec 02). A compilation with no annotated format emits exactly what the compiler emitted before this specification: no visibility change, no prefix, no library assembly, no entry, and the spec 24 exports map unchanged. Existing pinned outputs and the spec 25 artifacts stay valid without edits.

The interaction with spec 25: the package artifacts step compiles the recorded write list, which now includes `index.ts`; the npm tarball resolves its entry point to the compiled root module, and the generated declarations of prefixed cross-module exports stay in their per-module declaration files, outside the root re-export.

## Test hooks

Required once the boundary machinery exists; none exist yet:

- A sample tree with one annotated format compiles on the TypeScript lane; the test asserts the `index.ts` re-export list, the root-only exports map, the cross-module prefix on system declarations, the exclusion of a kind-naming declaration from the entry, and the materialization inserted at a foreign-facing return.
- Rejection tests for the named errors of the deep check: a buffer-kind member and a position member on a foreign-facing class.
- The pinned-output lanes for Rust, Kotlin, Swift, and Dart gain assertions for `pub(crate)`, `internal`, `public`, and the `_` prefix on the same sample tree.
- A two-library fixture asserts the shipped source tree inside the producer package, the refusal on version mismatch, that the consumer emits only its own modules with references into the producer package, and the inlining of the producer's read functions in the consumer's emitted code.
- A compilation with no annotated format is asserted byte-identical to the emission before this specification, guarding the activation rule.
