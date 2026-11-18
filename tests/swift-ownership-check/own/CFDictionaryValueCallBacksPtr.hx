package own;

@:swiftNativeType("UnsafePointer<CFDictionaryValueCallBacks>")
@:swiftBridge("Int", "kCFTypeDictionaryValueCallBacks", "withUnsafePointer(to: $0) { $1 in $body }", "$1")
abstract CFDictionaryValueCallBacksPtr(Int) from Int to Int {}
