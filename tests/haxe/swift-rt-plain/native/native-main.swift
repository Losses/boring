@main
struct PlainNativeMain {
    static func main() {
        print("sum=" + String(Plain.add(2, 3)))
    }
}
