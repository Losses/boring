package own;

// The value template is neither a $0 expression nor a bare identifier.
@:swiftNativeType("UnsafePointer<Int32>")
@:swiftBridge("Int", "kCFTypeArrayCallBacks + 1", "withUnsafePointer(to: $0) { $1 in $body }", "$1")
abstract BadBridgeCode(Int) from Int to Int {}
