# Swift target and Core Text: the probe result (task t-mwl2ttvv-yaco)

The Apple cutover question is whether the Swift emitter can express a Core Text
call, and whether a minimal consumption point can be compiled and run on macOS
from generated code. The answer the probe measured is **partly**: the call shape
is expressible today, the argument construction is not, and the import needs a
mechanism that the target happens to carry only for the test tree.

## 1. What the emitter can express today

**Imports are a fixed list.** The header of a generated file is built in
`Compiler.fileContent` (`packages/compiler/reflaxe/swift/swiftcompiler/Compiler.hx:491-563`):
`import Foundation` when the module references a Foundation-backed host edge
(`:502-504`), the `FoundationEssentials`/`Foundation` pair behind `canImport`
(`:516-529`), the `Glibc`/`Darwin`/`CRT`/`WinSDK` block behind `canImport`
whenever the module uses any host edge (`:530-543`), and `import SystemPackage`
(`:544-546`). `SwiftImports` (`.../SwiftImports.hx:13-104`) is a runtime-usage
flag table for that header; it carries no module inventory, because the target
emits **one Swift module**, so value and type references between generated
modules need no import at all (`SwiftImports.hx:106-118`). The one existing
hole that emits an arbitrary module name is the `swift-test-import` define
(`Compiler.hx:498-501`, `testImportPrefix` at `:432-436`): it renders
`import <define>` into every **test** module. The probe uses that define to get
`import CoreText`; a production cutover needs a first-class import mechanism.

**External calls go through extern classes and two markers.** An extern class
emits no declaration (`ignoreExterns: true`, `Compiler.hx:110`; the early return
at `:162-165`), and a reference to one of its statics renders
`<ClassName>.<member>` (`SwiftExpr.staticRef`, `.../SwiftExpr.hx:3565-3566`).
The escape hatches are the `@:topLevel` and `@:extension` markers
(`packages/compiler/StaticFunctionMarkers.hx:12-38`), which make `staticRef`
render the bare member name (`SwiftExpr.hx:3563-3568`), and the **variable form**
of `@:topLevel` for a `static final` constant
(`StaticFunctionMarkers.hx:55-78`), which renders a bare global constant. That is
exactly the Swift spelling of a C function and of a C constant, and it is what
the probe used: `CTFontCreateWithName(...)`, `CTFontCreateUIFontForLanguage(...)`,
`CTFontGetAscent(...)`, `kCTFontUIFontSystem`.

**Two argument shapes do not survive that path.**

- **Strings.** Every Haxe `String` lowers to `[UInt16]` in this target: `SwiftType.resident`
  is set unconditionally (`.../SwiftType.hx:28-37`, `StringUnitArrayBacking`), and a
  string literal renders `Array("...".utf16)` (`SwiftExpr.hx:7812-7817`). A cast to an
  extern class type renders `(value as! T)` (`SwiftExpr.hx:2921-2928`), so a Haxe
  String in a `CFString` position becomes `(Array("Helvetica".utf16) as! CFString)`.
  That compiles and then traps at run time: the probe's negative control shows the
  process dying with `Could not cast value of type 'Swift.Array<Swift.UInt16>'`.
  Nothing in the subset produces a `CFString` from a Haxe String.
- **Nothing else does either.** A null literal against a non-optional extern
  parameter renders `nil!`; against a parameter declared `Null<T>` it renders `nil`
  (measured, both shapes generated from the same call). `CGFloat` has no Haxe
  spelling (the target has one float width, `Double`), so the probe puts each
  `CGFloat` seam in a helper whose declared return type is the `Double` the
  emitter writes; Swift's SE-0307 interchangeability converts there.

**What is absent outright:** any pointer construct (`UnsafePointer`,
`withUnsafe*` scopes), any ownership construct (`deinit` emission, `Unmanaged`,
retain/release), any C-string scope, and any value-type C struct construction.
The only pointer code in the target lives inside fixed runtime source strings
(`SwiftRuntime.hx:477`, `:565`, `SwiftDecl.hx:485`), which no consumer can reach.

## 2. The probe

`tests/swift-coretext-probe/` holds the whole probe:

| file | role |
|---|---|
| `probe/CoreText.hx` | extern class with `@:topLevel` statics and one `@:topLevel` constant |
| `probe/CoreTextMetricsSupport.hx` | the `CGFloat` seams and the font construction |
| `probe/CoreTextMetricsTests.hx` | the `@:test` consumption point, writes `out/coretext-probe/metrics.txt` |
| `probe/CoreTextByNameNegativeTests.hx` | the control: the same call with no String bridge |
| `swift/CoreTextStringBridge.swift` | the one hand-written conversion, `[UInt16] -> CFString` |
| `probe.hxml`, `probe-by-name.hxml` | the two generation runs |

Generated call text (the part that matters):

