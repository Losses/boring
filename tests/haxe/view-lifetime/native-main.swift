@main
struct ViewLifetimeNativeMain {
    static func main() {
        print("rebind=" + String(describing: ViewLifetimeOracle.rebind()))
        print("escaped=" + String(describing: ViewLifetimeOracle.escapedConsumer()))
        print("local-mutation=" + String(describing: ViewLifetimeOracle.localAliasMutation()))
        print("combined=" + String(describing: ViewLifetimeOracle.combinedConsumer()))
        print("boundary=" + ViewLifetimeOracle.boundaryProbe())
    }
}
