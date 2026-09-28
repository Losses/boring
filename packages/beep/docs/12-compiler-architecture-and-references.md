# Compiler architecture and implementation references

## 1. Purpose

This document defines subsystem boundaries and reference implementations. Use references as design inputs. Beep rules in documents 01 through 11 control whenever a reference differs.

## 2. Reference implementations by subsystem

| Beep subsystem | Primary reference | Use it for | Do not copy |
| --- | --- | --- | --- |
| Scanner and Pratt parser | Wren src/vm/wren_compiler.c | Token advancement, precedence parsing, signature parsing, local/upvalue lookup | Immediate bytecode emission during parse; dynamic dispatch assumptions |
| Syntax tree and lowering | rustc AST/HIR lowering | Separate syntax, resolved names, and typed representation; preserve spans while removing syntax-only forms | Rust ownership, macros, lifetime syntax, or language-specific HIR nodes |
| Constraint-based inference | Swift compiler constraint solver | Generate constraints per expression, solve alternatives, retain diagnostic origins | Swift overload selection; Beep forbids same-name/same-arity overloads by argument types |
| Generic bounds and associated types | rustc inference and trait selection | Separate type variables from trait obligations; normalize projections through selected conformance | Lifetime inference, borrow checking, or rules outside Beep coherence |
| Definite assignment | Kotlin data-flow analysis or rustc MIR dataflow | CFG facts, joins, loop fixed points, unreachable paths | Kotlin smart-cast invalidation or Rust move/borrow semantics |
| Typed IR and verification | WebAssembly validation plus Wren stack bytecode | Validate before execution; explicit stack typing and bounded decoding | WebAssembly control syntax, binary format, or numeric semantics |
| Mark-sweep GC | Wren wren_vm.c and wren_value.c | Root marking, gray worklist, tracing, sweeping, temporary roots | Fiber roots/error transfer, dynamic Value tags, host payload scanning |
| Embedding boundary | Wren src/include/wren.h | Opaque VM, callbacks, allocator, handles, foreign registration | Untyped slots or executing source during import |

