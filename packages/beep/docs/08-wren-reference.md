# Wren source and behavior map

## 1. Pinned revision

Repository: https://github.com/wren-lang/wren. Inspected commit: 99d2f0b8fc2686134b32b18166e037639f7e9f2c. Every source link in this document pins that revision. Updating the pin requires review and rerunning comparison fixtures.

## 2. Source mapping

| Beep area | Wren source anchors | Preserved behavior | Beep change |
| --- | --- | --- | --- |
| Scanner/parser | [wren_compiler.c](https://github.com/wren-lang/wren/blob/99d2f0b8fc2686134b32b18166e037639f7e9f2c/src/vm/wren_compiler.c): Parser, tokenization, parsePrecedence, methodCall, endCompiler | Pratt parsing, newline syntax, signatures, locals/upvalues | Source-spanned AST and declaration/type passes before emission. |
| VM ownership | [wren_vm.h](https://github.com/wren-lang/wren/blob/99d2f0b8fc2686134b32b18166e037639f7e9f2c/src/vm/wren_vm.h): struct WrenVM, WrenHandle, wrenCallFunction, wrenIsFalsyValue | Per-instance state, method symbols, roots, receiver-first windows | Replace active Fiber with synchronous ExecutionContext; add static metadata. |
| Interpreter | [wren_vm.c](https://github.com/wren-lang/wren/blob/99d2f0b8fc2686134b32b18166e037639f7e9f2c/src/vm/wren_vm.c): runInterpreter, wrenInterpret, wrenCall, runtimeError | Stack dispatch, frames, host entry | Remove Fiber switching/error search; Result returns normally; panic has separate exit. |
| Values/closures | [wren_value.h](https://github.com/wren-lang/wren/blob/99d2f0b8fc2686134b32b18166e037639f7e9f2c/src/vm/wren_value.h): Value, ObjFn, ObjClosure, ObjUpvalue, CallFrame, ObjFiber | Function/closure split, upvalues, class identity | Move active stack/frames to VM context; remove suspended Fiber state. |
| Classes | [wren_value.c](https://github.com/wren-lang/wren/blob/99d2f0b8fc2686134b32b18166e037639f7e9f2c/src/vm/wren_value.c): wrenNewClass, wrenBindSuperclass, wrenNewInstance | Single inheritance, inherited fields, instance allocation | Verify static signatures and interface witnesses before install. |
| Opcodes | [wren_opcodes.h](https://github.com/wren-lang/wren/blob/99d2f0b8fc2686134b32b18166e037639f7e9f2c/src/vm/wren_opcodes.h): CALL_*, SUPER*, NULL, IMPORT_MODULE, CLASS, METHOD_* | Stack instruction organization and method symbols | Remove source NULL/Fiber transfers; imports use compile transaction; add verifier. |
| GC | [wren_vm.c](https://github.com/wren-lang/wren/blob/99d2f0b8fc2686134b32b18166e037639f7e9f2c/src/vm/wren_vm.c): wrenCollectGarbage/root marking; [wren_value.c](https://github.com/wren-lang/wren/blob/99d2f0b8fc2686134b32b18166e037639f7e9f2c/src/vm/wren_value.c): wrenGrayObj; [wren_vm.h](https://github.com/wren-lang/wren/blob/99d2f0b8fc2686134b32b18166e037639f7e9f2c/src/vm/wren_vm.h): first/gray/tempRoots/handles | Non-moving mark-sweep, thresholds, roots, handles | Add compile/execution roots and Beep field descriptors. |
| Host API | [wren.h](https://github.com/wren-lang/wren/blob/99d2f0b8fc2686134b32b18166e037639f7e9f2c/src/include/wren.h): WrenConfiguration, resolver/loader, foreign binding, slots, handles | Opaque VM, allocator, callbacks, retained values | Compile/execute split, typed slots, structured outcomes. |

## 3. Documentation behavior mapping

- [Classes](https://wren.io/classes.html): class/member/field/this forms. Beep preserves syntax forms and adds static type/access checking.
- [Method Calls](https://wren.io/method-calls.html): receiver/argument left-to-right evaluation and name/arity signatures. Beep preserves both.
- [Functions](https://wren.io/functions.html): closures and block arguments. Beep preserves lexical capture/block syntax with typed function values.
- [Control Flow](https://wren.io/control-flow.html): blocks, if, loops, break and continue. Beep requires Bool and adds exhaustive matching.
- [Concurrency](https://wren.io/concurrency.html): Fiber transfer, yield and error handling. Beep removes suspension and uses Result for recoverable errors.
- [Embedding](https://wren.io/embedding): VM config, slots, handles and lifecycle. Beep retains embedding and types boundary slots.
- [Modules](https://wren.io/modules.html): names/loading/imports. Beep retains callbacks/cache and checks whole graph before initialization.

## 4. Comparison tests

For each preserved behavior, record a Wren example/test name, expected result, Beep test path, and deliberate differences. A Beep-only test does not prove Wren alignment. A source link without behavior/test mapping does not guide implementation. Updating pinned commit reruns the comparison fixtures and reviews changed symbols.
