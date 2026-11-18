// The lifetime probe driver: `leak` and `double` run as separate processes.
@main
struct BufferLifetimeMain {
    static func main() {
        let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "leak"
        if mode == "double" {
            BufferLifetime.doubleFree()
        } else {
            BufferLifetime.leak()
        }
    }
}
