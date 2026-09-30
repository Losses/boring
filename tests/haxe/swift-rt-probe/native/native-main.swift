// Swift native harness for the minimal probe fixture. The runner copies
// this file into the generated tree root and compiles it with Runtime.swift
// (when emitted) and the generated package files.

@main
struct ProbeNativeMain {
    static func main() {
        print("concrete=" + String(try! Probe.catchConcrete("probe-1")))
    }
}
