// Native entry of the Swift compile stage for the resident-closure
// fixture (t-mum0mp8l-m0a6). Identical for both variants: it links the
// generated tree into one binary and calls every extern face the
// consumer lowered. The generated tree itself carries no entry point.
@main
struct NativeMain {
    static func main() {
        print(Consumer.stringToolsFace("7"))
        print(Consumer.uStringFace("héllo"))
        print(Consumer.graphemeFace("héllo"))
        print(Consumer.sortedMapFace())
        print(Consumer.sortedSetFace())
    }
}
