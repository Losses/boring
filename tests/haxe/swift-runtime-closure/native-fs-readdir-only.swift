@main
struct NativeFsReadDirOnly {
    static func main() {
        print(try! FsReadDirOnly.observedValue())
    }
}
