# Virtual machine and bytecode

## 1. Wren execution baseline

Wren VM state is in [wren_vm.h](https://github.com/wren-lang/wren/blob/99d2f0b8fc2686134b32b18166e037639f7e9f2c/src/vm/wren_vm.h). Dispatch and public wrenInterpret/wrenCall paths are in [wren_vm.c](https://github.com/wren-lang/wren/blob/99d2f0b8fc2686134b32b18166e037639f7e9f2c/src/vm/wren_vm.c). Opcode names and stack effects are in [wren_opcodes.h](https://github.com/wren-lang/wren/blob/99d2f0b8fc2686134b32b18166e037639f7e9f2c/src/vm/wren_opcodes.h). Wren uses stack bytecode and receiver-first call windows. Beep preserves this structure and replaces active Fiber with synchronous ExecutionContext.

## 2. VM state and frames

Each VM owns core types, modules, class/method tables, symbols, heap/GC, compile transaction, execution context, source maps, host bindings, configuration, and handles. Distinct VMs share no Beep values. One VM is entered by one host thread at a time.

ExecutionContext fields: operand stack, frame vector, current module, instruction count, root invocation id, exit outcome. It has no suspended state. CallFrame fields: function/closure id, instruction pointer, base slot, module id, source map id. A call pushes a frame; return pops it. Host entry returns only on completion or a structured outcome.

## 3. Value and instance layout

Primitive values may be immediate: Bool, Byte, Int, Float, Unit. Heap objects include String, Array, Map, class metadata, instance, closure, upvalue cell, enum payload, type descriptor, module, and foreign instance. Logical object header: kind, runtime type id, GC mark state, allocation size, next-object link.

Instance layout is class id, inherited fields, local fields in declaration order, and optional opaque host payload. Verifier checks field offsets/types. Collector traces Beep fields from class metadata and excludes host payload bytes. Option/Result have explicit tag and typed payload. Invalid tag/type combinations are VMFault. No source null/undefined exists.

## 4. Dispatch and opcode behavior

Compiler emits resolved method symbol and signature id. Virtual calls use verified class method table. Static/final/private calls may use direct slots. super starts at direct base. One name/arity has one signature, following Wren.

Each opcode specification must state byte encoding, stack inputs/outputs, local effects, branches, outcomes, and whether allocation may trigger GC. Families: constants; locals/captures; module access; fields; collections; arithmetic/comparison; branches; direct/virtual/super calls; closure creation; class metadata; enum construction/tests; pattern tests; return; panic.

Verifier propagates operand types and initialized-local state through function CFG. Branch targets begin instructions. Joins require equal stack height and compatible types. Calls match signatures. Field operations match layout. Closure captures match descriptors. Return matches function result. Panic terminates path. GC safepoints have live references on stack/maps or temporary roots.

## 5. Bytecode file requirements

The file format and every instruction are defined in 10-opcode-reference.md. This document defines VM integration, metadata ownership, and verifier behavior; 10-opcode-reference.md defines magic, version, sections, fixed widths, byte order, strings, constants, type descriptors, function/class/module records, source maps, branch offsets, and canonical serialization. No pointer, native layout, or machine code is serialized. Integers use fixed widths; Float uses IEEE 754 binary64 bits. Unknown feature bits and versions are rejected before large allocation.

Function records contain signature, generic bounds, local types, captures, max stack, code range, and source-map range. Class records contain base id, field descriptors, methods, override targets, and interface witnesses. Module records contain canonical name, import ids, exports, initializer, and constants.

Encoding is canonical for one Beep release and source/module graph, excluding declared non-semantic build metadata. Targets load identical bytes and produce equal structured outcomes. Cross-release loading is not promised.

## 6. Verifier algorithm

1. Check magic/version/features and file size against config.
2. Decode section offsets with checked arithmetic; reject overlap, overflow, truncation, and invalid trailing data.
3. Validate UTF-8 names, constant tags, ids, and cross-section references.
4. Validate nominal graph, layouts, method uniqueness, overrides, witnesses, and generic projections.
5. Decode each function and mark instruction boundaries.
6. Run worklist dataflow from entry with state (initialized locals, operand type stack). Reject underflow, invalid locals, uninitialized reads, wrong types, incompatible joins, and invalid targets.
7. Validate return/panic terminal state and max stack.
8. Validate source maps and configured limits.
9. Install only after every module passes.

Invalid bytecode returns InvalidBytecode(section, offset). It invokes no callback or user code and changes no VM state. Decoder allocation and work are bounded by input size and config.

## 7. Outcomes and limits

Outcomes: Success(value), RuntimeError(error), Panic(record), CompileError(diagnostics), ResourceLimit(record), InvalidBytecode(record), VMFault(record). Beep Result Err remains an ordinary returned value. Configurable limits cover source, modules, bytecode, heap, stack, frames and instruction count. Instruction budget increments once per dispatched opcode. Host callbacks have separate host budgets.

## 8. Wren deviations and tests

Wren opcodes include NULL, module execution transfer, and Fiber state transitions. Beep has no source NULL or Fiber transfer. Imports run in compile transaction before execution. Wren runtimeError searches Fiber handlers; Beep Err returns normally and panic exits root invocation.

Tests: stack effect for each opcode; mutation for each verifier rule; branch-into-operand rejection; invalid witness rejection; failed load atomicity; deterministic serialization; cross-target outcome parity; stack and instruction limit results; panic frame order.
