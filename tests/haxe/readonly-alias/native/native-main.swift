// Swift native harness. The runner copies this file into the generated
// tree root and compiles it with the emitted Runtime.swift and the
// generated package files, mirroring
// tests/haxe/view-lifetime/native-main.swift.
@main
struct ReadOnlyAliasNativeMain {
    static func main() {
        print("alias=" + String(describing: ReadOnlyAliasOracle.alias()))
        print("passed=" + String(describing: ReadOnlyAliasOracle.passed()))
        print("escaped=" + String(describing: ReadOnlyAliasOracle.escaped()))
        print("rebind=" + String(describing: ReadOnlyAliasOracle.rebind()))
        print("boundary=" + ReadOnlyAliasOracle.boundary())
    }
}
