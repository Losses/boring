// Swift native harness. The runner copies this file into the generated
// tree root and compiles it with the emitted Runtime.swift and the
// generated package files, mirroring tests/haxe/readonly-alias. The
// text() parameter is Any? so the harness compiles whether the
// generated codeInt() signature is Int or Int?; a nil value is
// rendered as the token "null".
@main
struct CharCodeAtNativeMain {
    static func text(_ v: Any?) -> String {
        (v as? Int).map { String(describing: $0) } ?? "null"
    }

    static func main() {
        print("subRev=" + CharCodeAtOracle.subRev())
        print("subHigh=" + CharCodeAtOracle.subHigh())
        print("subNeg=" + CharCodeAtOracle.subNeg())
        print("codeNull=" + text(CharCodeAtOracle.codeNull()))
        print("codeNeg=" + text(CharCodeAtOracle.codeNeg()))
        print("codeInt=" + text(CharCodeAtOracle.codeInt()))
    }
}