Reference entry points: [rustc-dev-guide compiler overview](https://rustc-dev-guide.rust-lang.org/overview.html), [rustc-dev-guide type inference](https://rustc-dev-guide.rust-lang.org/type-inference.html), [Swift compiler repository](https://github.com/swiftlang/swift), [WebAssembly core validation](https://webassembly.github.io/spec/core/valid/instructions.html), and pinned Wren links in 08-wren-reference.md. These identify projects and areas to inspect. Before adopting implementation details, record exact source revisions, symbol links, and tests in the implementation record.

## 3. Compiler phase requirements

The compiler owns immutable SourceFile records through one compile transaction. Syntax and semantic nodes store SourceSpan (module id, start byte, end byte). Diagnostics refer to spans, never AST pointers.

Pipeline:

1. Source manager validates UTF-8, assigns canonical module ids, and builds line-start tables.
2. Lexer produces Token arrays. Tokens own decoded literal payloads and refer to source bytes by span.
3. Parser produces arena-owned AST. AST represents syntax and contains unresolved Identifier nodes. Symbol and type data are held in later compiler phases.
4. Module declaration collector assigns symbol identities and forward declaration tables across the reachable module graph.
5. Resolver replaces identifier references with SymbolId references and validates access/import visibility. It does not infer types.
6. Type checker consumes resolved AST and declarations, produces typed HIR, and emits diagnostics. Typed HIR has TypeId on every expression and resolved MethodId/ConformanceId on every call and conformance use.
7. Lowering converts typed HIR to control-flow IR. It removes pattern syntax, lowers loops and short-circuit expressions, and records conversions and effects.
8. Bytecode generator maps typed IR to the instruction set in 10-opcode-reference.md.
9. Verifier validates generated or external bytecode before installation.

Each phase accepts immutable input and returns output plus diagnostics. A failed phase blocks phases that require its invariants. User code cannot run during compilation. Typed HIR is target-independent.

## 4. AST ownership and node model

Use a bump arena per module for AST nodes and a separate arena for decoded token payloads. The compile transaction owns both. On success, parser arenas are freed after typed HIR construction; on failure, all transaction arenas are freed. AST references use NodeId indices. SourceSpan is stored inline.

Required node families:

- ModuleNode: module id, imports, declarations.
- DeclarationNode: function, class, interface, enum, record, alias, constant, field, initializer, foreign declaration.
- TypeSyntaxNode: name, application, function, tuple, record, Self, Never, associated projection, where constraint.
- StatementNode: local declaration, expression, return, if, while, for, break, continue, match.
- ExpressionNode: literal, name, this/super, tuple, array/map, function literal, unary/binary, assignment, conditional, call, member, subscript, interpolation, match, if, block.
- PatternNode: wildcard, binding, literal, tuple, record, enum case, Option/Result case, class test, guarded arm.
- MemberSignatureNode: dispatch kind, spelling, labels, arity, parameter syntax, result syntax.

AST invariants: child ids belong to the same transaction; lists preserve source order; parentheses remain only when needed to distinguish tuple/group; AST nodes contain no TypeId, SymbolId, MethodId, or runtime object. Semantic facts live in typed HIR or side tables keyed by NodeId.

Parser recovery creates ErrorNode with span and expected-token set. Resolver and type checker skip subtrees containing ErrorNode. Code generation rejects any ErrorNode as an internal phase violation.

## 5. Symbol and type tables

SymbolId is a monotonically assigned index local to the compile transaction. Symbol records include module id, declaration NodeId, spelling, visibility, kind, generic parameter ids, and span. Lookup order: locals/parameters, enclosing function captures, receiver members under Wren implicit self-send rules, then module imports/declarations. Ambiguous imported names are compile errors with both declaration spans.

TypeId is an interned index into immutable descriptors. Tuple/record/function types use structural keys. Class/interface/enum types use nominal (module id, declaration id, substituted arguments) keys. Projection descriptors include ConformanceId and associated type id after normalization. TypeId zero is invalid; a missing descriptor is an internal compiler error.

Name resolution is a distinct pass. It builds lexical scopes and capture lists, but does not choose members from argument types. Member resolution filters receiver type, visibility, static/instance kind, name, labels, and arity. Duplicate signatures fail during declaration collection.

## 6. Type checker algorithm

The checker operates per strongly connected module component after all declarations are collected. It checks signatures and conformance headers before function bodies. A function context contains module, receiver type, expected return type, generic parameters, lexical bindings, definite-assignment state, and constraints.

For each expression, checkExpr(node, expectedType?) returns a typed node and constraints. It follows node-specific generation rules in 02-types-and-inference.md. Constraints retain origin NodeId and reason code. The solver runs to a fixed point for each callable body, then checks typed nodes against the final substitution. Calls bind only to a unique name/label/arity signature. Generic parameters instantiate as fresh inference variables. Source order never selects among type solutions.

Typed HIR is emitted only when body constraints, projections, conformance obligations, and definite-assignment facts resolve. Lowering then has one TypeId per expression, one MethodId/substitution per call, one field offset per field access, and one witness id per conformance use.

Error recovery uses poisoned ErrorType to suppress derivative diagnostics. ErrorType cannot enter typed HIR or bytecode. The compiler caps diagnostics per module and constraints per function; limit exhaustion returns ResourceLimit without executing code.

## 7. Definite assignment and CFG

Build a CFG after name resolution for each function. Basic blocks end in branch, conditional branch, return, panic, break, continue, or fallthrough. Edges name their source construct. Forward dataflow tracks definitely initialized locals/fields as bitsets. Entry initializes parameters and receiver. Declaration transfer sets its local after initializer success. Join intersects initialized sets. Loop analysis iterates to a fixed point. Reads outside the initialized set are diagnostics.

A separate reachability pass marks dead blocks. Return coverage checks reachable exits against declared result. Match coverage uses closed constructor sets and subtracts unguarded patterns or literal-true guarded patterns. Missing cases are reported in declaration order.

## 8. Lowering invariants

Typed HIR lowering preserves left-to-right evaluation by introducing temporaries for receiver, arguments, assignment target, and interpolation segments. &&, ||, conditional expressions, Result propagation, and match lower to explicit branches. Pattern bindings are written only after successful tests. For loops acquire one iterator and repeatedly call next.

Each IR value has TypeId and definition block. Each call has MethodId, signature id, witness if needed, and generic substitution. Each allocation has safepoint id and precise live-root set. Bytecode verification remains mandatory; generator correctness does not replace validation.

## 9. Reference use procedure

For each subsystem:

1. Read the public API and tests first.
2. Trace one implementation path from input through data structures to result.
3. Record source revision, file, symbol, invariants, and tests in 08-wren-reference.md or a subsystem reference section.
4. Write a Beep comparison fixture before adapting the design.
5. List adopted mechanism and each deliberate difference.
6. Keep mechanisms whose invariants fit Beep. Derive behavior from Beep rules where types, errors, GC roots, modules, or ABI differ.

A reference implementation does not prove that its behavior fits Beep. Every borrowed algorithm needs a Beep invariant, a negative case for incompatible reference behavior, and a target-independent test.

## 10. Reference-driven tests

- AST goldens assert node kind, child order, and exact spans for every production.
- Phase tests assert unresolved names never reach type checking and ErrorNode never reaches typed HIR.
- Typed HIR snapshots assert TypeId, MethodId, conformance id, conversions, and capture list.
- Constraint tests assert source-origin diagnostics and insertion-order independence.
- CFG snapshots assert edges, initialized sets, and match coverage.
- Lowering tests assert side-effect order and root maps at allocation safepoints.
- Wren comparison tests pair each adopted mechanism with one Beep fixture and one test for the intentional difference.
