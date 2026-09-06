# Feature spec 56: Std.isOfType runtime type contract

## Scope

This specification rules the runtime type-test contract for Haxe
`Std.isOfType(value, T)` across Dart, TypeScript, Rust, Kotlin, and Swift. It
covers subclass instances, interface checks, runtime identity boundaries,
compile-time folding, and invalid target diagnostics. It does not prescribe a
single target runtime representation or define type metadata that a target
does not otherwise provide.

## Current verification

| Target or mechanism | Current verification anchor | Current form |
| --- | --- | --- |
| Shared validation and folding | `packages/compiler/TypeCheckHelper.hx:26-42` | `classOfTypeExpr` validates the target, `knownIsOfType` folds statically decidable results, and `isSubtype` follows class and interface relations. |
| Dart | `packages/compiler/reflaxe/dart/dartcompiler/DartExpr.hx:1744-1752` | Validates a class target, applies the shared known-result prefix, and emits the Dart `is` test. |
| TypeScript | `packages/compiler/reflaxe/ts/tscompiler/TsExpr.hx:1538-1553` | Applies the shared prefix, rejects a non-folded interface check, and otherwise emits `instanceof`. |
| Rust | `packages/compiler/reflaxe/rust/rustcompiler/RustExpr.hx:4046-4057` | Applies the shared prefix and otherwise compares `__haxe_type_name()` with the target name. |
| Kotlin | `packages/compiler/reflaxe/kotlin/kotlincompiler/KotlinExpr.hx:2314-2322` | Applies the shared prefix and emits Kotlin `is`. |
| Swift | `packages/compiler/reflaxe/swift/swiftcompiler/SwiftExpr.hx:1807-1815` | Applies the shared prefix and emits Swift `is`. |

## Semantics ruling

1. The Haxe baseline is a runtime instance test: `Std.isOfType(v, T)` is true
   when the runtime value is an instance of `T`, including an instance of a
   subclass of `T`. It is false for a value that is not an instance of `T`.
   The shared subtype analysis already recognizes class and interface
   relations for statically known values at
   `packages/compiler/TypeCheckHelper.hx:26-42`. Every target lowering is
   required to preserve this observable baseline for values that reach its
   runtime test.

2. Dart, Kotlin, and Swift currently use native runtime type-test forms after
   the common validation and folding prefix. These forms are capability facts,
   not a request for identical generated text: Dart emits `is` at
   `packages/compiler/reflaxe/dart/dartcompiler/DartExpr.hx:1750-1751`, while
   Kotlin and Swift emit `is` at
   `packages/compiler/reflaxe/kotlin/kotlincompiler/KotlinExpr.hx:2320-2321`
   and `packages/compiler/reflaxe/swift/swiftcompiler/SwiftExpr.hx:1813-1814`.
   They are conforming only where their target runtime test includes the Haxe
   subclass behavior.

3. TypeScript has the target capability to test class instances with
   `instanceof`, as shown by the ordinary runtime path at
   `packages/compiler/reflaxe/ts/tscompiler/TsExpr.hx:1552`. Its current
   interface branch instead calls `Context.error` with the message
   `Std.isOfType interface checks require a statically typed implementor on the
   TypeScript target` at `:1548-1551`. This is a subset rejection, with no cross-target semantic ruling: a non-folded
   interface check is rejected at
   compile time, and it must not silently become a structural or always-false
   runtime test. The long-term contract should support an interface check when
   the generated runtime representation can prove Haxe interface membership;
   this specification does not prescribe that implementation.

4. Rust's current fallback compares the value's
   `__haxe_type_name()` with one exact module and type name at
   `packages/compiler/reflaxe/rust/rustcompiler/RustExpr.hx:4052-4056`.
   Exact name equality can represent the exact runtime class only if the
   metadata method returns that class's identity. It does not, by itself,
   cover a subclass instance tested against its base class, because the two
   names differ. It also does not establish type aliases as equivalent unless
   they are normalized to one runtime identity, and it does not establish
   interface membership because an interface is not necessarily the concrete
   value's type name. Therefore Rust's current fallback is a subset lowering:
   unsupported subclass, alias, or interface cases must be rejected or folded
   only when their required relation is proven; they must not be declared
   conforming solely because the names are equal. A future Rust runtime test
   should be judged by the ruling 1 baseline and the spelling of the
   metadata call.

5. `TypeCheckHelper.knownIsOfType` is shared behavior. When it returns a known
   result, each target may emit `true` or `false` without a runtime test; when
   the target expression is not a valid class type expression, each target
   reports the shared invalid-type condition through `Context.error` and does
   not invent a runtime fallback. The shared decision and its subtype walk are
   anchored at `packages/compiler/TypeCheckHelper.hx:26-42`, with the target
   prefix visible, for example, at Dart `:1745-1750` and TypeScript
   `:1539-1546`.

6. Future sharing must separate the common prefix from runtime rendering. A
   neutral decision boundary may be described as
   `planIsOfType(value, target)`, returning validation status and an optional
   known result. That shared plan owns target validation and compile-time
   folding. The runtime decision shape remains target-local: native `is`,
   `instanceof`, runtime metadata, or a target-specific rejection may be
   selected only after the target capability and Haxe-equivalence rules are
   applied. No implementation change is required by this reserved shape.

## Contract examples

| Source behavior | Required result |
| --- | --- |
| A value is an instance of `Base` | `Std.isOfType(value, Base)` is true. |
| A value is an instance of `Child extends Base` | Testing `Base` is true. |
| A value is an instance of an unrelated class | Testing `Base` is false. |
| A statically known subtype relation is decidable | Emit the shared known `true` or `false` result. |
| The target expression is not a class type expression | Reject through the target's compile-time `Context.error` path. |
| Rust metadata names are equal | The exact-class test may be true; equality alone does not prove base-class or interface membership. |
| TypeScript cannot represent a required interface membership test | Reject the subset input; do not emit a false or structural approximation. |

## Non-goals

This specification does not require identical target syntax, prescribe a
particular class metadata layout, define JavaScript structural typing, or add
interface metadata to Rust. It does not remove the shared known-result fold,
change Haxe subtype relations, or require an implementation of the future
planning boundary.
