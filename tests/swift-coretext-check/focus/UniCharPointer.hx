package focus;

/**
    A pointer to UTF-16 units. The array owns the storage, so the call renders
    inside `withUnsafeBufferPointer` and the argument reads the buffer's
    base address. This is the pointer/lifetime bracket shape the Apple binding
    needs for `CFStringCreateWithCharacters` and its siblings.
**/
@:swiftNativeType("UnsafePointer<UInt16>")
@:swiftBridge("String", "$0", "$0.withUnsafeBufferPointer { $1 in $body }", "$1.baseAddress!")
abstract UniCharPointer(String) from String to String {}
