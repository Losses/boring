# Swift ownership check

This fixture is the macOS execution half of block B: CF/CG values stay
ARC-visible, raw pointers cross a C ABI through an explicit borrow, and a
cache holds class references in a Swift container.

## Scope

The original count of 49 retain/release sites came from a raw grep
(35 CFRelease, 2 CFRetain, 12 framework releases, including imports and
comments). The actual call sites are 33: 24 in the CF family (23 CFRelease
plus 1 CFRetain) and 9 in the CG family (4 CGContextRelease, 4
CGColorSpaceRelease, 1 CGPathRelease). On the macOS 26.4 SDK all five
functions are unavailable because Core Foundation and Core Graphics objects
are automatically memory managed. None of the 33 sites needs an explicit
release in generated Swift.

Deleting those sites from `platforms/apple` belongs to the module migration.
This block owns the emitter rules and the fixtures that prove the shapes.

## Rules

**No release family.** The generated Swift must not call
`CFRelease`, `CFRetain`, `CGContextRelease`, `CGColorSpaceRelease`, or
`CGPathRelease`. A binding that declares one of them as a top-level extern
static, or a call site that would emit one, fails generation. The positive
fixture's generated tree is scanned for zero occurrences.

**Class-typed externs.** A CF/CG value is declared with a typed extern class.
A raw pointer type would hide the value from ARC.

**Borrowed pointers.** A C API that hands back a `void*` (for example
`CFArrayGetValueAtIndex`) is converted with
`swift.Opaque.takeUnretained<T>`, which renders
`Unmanaged<T>.fromOpaque(pointer).takeUnretainedValue()`. The borrow has no
retain; the owner must outlive the use. The opposite direction, a Swift class
reference handed to a C ABI, uses `swift.Opaque.passUnretained`.
`swift.Opaque.takeRetained` is refused at generation time by default: an
ownership transfer needs a proof, and the tree currently has none.

**Cache container.** A cache holds class references in a Swift container
(dictionary or array). Inserting retains, removing releases, and no explicit
retain/release call is written. The empty release family in the generated tree
is the observable part.

## Run it

On macOS with the repository devShell and Xcode command line tools:

    bash tests/swift-ownership-check/run.sh

The script prints three assertion lines:

    b1 mapped=true data=4 number=42 numberOk=true array=1 arrayText=true dictText=true font=yes line=yes
    b2 runGlyphs=9 changed=2457
    b3 cached=true after=null

The negative cases are generation-only:

    haxe tests/swift-ownership-check/check-release-negative.hxml
    haxe tests/swift-ownership-check/check-retained-negative.hxml

Both exit non-zero with their rule text.

## When it fails

The CI macos job runs `Swift ownership check` after the pointer check. A
failed step uploads `swift-ownership-interop-log` with the step transcript
plus `compile.log` and `run.log`. Locally the same files live under
`out/swift-ownership-check/run`.
