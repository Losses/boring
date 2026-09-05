# Standard library spec 17: platform modules (fs, env, process arguments, path)

## Scope

This specification rules four host-adjacent standard library modules
(`std.Fs`, `std.Env`, the argument face of `std.Process`, and `std.Path`)
and the Swift build-chain change that `std.Fs` on Swift requires. For each
module it fixes which functions the module exposes, how each of the five
targets implements a call, and what a browser host does when it cannot.
It also lists the ad-hoc host externs in the toolchain that retire.

## Mechanism

A platform module is an `extern class` in `samples/std/`. Each target's
expression compiler lowers every static call on the module into the
calling file. No runtime package implements a platform module, and no
runtime file carries one: the backing expression (a host call, a lazy
host load, or a throwing stub) is emitted into the calling file, at the
call site or, when a target ruling fixes that shape, as the top-level
lowering the call site invokes. A file that never
calls `std.Fs` never mentions a host API, so the general-entry contract of
spec 06 is untouched and `tests/ts/runtime-entry.test.ts` keeps scanning
an unchanged entry.

Spec 06 currently rules two classes for `std.*`: runtime-backed modules
and compiled modules. A platform module is neither class. Spec 06 gains this
third class, with `std.UStringPlatform` (`samples/std/UStringPlatform.hx`)
and `std.TestPlatform` (`samples/std/TestPlatform.hx`) named as the prior
art that already follows it.

`std.Path` is NOT a platform module. It is a compiled std module in pure
Haxe (ruling 2026-09-02): every target shares one implementation, because
path joining and splitting are string logic that needs no host capability.

## Faces

```haxe
package std;

extern class Fs {
	/** Whether a path exists. */
	static function exists(path:String):Bool;
	/** Read a whole file as text. Raises the haxe.Exception mapping on failure. */
	static function readText(path:String):String;
	static function writeText(path:String, data:String):Void;
	static function appendText(path:String, data:String):Void;
	/** Create a directory and missing parents. */
	static function makeDirs(path:String):Void;
	/** Entry names of a directory, without the directory part. The list
	    never contains "." or ".."; its order is unspecified and each host
	    returns its native order. */
	static function readDir(path:String):Array<String>;
	static function isDirectory(path:String):Bool;
}

extern class Env {
	/** The value of an environment entry, null when absent. */
	static function get(key:String):Null<String>;
	static function set(key:String, value:String):Void;
	static function remove(key:String):Void;
}
```

`samples/std/Process.hx` gains one static:

```haxe
	/** The program arguments after the program name. */
	static function args():Array<String>;
```

`std.Path` is a compiled module with this face:

```haxe
package std;

class Path {
	/** Join two path segments with the platform-agnostic separator. */
	static function join(a:String, b:String):String;
	/** The directory part of a path. */
	static function dirname(path:String):String;
	/** Resolve `.` and `..` segments; map `\` to `/` first. */
	static function normalize(path:String):String;
	/** Expand a leading `~` to the home directory via `std.Env`. */
	static function expandHome(path:String):String;
}
```

`expandHome` reads `HOME` on POSIX targets and `USERPROFILE` on Windows
hosts through `std.Env.get`; a path that does not start with `~` returns
unchanged, and a missing variable leaves the `~` in place. This is the one
place `std.Path` depends on another std module.

