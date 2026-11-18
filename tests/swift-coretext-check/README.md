# Swift C interop check

This fixture is the permanent check behind the Swift target's platform-API
claims. It generates Swift that calls real Core Text, compiles the tree
against the macOS SDK, and runs it so the measured font metrics come from the
framework itself.

The rest of the release path only proves that generated Swift compiles. A tree
can compile and still have no route from a Haxe String to a Core Foundation
string, a platform import, or a C enum spelling. This check exercises those
three declarations:

- `focus/CoreTextMetricsSupport.hx` carries `@:swiftImport("CoreText")`, so
  its generated file opens with `import CoreText` and the files that name no
  platform symbol stay import free.
- `focus/CFString.hx` declares `@:swiftNativeType("CFString")` with a
  `@:swiftBridge` value conversion; `focus/CString.hx` and
  `focus/UniCharPointer.hx` declare the `withCString` and
  `withUnsafeBufferPointer` lifetime brackets.
- `focus/CoreText.hx` spells the CF_ENUM member as
  `CTFontUIFontType.system`, the encoding as
  `CFStringBuiltInEncodings.UTF8.rawValue`, and the CFIndex seam as
  `Int`.

## Run it

On macOS with the repository devShell and Xcode command line tools:

    bash tests/swift-coretext-check/run.sh

The script writes to `out/swift-coretext-check/run` by default and prints the
measured metrics:

    named ascent=36.9609375 descent=11.0390625
    cstring ascent=36.9609375 descent=11.0390625
    units ascent=36.9609375 descent=11.0390625
    system-ui ascent=46.40625 descent=10.125

Generation alone works on any platform that can run Haxe:

    haxe tests/swift-coretext-check/check.hxml \
      -D swift-output=out/check/gen \
      -D swift-test-output=out/check/gen-tests

`tests/swift-coretext-check/emit.test.ts` is the collected suite's half. It
pins the generated text (import scope, bridge expressions, enum spellings,
repeat-generation stability) on every platform, while the macOS step only has
to prove that the same text compiles and runs against the real SDK.

## When it fails

The CI macos job runs the script in the step `Swift C interop check (generated
Core Text sample compiles and runs)`. A failed step uploads the
`swift-c-interop-log` artifact with the step transcript, `compile.log`, and
`run.log`; read the compiler output there first. Locally the same files live
under `out/swift-coretext-check/run`.

The check has its own fixture directory and is not listed as a bundle in
`boring.json`; changing the Swift emitter does not regenerate the reference
trees to exercise it, so this fixture is the only coverage for the declarations
above.
