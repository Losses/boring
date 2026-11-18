package ptr;

@:swiftNativeType("CFString")
@:swiftBridge("String", "String(decoding: $0, as: UTF16.self) as CFString")
abstract CFString(String) from String to String {}