```swift
import CoreText

public enum CoreTextMetricsSupport {
    public static func createSystemFont(_ size: Double) -> CTFont? {
        return CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, size, nil)
    }

    public static func createNamedFont(_ name: [UInt16], _ size: Double) -> CTFont {
        return CTFontCreateWithName(coreTextString(name), size, nil)
    }

    public static func ascentOf(_ font: CTFont) -> Double {
        return CTFontGetAscent(font)
    }

    public static func descentOf(_ font: CTFont) -> Double {
        return CTFontGetDescent(font)
    }
}
```

`coreTextString` is the hand-written bridge; every Core Text symbol in that
snippet is generated. `.github/workflows/swift-coretext-probe.yml` generates,
compiles and runs the tree on `macos-latest`, and runs the negative control
under `continue-on-error` so its trap is recorded in the log:

```
gh workflow run swift-coretext-probe.yml --ref probe/swift-coretext
```

## 3. Mechanisms a cutover needs

| mechanism | shape | what it costs |
|---|---|---|
| Swift module import | a per-declaration `@:swiftImport("CoreText")` that `SwiftImports` collects into the file header, emitted under `#if canImport` | one metadata read in `SwiftDecl`/`SwiftImports`, one header line in `Compiler.fileContent`, plus the duplicate-import and ordering rules; small, and it is the cheapest of the five |
| String bridge | a declared conversion from the unit-array String to a C string type: `CFString` from `[UInt16]`, and a C-string scope for `CFStringCreateWithCString` | a new emitter form for a scoped conversion (`withCString`-style), because the C-string case needs a lifetime bracket that a plain call cannot express |
| Numeric width seams | keep `CGFloat` at extern boundaries and let SE-0307 convert at typed positions | documentation plus a lint that pins the seam to a helper; no emitter change |
| Pointers and out-parameters | `UnsafePointer`/`UnsafeMutablePointer` parameters and in-out C arrays, which Core Text uses for glyph runs and typographic bounds | a genuine type model addition: the subset has no pointer type, no alloc/dealloc pairing, and no scoping construct |
| Ownership | retain/release and framework release (`CFRelease`, `CGContextRelease`, ...) | Swift ARC covers the Swift side; the C side needs `Unmanaged` and a wrapper with `deinit`, so the emitter needs a destructor form and a rule for who owns an opaque handle |

## 4. Scale, measured on `platforms/apple`

The Kotlin/Native binding half is 15 `.kt` files and 3544 lines, and 12 of those
files opt into `ExperimentalForeignApi`. It uses **70 distinct CT/CG/CF symbols**
(24 `CT`, 27 `CG`, 19 `CF`) with this construct mix:

| construct | uses | mechanism it needs |
|---|---:|---|
| `CFRelease` / `CFRetain` | 35 / 2 | ownership |
| framework releases (`CGContext`, `CGColorSpace`, `CGPath`) | 12 | ownership |
| `memScoped` scopes | 13 | pointer lifetime scopes |
| `cValue` reads | 5 | pointer reads |
| `CFStringCreateWithCString` | 6 | C-string scope |
| `CFDictionaryCreate` / `CFArrayCreate` | 6 / 2 | CF container construction from arrays of pointers |
| `CTRunGetPositions` / `CTRunGetGlyphs` / `CTFontDrawGlyphs` | 4 / 4 / 3 | in/out C arrays |
| `CTLineGetTypographicBounds` | 2 | out-parameters |

Two facts from that table set the size of the job. First, the binding does not
call `CTFontCreateWithName` at all: fonts come from
`CTFontDescriptorCreateWithAttributes` plus `CTFontCreateWithFontDescriptor`, and
both take a `CFDictionary` of `CFNumber` and `CFString` values, so the String
bridge the probe had to hand-write is on the **critical path** of the real
binding twice (a C string into a `CFString`, then a `CFString` into a
dictionary). Second, 49 of the symbols' call sites are retain/release points, so
the ownership mechanism is a precondition for the first line of real binding
code, and the probe's simplest possible call tells nothing about it.

Read against that, the cutover is **not** a porting job yet: it is five emitter
mechanisms with pointer, ownership, and CF-container modelling in front of a
~70-symbol binding. The probe's two calls are the part that already works; the
remaining work is dominated by the two mechanisms the Swift target has no
representations for at all.

## 5. Risks

- **Trap-by-construction.** The String path compiles cleanly and fails at run
  time, so a port written against today's emitter would build and crash on first
  use; every bridged call site needs a test that executes it.
- **Ownership is invisible in Haxe types.** A Haxe extern class instance that
  wraps a retained `CFTypeRef` has no place to state whether the reference is
  owned, so the retain/release rule has to live in a convention the emitter
  cannot check.
- **One module.** Every generated file compiles into a single Swift module, so a
  host framework import appears in a file's header with no module qualification;
  that constrains the import mechanism's design (no aliasing, no selective
  import) and makes a per-file lifetime for imports mandatory.
