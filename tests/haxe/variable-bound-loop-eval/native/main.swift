// Native invocation harness for the Swift generated module of the
// variable-bound-loop-eval fixture. The runner builds the generated tree as
// a library module named VbleProbe and links this harness against it, so the
// harness calls the three generated probe functions once each and prints the
// three returned bound-read counts. The generated main() calls the fixture
// shadow of haxe.Log (a no-op), so this harness is the only printer of the
// observation line. The host C library supplies the error stream and the exit
// status; the toolchain carries no Foundation module.
#if canImport(Glibc)
import Glibc
#endif
#if canImport(Darwin)
import Darwin
#endif

import VbleProbe

let local = Probe.localBound()
let length = Probe.growingLength()
let control = Probe.doubleControl()
print("local=\(local) length=\(length) control=\(control)")
