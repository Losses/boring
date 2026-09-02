# Feature spec 38: Deferred variable declarations

Status: Planned.

## Scope

This specification rules local variable declarations without an initializer,
`var x:T;`, together with the assignments that initialize them later in the
function body. The Kotlin engine sources initialize locals through
expression statements (`val x = when { ... }`); splitting such a statement
into a bare declaration plus branch assignments currently crashes the
Kotlin target: `src/reflaxe/kotlin/kotlincompiler/KotlinExpr.hx` evaluates
`isTryRegion(init)` at line 327 and `isStringBufToStringCall(init)` at line
333 inside statement guards that run before the `init != null` guard at
line 335, so a null initializer dereferences null. The engine port worked
around the crash by hoisting named early-return functions
(`engine-haxe/.../ContextualDashEllipsisRoleResolver.hx:57`). This
specification sanctions the statement form and rules the guards.

## Haxe construct

```haxe
static function tierOf(value:Int):Int {
	var tier:Int;
	if (value > 2) {
		tier = 2;
	} else {
		tier = value;
	}
	return tier;
}
```

The type annotation is required, per the explicit-types convention of the
translatable subset. A read of the declared name must be preceded by an
assignment on every path; this specification assigns that check to each
target compiler's own definite-assignment analysis (rule 3), because the
subset performs no dominance analysis of its own.

## Ruling

1. A local `var x:T;` with no initializer is sanctioned at function-body
   statement level. Declarations of fields without initializers stay
   outside this specification: static fields follow features/30, instance
   fields follow features/27.
2. The declaration lowers to each target's deferred-declaration form, and
   the later assignments render as plain assignments to the declared name:
   - Kotlin: `var x: T` — kotlinc definite-assignment analysis rejects a
     use before assignment. The declaration emits `var` in every case,
     because the later assignment marks the binding mutated.
   - TypeScript: `let x: T;` — strict mode rejects a use before assignment.
   - Swift: `var x: T` — definite initialization enforced by swiftc.
   - Dart: `T x;` — flow analysis enforced by the analyzer.
   - Rust: `let mut x: T;` — deferred initialization enforced by rustc.
   - Haxe stage 1: the plain Haxe statement; sanctioned bodies assign
     before every read, so the stage-1 compiler observes no uninitialized
     read.
3. Every statement-lowering guard that inspects the shape of a `TVar`
   initializer must test `init != null` before the inspection. The
   `KotlinExpr.hx` `isTryRegion`/`isStringBufToStringCall` guards are the
   known instance; the equivalent statement guards of the TypeScript,
   Swift, Dart, and Rust expression lowerers are audited in the same
   change, and any guard with the same shape gains the same null check.
4. The construct adds no rejection row: it moves from a crash to a
   sanctioned form. A read not dominated by an assignment surfaces as the
   target compiler's own error during the tree build of the verification
   run; the mutation hook pins this for Kotlin.

## Test hooks

- A sample function holds one bare `Int` declaration assigned in both
  branches of an `if`/`else`, one bare nullable declaration assigned
  inside a null-guard branch, and one bare declaration assigned inside a
  loop before the read; each returns the assigned value.
- Tree assertions: each target tree carries the deferred-declaration form
  of rule 2 (`var x: Int`, `let x: number`, `var x: Int`, `int x;`,
  `let mut x: i32`).
- Mutation: deleting one assignment branch fails the Kotlin tree build
  with the definite-assignment error of the Kotlin compiler.