Separator handling (ruling 2026-09-02): every `std.Path` function accepts
both `/` and `\` as separators on input, normalizes to `/` internally, and
returns `/`-separated text. The Windows section below carves out the
inputs where translation itself would change or corrupt the path.

## Windows path kinds (user requirement 2026-09-03)

Windows separators are the classic failure point of path libraries; every
`std.Path` function first classifies its input into a kind, and the kind
decides what the function may do with it:

| Kind | Shape (examples) | Rules |
| --- | --- | --- |
| Device | `\\?\C:\x`, `\\.\COM1` | Every function returns the input unchanged. After `\\?\` Win32 accepts no `/` and performs no `.`/`..` resolution, so translating separators or resolving dots can produce a broken path. |
| UNC | `\\server\share\a\b` | The root is `\\server\share`; `dirname` descends from there and never strips the root. Output form is `//server/share/...`; a leading `//` is preserved on re-parse so the round trip is stable. `..` at the root is dropped. |
| Drive absolute | `C:\a`, `C:/a` | `dirname` stops at `C:/`; the root form keeps its trailing separator (`C:/`). |
| Drive relative | `C:a` | No separator after the drive; per-drive current directories are host state a string layer does not have, so `normalize` leaves the text after the drive untouched and only applies separator translation. |
| Root relative | `\a` | Starts with `\` but no drive, no UNC. Kept root-relative; `dirname` stops at `\`. |
| POSIX absolute | `/a` | A leading `/` is always POSIX-absolute in this module, never a Windows root-relative path; a Windows caller passes `\a` for that meaning. |
| POSIX double slash | `//a` | POSIX leaves exactly two leading slashes implementation-defined; `normalize` preserves both leading slashes. |
| Relative | `a`, `a/b`, `a\b` | Both separators accepted (constant across hosts, per the 2026-09-02 ruling); on a POSIX host a `\` inside a filename is legal and this module rewrites it. The spec states this cost openly to keep the behavior identical on every host. |

Consequences for individual functions: `join(a, b)` returns `b` unchanged when `b`
is a device, UNC, drive-absolute, or POSIX-absolute path; joining onto a
device path is not defined and returns `b` as well. `normalize` on a
device path returns the input verbatim; on other kinds it translates
separators, resolves `.` and `..` (never past a root), and strips
trailing separators except on a root. `dirname(".")` and `dirname("")`
return `"."`; `dirname("/")` returns `"/"`; `dirname("C:/a")` returns
`"C:/"`; `dirname("//s/share/a")` returns `"//s/share"`.

Out of scope, stated as boundaries: the module does not validate reserved
device names (`CON`, `NUL`, `COM1`…), does not validate illegal
characters (`<>:"|?*`), and does not fold case; case sensitivity is a
host filesystem property. Source literals vs runtime values: in Haxe
source `"C:\\Users"` is the single-backslash value `C:\Users`; every
spec example and test fixture that contains a backslash must state
whether it shows the escaped source form or the runtime value.

## Target rulings

- **TypeScript.** The calling file gains no top-level `node:` import.
  Each `std.Fs` member a file uses lowers once to a top-level named
  arrow (`fs` + the capitalized member, as in `fsMakeDirs`) whose body
  holds the loader probe (`typeof require === "function" ?
  require("node:fs") : null`) and the unavailability throw; the probe
  evaluates per call, so `node:fs` still loads lazily per call and, when
  no host loader exists (browser), the call raises the haxe.Exception
  mapping with the fixed message `std.Fs is not available on this host`.
  The call site lowers to a plain call of that helper, so a loop body
  never carries a closure (the loop-structure invariant the generated
  tree is held to). `std.Env.get` reads
  `localStorage.getItem(key)` when `localStorage` is defined (synchronous,
  missing key null, a direct `Null<String>` match per ruling 2026-09-02)
  and `process.env[key] ?? null` otherwise; `set`/`remove` map to
  `setItem`/`removeItem` on the browser and to env assignment/deletion on
  node. `std.Process.args()` reads `process.argv.slice(2)` lazily.
- **Kotlin.** `std.Fs` maps to `java.nio.file.Files` and `Paths`;
  `makeDirs` is `Files.createDirectories`. `std.Env.get` is
  `System.getenv(key)` (null when absent). `std.Process.args()` needs the
  program arguments inside `main`: when any compiled module references
  `std.Process.args`, the generated entry is `fun main(args: Array<String>)`
  and the arguments thread to a generated holder; without the reference the
  entry keeps today's shape.
- **Rust.** `std.Fs.readText` reads bytes with `std::fs::read` and converts
  with `String::from_utf8_lossy` (ruling 2026-09-02: content becomes a
  `String` at read time; invalid UTF-8 sequences become U+FFFD; the read
  never fails for encoding reasons). `writeText`/`appendText` map to
  `std::fs::write`/`OpenOptions::append`; `makeDirs` is `create_dir_all`;
  `readDir` is `std::fs::read_dir` with entry names collected;
  `isDirectory` is `path.metadata().map(|m| m.is_dir())`. `std.Env.get` is
  `std::env::var(key).ok()`; a non-UTF-8 entry reads as absent.
  `std.Process.args()` is
  `std::env::args().skip(1).collect::<Vec<_>>()`.
