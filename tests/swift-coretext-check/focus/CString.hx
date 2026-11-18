package focus;

/**
    A NUL-terminated C string. The pointer is valid only while the native
    String owns its storage, so the bridge declares the lifetime bracket: the
    whole call renders inside `withCString`, and the argument is the bound
    pointer.
**/
@:swiftNativeType("UnsafePointer<CChar>")
@:swiftBridge("String", "String(decoding: $0, as: UTF16.self)", "$0.withCString { $1 in $body }", "$1")
abstract CString(String) from String to String {}
