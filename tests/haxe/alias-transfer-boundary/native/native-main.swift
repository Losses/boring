// Swift native harness. The runner copies this file into the generated
// tree root and compiles it with the emitted Runtime.swift and the
// generated package files, mirroring
// tests/haxe/view-lifetime/native-main.swift.
@main
struct AliasTransferNativeMain {
    static func main() {
        print("field=" + String(describing: ContainerAliasOracle.field()))
        print("fieldNull=" + String(describing: ContainerAliasOracle.fieldNull()))
        print("fieldRebind=" + String(describing: ContainerAliasOracle.fieldRebind()))
        print("relay=" + String(describing: ContainerAliasOracle.relay()))
        print("relayFresh=" + String(describing: ContainerAliasOracle.relayFresh()))
    }
}
