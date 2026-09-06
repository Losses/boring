# Feature spec 57: Object literal construction contract

## Scope

This specification rules object literal construction, field ordering, record
validation, and the TypeScript immutability option across Dart, TypeScript,
Kotlin, Swift, and Rust. It distinguishes anonymous object construction from
the existing named-record lowering path. It does not prescribe target
constructor syntax or make target ownership and immutability mechanisms
universal.

## Current verification

| Target or mechanism | Current verification anchor | Current form |
| --- | --- | --- |
| Haxe expression shape | `packages/compiler/reflaxe/dart/dartcompiler/DartExpr.hx:1127-1128` | A `TObjectDecl` is routed to the target object-literal renderer. |
| Dart named record path | `packages/compiler/reflaxe/dart/dartcompiler/DartExpr.hx:2682-2701` | Resolves a named record, maps fields by name, emits declaration order, reports a missing field, imports the type, and calls its constructor. |
| TypeScript object path | `packages/compiler/reflaxe/ts/tscompiler/TsExpr.hx:2320-2337` | Takes `(fields, immutable:Bool)`, preserves source order, supports local shorthand, and recursively applies the platform immutability operation when requested. |
| TypeScript immutability call sites | `packages/compiler/reflaxe/ts/tscompiler/TsExpr.hx:1015-1017`, `:1070-1071`, and `:2340-2345` | Decode fills request the immutable form; ordinary expressions request the mutable form; nested object literals recurse through the immutable form. |
| Kotlin | `packages/compiler/reflaxe/kotlin/kotlincompiler/KotlinExpr.hx:3093-3097` | Resolves a target type and emits named constructor arguments. |
| Swift named record path | `packages/compiler/reflaxe/swift/swiftcompiler/SwiftExpr.hx:2807-2825` | Resolves a record, maps names, validates missing fields, and emits declaration-order memberwise arguments. |
| Rust | `packages/compiler/reflaxe/rust/rustcompiler/RustExpr.hx:5484-5501` | Emits a struct literal, target field names, and clone or `to_string` conversions for string values. |
| Compile-time failure path | Dart `packages/compiler/reflaxe/dart/dartcompiler/DartExpr.hx:2694-2695` and `:3746-3748` | A missing record field reaches target `fail`, which calls `Context.error`; this is not a runtime failure. |

## Semantics ruling

1. The Haxe baseline for an object literal is construction of an anonymous
   structure whose fields are evaluated and represented in source order. The
   named-record path is an existing target mechanism for materializing that
   structure as a generated record type; it is not a new semantic category.
   The Haxe expression dispatch is visible at Dart
   `packages/compiler/reflaxe/dart/dartcompiler/DartExpr.hx:1127-1128`, while
   the named-record resolution and construction path is visible at Dart
   `:2682-2701` and Swift `:2807-2825`.

2. Source order is the ordering contract for an anonymous object literal. A
   target must preserve the order of the source field list when it emits a
   native anonymous object, as TypeScript does at
   `packages/compiler/reflaxe/ts/tscompiler/TsExpr.hx:2320-2337`. For a
   named-record lowering, the target constructor's declaration order is the
   applicable existing mechanism: Dart iterates `recordFieldNames(def)` at
   `packages/compiler/reflaxe/dart/dartcompiler/DartExpr.hx:2691-2698`, and
   Swift does so at `packages/compiler/reflaxe/swift/swiftcompiler/SwiftExpr.hx:2816-2824`.
   These rules coexist: source order governs anonymous construction, while
   declaration order governs the named-record constructor path.

3. A record literal must contain every required record field and no field that
   is absent from the resolved record schema. Missing fields are rejected, as
   shown by Dart's `fail` call at
   `packages/compiler/reflaxe/dart/dartcompiler/DartExpr.hx:2692-2695`.
   Extra fields are likewise rejected by the contract, even where a current
   target map would otherwise ignore or overwrite them. Both errors are
   compile-time failures at the target's `Context.error` path; they are never runtime
   object failures; Dart's error wrapper is at `:3746-3748`. The diagnostic
   wording may remain target-local, but accepting either mismatch is not
   conforming.

4. TypeScript's Boolean immutability parameter is a target-side policy, separate
   from the shared Haxe
   object-literal contract. The signature is explicitly `(fields, immutable:Bool)`
   and the implementation applies the platform immutability operation
   recursively to nested object literals at
   `packages/compiler/reflaxe/ts/tscompiler/TsExpr.hx:2320-2345`. The tree
   shows the policy being requested by TypeScript decode-fill code at
   `:1015-1017`, while ordinary expression dispatch passes `false` at
   `:1070-1071`. Therefore TypeScript may require immutability at those local
   boundaries, and its shorthand optimization is also local, but Dart,
   Kotlin, Swift, and Rust do not inherit an immutability obligation from this
   specification.

5. Rust's ownership conversions are permitted when they are value-semantics
   preserving. The current renderer clones or converts string values while
   constructing the struct at
   `packages/compiler/reflaxe/rust/rustcompiler/RustExpr.hx:5484-5501`.
   Such `clone` and `to_string` operations must not change any field value,
   field evaluation order, or source/declaration ordering rule. Ownership
   management is therefore target-local and observable only if it changes the
   Haxe value or ordering; a semantics-preserving conversion is conforming.

6. Future sharing should use a neutral plan such as
   `planObjectLiteral(type, fields, policy)`. The common decisions are
   named-record
   resolution, complete field validation, and the applicable ordering plan.
   Constructor syntax, anonymous-object syntax, TypeScript immutability and
   shorthand, and Rust ownership conversions remain target-local policies.
   This is a documentation reservation only; it does not require an
   implementation or make `policy` a cross-target immutability contract.

## Contract examples

| Source behavior | Required result |
| --- | --- |
| Anonymous literal `{first: a, second: b}` | Construct fields in `first`, then `second`, source order. |
| Named record fields supplied in a different source order | Validate by name and construct in the record declaration order. |
| A required record field is absent | Reject during compilation through `Context.error`. |
| An unknown record field is present | Reject during compilation through `Context.error`. |
| A TypeScript ordinary object literal | Do not infer a cross-target immutability requirement from it. |
| A TypeScript decode-fill literal with immutability enabled | Apply the target's immutable-object policy to the outer object and recursively apply it to nested object literals. |
| Rust string field ownership requires a clone or conversion | Permit it when the resulting value and field order are unchanged. |

## Non-goals

This specification does not standardize constructor spelling, JavaScript
property descriptors, a universal immutability model, local shorthand syntax,
Rust ownership strategy, or the generated named-record declarations. It does
not require anonymous records to have a runtime class identity, and it does
not require implementation of the future neutral planning signature.
