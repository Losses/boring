# Modules and embedding API

## 1. Wren host API reference

Wren declares WrenConfiguration, module resolver/loader, foreign bindings, slots and WrenHandle in pinned [wren.h](https://github.com/wren-lang/wren/blob/99d2f0b8fc2686134b32b18166e037639f7e9f2c/src/include/wren.h). wrenInterpret, wrenCompileSource, wrenCall and slot operations are implemented in [wren_vm.c](https://github.com/wren-lang/wren/blob/99d2f0b8fc2686134b32b18166e037639f7e9f2c/src/vm/wren_vm.c). Beep retains opaque per-VM configuration/callbacks and separates compile from execute.

## 2. Module graph

A source file defines one module. Resolver maps import path and importer identity to canonical name. Canonical names are per-VM cache keys. Loader returns immutable bytes and a release callback; compiler copies bytes when no retention callback is supplied. Names use forward slashes; canonicalization removes dot components and rejects traversal above configured root.

Compiler resolves full reachable graph before checking bodies. It loads each canonical module once per transaction. Declaration collection spans the graph so signatures can refer across cycles. Cycles with ambiguous initialization order are compile errors. Imports execute no statements.

A module may declare one init: () -> Result<Unit,E>. Initializers run once after graph verification in deterministic topological order. Ties between independent modules use canonical module name byte order. Any cyclic component containing an initializer is rejected. Entry runs after all init results are Ok. An Err stops later initializers and returns RuntimeError(error); completed initializer side effects remain. This boundary is observable and tested.

## 3. Compile transaction state machine

States: Created, Resolving, Parsed, Declared, Checked, Lowered, Verified, Installed, Failed, Released. Transitions move forward. Failed transactions release their owned source/AST/IR/bytecode and do not change installed modules. Installed transactions transfer module ownership to VM.

Phases: resolve graph; scan/parse; collect declarations; resolve names/imports; type-check bodies and constraints; lower typed IR; serialize; verify all modules; atomically install. User initializer/foreign methods do not run during these phases. Resolver/loader callbacks supply source only and cannot execute Beep code.

## 4. Native API

Required operations:

- create(config) -> VM handle or configuration error.
- compile(vm, rootName, source) -> CompiledUnit or DiagnosticSet.
- loadBytecode(vm, bytes) -> CompiledUnit or InvalidBytecode.
- execute(vm, unit, entry, typedArgs) -> Outcome.
- lookupExport(vm, module, name) -> typed handle or lookup error.
- call(vm, functionHandle, typedArgs) -> Outcome.
- createHandle/releaseHandle, collect(vm), destroy(vm).

Outcome variants: Success(value), CompileError(diagnostics), RuntimeError(error), Panic(record), ResourceLimit(record), InvalidBytecode(record), VMFault(record). Beep Result Err remains a normal returned Beep value.

Configuration includes allocator, resolver/loader, foreign functions/classes, output/diagnostic callbacks, user data, heap growth and limits for source, graph, stack, frames, instructions, bytecode and heap. Defaults grant no file/network/process/clock/random capability.

Compilation copies source by default. Handles are opaque VM-specific GC roots. Slots carry Beep descriptors. Validate argument count/types before VM entry and results before host exposure. Host callback errors map to declared Error constructors. Host exceptions are translated by adapters before ABI return.

## 5. Threading and re-entry

One VM is entered by one host thread at a time. Independent VMs may execute concurrently when callbacks/allocators are thread-safe. Same-VM re-entry, destruction during a callback, or execute during compile returns HostApiError. VM creates no threads and has no scheduler.

## 6. Foreign classes

Foreign instance layout contains class id, Beep field vector and opaque host payload. Beep fields use verified offsets/types and are traced by GC. Payload bytes are never scanned. Foreign methods receive validated typed slots and designated payload access. Finalizer receives payload/user data only and cannot re-enter VM.

## 7. Diagnostics and ownership

Diagnostics contain stable code, severity, canonical module, byte range, line/column, message key/arguments and related ranges. Message wording may change across releases. ABI appendix defines destroy operation or VM-owned lifetime for each diagnostic set.

CompiledUnit is VM-specific and roots module metadata until install/release. A unit cannot cross VMs except through bytecode load, which verifies and installs a copy. Source, callback results, handles, diagnostics, outcomes and user data each have explicit owner and release operation in ABI appendix.

## 8. Required tests

- Type error in any dependency causes zero user initializer/output/foreign calls.
- Resolver order and one load per canonical module are deterministic.
- Failed compile preserves old module table.
- Independent initialization ties use canonical-name byte order.
- Cycle containing initializer fails before execution.
- Initializer Err stops later initializers and returns typed error.
- Wrong slot type/arity is rejected before VM entry.
- Missing foreign binding prevents installation.
- Foreign class Beep fields survive GC and host payload stays opaque.
- Handle lifetime, VM isolation, thread entry and re-entry rules are checked.
