package own;

// The bare identifier has no declaration in the compilation unit.
@:swiftNativeType("UnsafePointer<Int32>")
@:swiftBridge("Int", "kCFTypeArrayCallBackz", "withUnsafePointer(to: $0) { $1 in $body }", "$1")
abstract BadBridgeName(Int) from Int to Int {}
