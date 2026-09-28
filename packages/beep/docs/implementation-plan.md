# Beep implementation plan

## 1. Purpose

This plan maps implementation work to topic specifications and pinned Wren source. Beep code is not included in this package yet. Product decisions are in 01-language.md, 03-objects-and-control.md, 04-errors-and-library.md, and 07-modules-embedding.md.

## 2. Dependency order

1. Implement the grammar in 01-language.md and 09-lexer-expression-grammar.md.
2. Implement associated equality grammar and solver fixtures in 02-types-and-inference.md.
3. Implement bytecode layout and opcode table in 10-opcode-reference.md, with VM integration in 05-vm-bytecode.md.
4. Implement the host ABI in 11-abi-data-layouts.md and 07-modules-embedding.md.
5. Implement source manager, scanner, parser and diagnostics.
6. Implement module graph and declaration collection.
7. Implement name/access resolution, type checker, generic solver, projection normalization and CFG analyses.
8. Build typed IR and deterministic bytecode encoder.
9. Build verifier and mutation suite before enabling bytecode load.
10. Implement synchronous interpreter, class model and closures.
11. Implement mark-sweep collector and typed handles.
12. Implement compile transaction, embedding API and foreign ABI.
13. Implement standard library and cross-target conformance suite.
14. Harden parser, solver, verifier, allocator and limits; publish release ABI/version.

## 3. Work packages

### Source and parser

Architecture and ownership rules: 12-compiler-architecture-and-references.md sections 3-5. Grammar: 01-language.md and 09-lexer-expression-grammar.md. Wren anchors: wren_compiler.c Parser, tokenizer, parsePrecedence, methodCall, endCompiler. Preserve Pratt expression structure and signature syntax. Tests cover token goldens, AST node/span goldens, every grammar production, malformed UTF-8, nested comments, interpolation, line endings, precedence, and bounded fuzzing. Gate: each production has positive and negative parser tests.

### Module graph and declarations

Wren anchors: WrenResolveModuleFn/WrenLoadModuleFn in include/wren.h; wrenCompileSource and import handlers in wren_vm.c; WrenVM module state. Preserve canonical host resolution and per-VM cache. Add transaction-local graph and declaration collection. Tests prove all reachable modules check before user effects, init order, and rollback. Gate: effect log is empty after every compile failure.

### Type checker and inference

Phase and symbol/type table specifications: 12-compiler-architecture-and-references.md sections 3, 5, and 6. Typing and solving rules: 02-types-and-inference.md. Wren anchors: local/module resolution and methodCall/signature parsing in wren_compiler.c; dynamic class lookup in wren_vm.h as the replaced baseline. Implement constraint structures, generation, solve phases, projection normalization, CFG assignment and diagnostics. Test order independence, principal solutions, variance, bounds, defaults, arity selection, projections and exhaustiveness. Gate: typed HIR has no unresolved non-quantified variable.

### Typed IR and bytecode

Wren anchors: ObjFn/FnDebug/CallFrame in wren_value.h; opcode definitions in wren_opcodes.h; disassembly in wren_debug.c. Specify each field/opcode stack layout. Typed IR retains source/type/method/substitution/witness identity. Gate: schema review before opcode values and loader exposure.

### Compiler and verifier

Preserve Wren stack lowering, receiver-first call windows and source mapping. Generate from checked typed IR. Verifier uses bounded decode and worklist type-state over operand stacks/initialized locals. Test valid and mutated-invalid module per invariant, fuzz bounds and atomic failure. Gate: bytecode loading remains disabled until mutation suite passes.

### Synchronous VM and classes

Wren anchors: runInterpreter/wrenInterpret/wrenCall; CallFrame/wrenCallFunction; class allocation functions. Replace ObjFiber ownership with ExecutionContext and normal nested frames. Preserve calls, classes, closures, super and member behavior. Exclude transfer/suspend state/opcodes. Test evaluation order, override, constructor, capture lifetime, panic frames and VM outcomes.

### Garbage collector

Wren anchors: wrenCollectGarbage/root marking; wrenGrayObj/object tracing; WrenVM first/gray/tempRoots/handles. Implement root inventory and per-object trace table in 06-memory.md. Trace Beep fields of foreign instances and treat host payload as opaque. Test forced collection at allocations, cycles, handles, closures, rollback, finalizers and allocator errors. Gate: output is invariant across collection thresholds.

### Embedding and foreign API

Wren anchors: WrenConfiguration, callbacks, slots, handles in include/wren.h; API functions in wren_vm.c. Define C ABI, ownership, outcomes, destruction, thread and re-entry rules. Split compile from execute. Test VM isolation, typed slots, callback errors, missing bindings, source lifetime, stale handles, re-entry, and ABI per target.

### Standard library and target parity

Implement 04-errors-and-library.md signatures, Unicode scalar strings, typed collections, checked arithmetic, Option/Result and host capability modules. Run shared source fixtures on every target. Compare structured values, error tags, output events and panic frames. Target libraries do not define unspecified behavior.

## 4. Wren source-to-test traceability

Before implementing preserved behavior, add a row to 08-wren-reference.md with pinned source link, symbol, Wren example/test, Beep expectation, Beep test path and deviations. Review rejects tasks that cite only a Wren file.

## 5. Release gates

1. Grammar and type decisions are complete.
2. Every type rule has positive and negative tests.
3. Whole-graph compile failure runs zero user code.
4. Verifier rejects each malformed encoding without state mutation.
5. Forced-GC suite covers every root category.
6. Embedding API has ownership and ABI tests on every target.
7. Shared cross-target tests agree on structured outcomes.
8. Bytecode version and target-independent encoding are documented. Cross-release compatibility is not promised.
