// Swift native harness. The runner copies this file into the generated
// tree root and compiles it with the emitted Runtime.swift and the
// generated package files, mirroring tests/haxe/try-tail.
//
// Signature notes (matched against the generated lowering at base
// e8648488): the three probe functions are `throws -> String` (the
// lowered try region carries a bare catch that rethrows unmatched
// domains), so each line runs in its own do/catch. The fixture
// exception is absorbed by the region itself; a harness-caught line
// would be an observation outside the authored expectations.
@main
struct ThrowingDefaultNativeMain {
    static func line(_ label: String, _ body: () throws -> String) -> String {
        do {
            let value = try body()
            return label + "=" + value
        } catch {
            return label + "=harness-caught:\(error)"
        }
    }

    static func main() {
        print(line("omittedSafe", ThrowingDefaultOps.probeOmittedSafe))
        print(line("omittedThrowing", ThrowingDefaultOps.probeOmittedThrowing))
        print(line("explicit", ThrowingDefaultOps.probeExplicit))
    }
}
