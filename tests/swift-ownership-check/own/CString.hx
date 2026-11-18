package own;

@:swiftNativeType("UnsafePointer<CChar>")
@:swiftBridge("String", "String(decoding: $0, as: UTF16.self)", "$0.withCString { $1 in $body }", "$1")
abstract CString(String) from String to String {}
