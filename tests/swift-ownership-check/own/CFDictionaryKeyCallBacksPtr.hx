package own;

@:swiftNativeType("UnsafePointer<CFDictionaryKeyCallBacks>")
@:swiftBridge("Int", "kCFTypeDictionaryKeyCallBacks", "withUnsafePointer(to: $0) { $1 in $body }", "$1")
abstract CFDictionaryKeyCallBacksPtr(Int) from Int to Int {}
