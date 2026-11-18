// The entry point the generated `-main` class does not carry: the Swift
// target emits the class's static `main` method, and the fixture driver calls it.
@main
struct A1Main {
    static func main() {
        OutFixture.main()
    }
}
