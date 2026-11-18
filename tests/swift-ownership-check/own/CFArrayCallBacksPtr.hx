package own;

@:swiftNativeType("UnsafePointer<CFArrayCallBacks>")
@:swiftBridge("Int", "kCFTypeArrayCallBacks", "withUnsafePointer(to: $0) { $1 in $body }", "$1")
abstract CFArrayCallBacksPtr(Int) from Int to Int {}
