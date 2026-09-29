// Native invocation harness for the Swift generated module of the signed key
// composition fixture. The runner builds the generated tree as a library
// module and links this harness against it, so the harness prints the text
// one generated observation function returns. It holds no ordering decision
// and re-implements no comparator. The case name is the first program
// argument. The host C library supplies the error stream and the exit
// status; the toolchain carries no Foundation module.
#if canImport(Glibc)
import Glibc
#endif
#if canImport(Darwin)
import Darwin
#endif

import KeyComp

func observation(_ name: String) -> String {
    switch name {
    case "direct-int": return KeyCompositionObserve.directInt()
    case "direct-int-extremes": return KeyCompositionObserve.directIntExtremes()
    case "typedef-int": return KeyCompositionObserve.typedefInt()
    case "typedef-int-extremes": return KeyCompositionObserve.typedefIntExtremes()
    case "composite-nullable": return KeyCompositionObserve.compositeNullable()
    case "composite-extremes": return KeyCompositionObserve.compositeExtremes()
    default:
        fputs("signed-key-composition harness: unknown case \(name)\n", stderr)
        exit(2)
    }
}

let arguments = CommandLine.arguments
let requested = arguments.count > 1 ? arguments[1] : "<none>"
print(observation(requested))
