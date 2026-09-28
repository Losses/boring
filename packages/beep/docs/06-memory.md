# Memory management

## 1. Wren collector reference

Wren uses non-moving mark-sweep. Allocation threshold, collection, root traversal, gray processing and sweeping are in [wren_vm.c](https://github.com/wren-lang/wren/blob/99d2f0b8fc2686134b32b18166e037639f7e9f2c/src/vm/wren_vm.c). Object tracing/allocation are in [wren_value.c](https://github.com/wren-lang/wren/blob/99d2f0b8fc2686134b32b18166e037639f7e9f2c/src/vm/wren_value.c). Root fields, temporary roots, handles, object list and gray stack are in [wren_vm.h](https://github.com/wren-lang/wren/blob/99d2f0b8fc2686134b32b18166e037639f7e9f2c/src/vm/wren_vm.h). Beep retains this algorithm and adds transaction/execution roots.

## 2. Object lifecycle

Every heap object uses the configured allocator and joins the VM object list before exposure. The logical header stores kind, mark bit, byte size and next link. Allocation initializes every traceable field to a valid internal empty state before another allocation may trigger collection.

Collection runs when allocation since the last completed collection reaches nextGC, or on an explicit idle-VM request. It resets marks, marks roots, drains gray stack, sweeps unmarked objects, updates live bytes, and computes the next threshold from configured minimum and growth percentage. Heap accounting overflow returns ResourceLimit.

## 3. Root inventory

The collector marks:

1. Core classes and permanent type descriptors.
2. Installed modules, globals, and constants.
3. Class/method tables, witnesses, and symbol strings.
4. Active operand slots and frame closure/function/module references.
5. Open upvalues and captured cells.
6. Compile transaction AST, type metadata, and constants under construction.
7. Temporary root stack entries.
8. Every unreleased host handle.
9. Host callback arguments/results while callback is active.
10. Panic/error report values until copied to host-owned records.

Every root-bearing field has one trace function and a forced-GC test. A live object in a native local is pushed as a temporary root before an allocation that can collect. Temporary roots are LIFO; only the top may be popped. Overflow produces checked ResourceLimit.

## 4. Per-object tracing

- String: no Beep references.
- Array: every initialized element according to T representation.
- Map: every live key and value.
- Class: superclass, method closures, witnesses, field type descriptors.
- Instance: class and initialized Beep fields.
- Closure: function metadata and captured upvalue cells.
- Upvalue: open slot is traced by active stack; closed cell traces stored value.
- Enum: case descriptor and payload.
- Module: imports, exports, globals, constants and initializer.
- Foreign instance: class and Beep fields; host payload is opaque and unscanned.
- Type descriptor: argument descriptors and nominal declaration metadata.

## 5. Handles and foreign objects

A handle stores VM identity, generation/liveness and Value. Creation links it as a root. Release unlinks once. Cross-VM use, double release and use after VM destruction return HostApiError. Public API exposes no managed object pointer.

Foreign payload allocation/release belongs to host binding. A finalizer runs at most once when swept or when VM is destroyed. It receives opaque payload/user data, cannot re-enter VM, and has unspecified order/timing. Beep fields are traced before payload finalization.

## 6. Allocation failure

Allocator matches the Wren allocate/grow/shrink behavior. Byte counters use checked arithmetic. If allocation fails, VM performs one collection and retries once. A second failure yields ResourceLimit. If internal consistency cannot continue, mark VM Failed; future calls return VMFault while destroy remains valid. Compilation installs atomically and releases pending transaction roots on failure. Runtime mutations completed before a failed allocation remain completed.

## 7. Tests

Force collection before and after every allocation. Test self/multi-object cycles; roots through globals, frames, closures, upvalues, witnesses, handles and callbacks; transaction rollback; foreign payload opacity and one finalizer; output parity at different thresholds; injected allocator failure at every allocation site; stale/released/cross-VM handle rejection.
