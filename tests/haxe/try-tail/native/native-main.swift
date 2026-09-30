// Swift native harness. The runner copies this file into the generated tree
// root and compiles it with Runtime.swift (if emitted) and the generated
// package files.

@main
struct TryTailNativeMain {
    static func main() {
        print("p1-init=" + String(try! TryTailOracle.p1Init()))
        print("p1-ret=" + String(try! TryTailOracle.p1Ret()))
        print("p1-handler=" + String(try! TryTailOracle.p1Handler()))
        print("p2-init=" + String(try! TryTailOracle.p2Init()))
        print("p2-ret=" + String(try! TryTailOracle.p2Ret()))
        print("p2-handler=" + String(try! TryTailOracle.p2Handler()))
        print("p3-init=" + String(try! TryTailOracle.p3Init()))
        print("p3-ret=" + String(try! TryTailOracle.p3Ret()))
        print("p3-handler=" + String(try! TryTailOracle.p3Handler()))
        print("p4-init=" + String(try! TryTailOracle.p4Init()))
        print("p4-ret=" + String(try! TryTailOracle.p4Ret()))
        print("p4-handler=" + String(try! TryTailOracle.p4Handler()))
    }
}
