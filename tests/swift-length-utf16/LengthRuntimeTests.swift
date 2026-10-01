// Swift runtime driver for the coalescing String.length fixture.
// Compiled together with the generated Swift (see run.sh); the
// coalesced default must count UTF-16 code units, so "a😀b" prints 4.
@main
struct LengthRuntimeTests {
    static func main() {
        print("coalesced=\(CharCount.charCount("a😀b"))")
        print("present=\(CharCount.charCount("a😀b", 9))")
    }
}