- **Dart.** `std.Fs` maps to `dart:io` (`File`, `Directory`); `makeDirs`
  is `Directory.create(recursive: true)`. `std.Env.get` is
  `Platform.environment[key]`. `std.Process.args()` threads
  `main(List<String> args)` like Kotlin. The web compilation of Dart is
  not a target of this toolchain; `dart:io` availability is unconditional.
 - **Swift.** On x86_64 Linux, Swift 6.2.4 supplies FoundationEssentials;
   the test entry writes results through `print(..., terminator: "")` to stdout
   (`packages/compiler/reflaxe/swift/swiftcompiler/SwiftRuntime.hx`). The six
   `std.Fs` operations `exists`, `readText`, `writeText`, `makeDirs`, `readDir`,
   and `isDirectory` map to `FoundationEssentials.FileManager`. `appendText`
   remains on swift-system: one `FileDescriptor.open(FilePath(path),
   .writeOnly, options: [.create, .append], ...)` call followed by
   `writeAll(text.utf8)`. `std.Env.get`, `set`, and `remove` remain native
   platform calls so all three operate on the same environment view.
   FoundationEssentials is conditionally imported only in generated files that
   reference one of the six FileManager helpers; `SystemPackage` is imported
   only for appendText. SwiftPM pins `SystemPackage` at `1.6.6` and keeps
   generated sources in Swift 5 language mode.


  Host conditioning remains explicit for the native environment helpers:
  `std.Env.get` uses `getenv` on Glibc/Darwin and the Windows `CRT` module,
  `std.Env.set` uses `setenv` or `_putenv_s`, and `std.Env.remove` uses
  `unsetenv` or `_putenv`. The paired C runtime calls keep get/set/remove
  on one environment view. The Windows module is `CRT`, the Swift overlay
  of ucrt that swiftlang toolchains ship; the 6.1.2 Windows SDK has no
  MSVCRT module. FileManager supplies the filesystem behavior on hosts
  that import FoundationEssentials; Apple SDKs do not expose that module
  as a top-level import, so generated files fall back to `Foundation`
  through `canImport(Darwin)`. Hosts with neither module use the fixed
  unavailability exception arm.

  The SwiftPM test chain runs Swift 6.2.4 on Linux and pins swift-system
  `1.6.6`; every generated target stays in Swift 5 language mode.

## Swift build-chain migration (in scope, ruling 2026-09-02)

The Swift chain moves from bare `swiftc` invocations to SwiftPM:

1. The test chain gains a `Package.swift` declaring the swift-system
   dependency; `swift build` replaces the direct `swiftc` invocation in
   the Swift test and verification commands.
2. The dependency declaration lives only in the test-chain
   `Package.swift`; generated code never declares dependencies.
3. The `import SystemPackage` line lowers only into generated files whose
   functions reference `std.Fs` (inline lowering keeps host imports inside
   function bodies, so files with no fs reference never import the
   package; ruling 2026-09-02 requires conditional import and never a
   blanket import).
4. `std.Process.args()` probes `CommandLine.arguments` availability in the
   same migration.

## Failure contract

Failures raise the target's `haxe.Exception` mapping (spec 03) with the
path and the host error text in the message. An unmapped capability on a
host (for example `std.Fs` in a browser) raises the same mapping with the
fixed unavailability message above; it never returns a wrong value.
A platform this spec implements (the Windows Swift host among them)
never falls under the unmapped clause: unmapped means the host has no
corresponding capability at all; it does not mean that the toolchain
skipped implementing a platform. Compilation always succeeds; host
support is a runtime property, decided at the call.

## Host externs that retire

| Site | Fate |
| --- | --- |
| `packages/registry/src/registry/Platform.hx` (jsRequire Fs/Path, NodeProcess, Console.error) | retires onto `std.Fs`, `std.Path`, `std.Process`, `std.Console` |
| `packages/registry/src/registry/Environment.hx` (JSON-text bridge over `process.env`) | retires onto `std.Env.get`; the bridge existed because a typed extern could not carry undefined-vs-null, and inline lowering emits `?? null` itself (spec 26 rewrite follows) |
| `packages/compiler/TestCollector.hx` (runnerSource embedded jsRequire externs) | retires onto `std.Fs`/`std.Env`/`std.Process` |
| `tools/test-consistency/Main.hx` (Syntax.code require fs) | retires when the tool's host haxe compiles through boring (a separate decision outside this spec) |
| `packages/compiler/reflaxe/ts/tscompiler/TsRuntime.hx` (TEST_SOURCE node:fs) | stays: the test entry owns host filesystem access per spec 06 |
| `samples/std/Process.hx`, `samples/std/Console.hx` | stay; Process gains `args()` |

Payoff: `packages/registry/src/registry/Main.hx` enters five-target
compilation; its blocker was the `@:jsRequire` externs of `Platform.hx`,
and after migration no jsRequire import remains.

## Test hooks

- New samples under `samples/std/` exercise each face on every target chain
  except the browser-throws branch, which a TypeScript unit test pins by
  textual assertion on the lowered branch shape.
- `std.Path` gets a shared-semantics test: one Haxe test file runs on all
  five targets and asserts identical outputs for separator mixing
  (`a\b/c`), `.`/`..` normalization, and `~` expansion (with the variable
  set through `std.Env.set` in the test setup).
- `tests/ts/compiler-scope.test.ts` carries the new module names.
- The consistency run reads the new sample's jsonl alongside the other
  targets.
