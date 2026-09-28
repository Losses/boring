// Native invocation harness for the Swift generated module of the comparison
// observation fixture. The runner builds the generated tree as a library module
// and links this harness against it, so the harness prints the text one
// generated observation function returns. It holds no ordering decision and
// re-implements no comparator. The case name is the first program argument.
// The host C library supplies the error stream and the exit status; the
// toolchain carries no Foundation module.
#if canImport(Glibc)
import Glibc
#endif
#if canImport(Darwin)
import Darwin
#endif

import CmpObs

func observation(_ name: String) -> String {
    switch name {
    case "int-ordinary": return ComparisonObserve.intOrdinary()
    case "int-extremes": return ComparisonObserve.intExtremes()
    case "array-order": return ComparisonObserve.arrayOrder()
    case "nullable-order": return ComparisonObserve.nullableOrder()
    case "string-order": return ComparisonObserve.stringOrder()
    case "nullable-int-order": return ComparisonObserve.nullableIntOrder()
    case "mixed-sign-array-order": return ComparisonObserve.mixedSignArrayOrder()
    case "shared-enum-helpers": return ComparisonObserve.sharedEnumHelpers()
    case "same-short-record-helpers": return ComparisonObserve.sameShortRecordHelpers()
    case "parameter-composition": return ParameterCompositionCases.observe()
    default:
        fputs("comparison harness: unknown case \(name)\n", stderr)
        exit(2)
    }
}

let arguments = CommandLine.arguments
let requested = arguments.count > 1 ? arguments[1] : "<none>"
print(observation(requested))
