# Swift pointer interop check

This fixture is the macOS execution half of block A: out parameters (T* and
T**), temporary C buffers, and the opaque-pointer step. The declarations are
generic C interop shapes; Core Text is only the framework the fixture happens
to drive.

## Public declarations

`swift.Out<T>` (package `swift`, std-shadow)

- Swift representation: `public final class Out<T> { public var value: T }`.
- An extern argument position with this parameter type renders `&arg.value`;
  a `Null<Out<T>>` position accepts `nil`.
- The argument must be a plain local or field, so the address stays valid for
  the call. A constructor call is rejected at generation time
  (`an out parameter needs a plain local or field`).
- Lifetime: the callee writes during the call; the caller reads `value` after.
  The wrapper keeps no C ownership, so it cannot stand in for a retained
  handle.

`swift.Buffer<T>` (package `swift`, std-shadow)

- Swift representation: `UnsafeMutablePointer<T>`.
- `alloc(count, fill)` allocates and initializes; `get(i)` and `set(i, v)`
  subscript the pointee; `free(count)` deinitializes and deallocates.
- An extern argument position passes the pointer itself, which converts to
  `UnsafePointer<T>` at a read-only parameter.
- Lifetime: the caller must call `free(count)` exactly once after the last
  use. The runtime gives no diagnostic for a missing free or a double free:
  measured on macOS 26.5.1 with Swift 6.3.1 (also with
  `MallocScribble=1 MallocGuardEdges=1`) both mistakes exited 0. A missing
  free is a silent leak and a double free is silent undefined behavior, so
  block B cannot rely on a crash and has to detect the pairing statically.
- Ownership on this SDK: `CGContextRelease` and `CGColorSpaceRelease` are
  unavailable in Swift (Core Foundation objects are automatically memory
  managed). Block B's rule must account for ARC-managed CF values and cannot
  assume every Create/Copy needs an explicit release call.

`@:swiftLabels` (declaration metadata)

- A marked extern static may declare a `|`-separated label list, one entry
  per argument. An empty entry keeps the argument unlabeled.
- The call renders the labels in Swift form, which is how a Swift-imported
  initializer is called: `CGContext(data: pixels, width: 64, ...)`.
- C functions without labels keep the plain positional form; the metadata is
  only for the imported shape.

`swift.RawPointer` and `swift.Opaque.takeUnretained<T>` (package `swift`, std-shadow)

- Swift representation: `UnsafeRawPointer`.
- `takeUnretained<T>(pointer)` renders
  `Unmanaged<T>.fromOpaque(pointer!).takeUnretainedValue()`.
- Lifetime: the pointer is borrowed. The call performs no retain, so the
  owning C object must outlive the use.

## Which declaration when

| C shape at the call site | declaration | ownership |
|---|---|---|
| `T*` out parameter, caller reads the result | `swift.Out<T>` | the wrapper is a plain class; it holds no C ownership |
| contiguous `T*` buffer (read, write, or both) | `swift.Buffer<T>` | allocated for the call; `free(count)` once |
| `void*` or opaque pointer to a class object | `swift.RawPointer` + `swift.Opaque.takeUnretained<T>` | borrowed; the owner must outlive the use |
| Swift-imported call that needs argument labels | `@:swiftLabels(...)` | none; the metadata only sets the call spelling |
| platform scalar or struct spelling | `@:swiftNativeType(...)` | none; the type is rendered with that Swift name |
| value returned by Create/Copy as a class reference | a typed extern class | ARC-managed; no release call |

The four do not overlap: `Out` owns no storage, `Buffer` owns raw memory, `RawPointer` borrows an address, and `swiftLabels` only changes how the call is written. A labeled initializer can still take a `Buffer` or an `Out` argument.

## Run it

On macOS with the repository devShell and Xcode command line tools:

    bash tests/swift-pointer-check/run.sh

The script generates the fixture, compiles the whole tree with
`swiftc -swift-version 5`, runs it, and asserts the printed values. The
generated tree lives under `out/swift-pointer-check/run` by default.

Generation alone works on any platform that can run Haxe:

    haxe tests/swift-pointer-check/check.hxml \
      -D swift-output=out/pointer/gen \
      -D swift-test-output=out/pointer/tests

`tests/swift-pointer-check/emit.test.ts` is the collected suite's half. It
pins the emitted shapes and drives the A6 negative case.

## Lifetime record

`bash tests/swift-pointer-check/lifetime.sh` runs the two deliberate
mistakes in separate processes and prints `leak_exit` and
`double_free_exit` with their logs. The CI macos job records the same output
in the `swift-pointer-interop-log` artifact; it is a record, so the step
does not gate on a crash.

## When it fails

The CI macos job runs `Swift pointer interop check` after the Core Text
check. A failed step uploads `swift-pointer-interop-log` with the step
transcript plus `compile.log` and `run.log`. Locally the same files live
under `out/swift-pointer-check/run`.
