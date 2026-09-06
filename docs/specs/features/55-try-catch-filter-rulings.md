# Feature spec 55: Try/catch filter rulings

## Scope

This specification rules the runtime type filter and propagation behavior of
Haxe `try`/`catch` in the supported subset. It covers typed catch matching,
handler binding visibility, the conforming target shapes, and Rust's fallible
region equivalent. It does not unify target exception syntax or define a new
exception runtime.

## Current verification

| Target or mechanism | Current verification anchor | Current form |
| --- | --- | --- |
| Haxe catch baseline | The typed catch is represented by the catch variable and its declared type, consumed by target `exceptionClassOf` helpers at Dart `packages/compiler/reflaxe/dart/dartcompiler/DartExpr.hx:2758-2797`, TypeScript `packages/compiler/reflaxe/ts/tscompiler/TsExpr.hx:2375-2413`, and Swift `packages/compiler/reflaxe/swift/swiftcompiler/SwiftExpr.hx:2882-2974` | Each target resolves the catch class before rendering its target-specific filter. |
| Dart | `packages/compiler/reflaxe/dart/dartcompiler/DartExpr.hx:2806-2821` | Emits `try` and an `on Class catch (x)` handler, directly filtering by the class. |
| Swift | `packages/compiler/reflaxe/swift/swiftcompiler/SwiftExpr.hx:2983-3001` | Emits `do`, `catch let x as Class`, and a bare catch that rethrows the unmatched error. |
| TypeScript | `packages/compiler/reflaxe/ts/tscompiler/TsExpr.hx:2424-2441` | Emits an untyped `catch (x)`, applies `instanceof` in the handler, and rethrows on mismatch. |
| Kotlin | `packages/compiler/reflaxe/kotlin/kotlincompiler/KotlinExpr.hx:1368-1387` | Emits typed `catch (x: Class)` through the expression-shaped `try` renderer. |
| Rust | `packages/compiler/reflaxe/rust/rustcompiler/RustExpr.hx:2640-2698` | Has no same-named statement renderer; a fallible region and `Result` carry the body, handler, and error path. |
| Catch binding state | Dart `:2815-2817`, TypeScript `:2434-2436`, Swift `:2992-2994`, and Kotlin `:1376-1378` | Target renderers register the catch variable while rendering the handler and remove it afterward. |
| Swift value-arm modifier | `packages/compiler/reflaxe/swift/swiftcompiler/SwiftExpr.hx:3024-3037` | `containsThrowingCall` controls `try` on value-producing arms; this is an expression-shape concern around the same filter contract. |

## Semantics ruling

1. The Haxe baseline is runtime type filtering: `catch (e:T)` catches only
   an exception whose runtime value is an instance of `T`, including an
   instance of a subclass of `T`. If the thrown value is not an instance of
   `T`, this catch does not handle it and propagation continues. Target class
   resolution for this operation is anchored at Dart `:2758-2797`, TypeScript
   `:2375-2413`, and Swift `:2882-2974`.

2. Dart's `on Class catch (x)` is conforming when the target runtime performs
   the required subclass-aware filter directly. Swift's `catch let x as
   Class` followed by a bare `catch { throw error }` is conforming because the
   cast selects matching values and the final catch preserves mismatch
   propagation. These forms are evidenced at Swift `:2983-3001` and Dart
   `:2806-2821`.

3. TypeScript's untyped `catch (x)` is conforming when its handler tests
   `x instanceof Class`, executes the Haxe handler only for a match, and
   rethrows the original value otherwise. The filter and rethrow shape is at
   `packages/compiler/reflaxe/ts/tscompiler/TsExpr.hx:2424-2463`.
   Kotlin's typed `catch (x: Class)` is conforming when the generated target
   catch mechanism supplies the same runtime type filtering and propagation
   behavior; its current shape is at
   `packages/compiler/reflaxe/kotlin/kotlincompiler/KotlinExpr.hx:1368-1387`.
   The common requirement is observable equivalence of filtering and
   propagation. The three native forms need not have identical text.

4. The catch binding has the source Haxe name and declared type for the whole
   handler body. References to that binding must resolve to the caught value
   with the source-visible type. Maps such as `catchVars`, including the
   registration shown at Dart `:2815-2817`, TypeScript `:2434-2436`, Swift
   `:2992-2994`, and Kotlin `:1376-1378`, are implementation details and are
   not part of the cross-target contract.

5. Rust may represent the same operation without a native try/catch
   statement. A fallible region must carry successful values as `Ok` and
   failures as `Err`, and its handler or propagation path must produce the
   same oracle output item by item as the Haxe behavior. The relevant region
   lowering is at `packages/compiler/reflaxe/rust/rustcompiler/RustExpr.hx:2640-2698`.
   No new exception mechanism is implied. If the target configuration cannot
   carry the required filter and propagation behavior, the subset must reject
   the input. A weaker lowering is not conforming.

6. In Swift value-producing try regions, `containsThrowingCall` may add the
   target `try` modifier to a value arm. This modifier preserves the enclosing
   expression lowering and does not change the typed-catch filter or mismatch
   propagation ruling. The current value-arm handling is at
   `packages/compiler/reflaxe/swift/swiftcompiler/SwiftExpr.hx:3024-3037`.

## Contract examples

| Source behavior | Required result |
| --- | --- |
| Throw an instance of `Child`, catch `Base` | Run the handler and expose the child through the source catch binding. |
| Throw an instance of `Other`, catch `Base` | Do not run the handler; propagate the original exception. |
| Handler references `e` with source type `Base` | The name and source-visible type are available throughout the handler. |
| Rust fallible region returns success | Carry the region value through `Ok` and preserve the oracle output. |
| Rust fallible region receives a nonmatching failure | Preserve it through `Err` and the surrounding propagation path. |
| A target cannot model filtering and propagation | Reject the subset input; a weaker invented behavior is not conforming. |

## Non-goals

This specification does not prescribe catch-header spelling, exception class
layout, variable-map names, Swift `try` placement beyond its relationship to
this contract, or a native exception mechanism for Rust. It does not broaden
the number of catches, change Haxe subclass relations, or require identical
source and generated control-flow shapes.
