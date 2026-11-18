package focus;

/**
    A Core Foundation string at a C boundary. Haxe sees the underlying String,
    so a call site passes a String; the abstract's native spelling is the
    platform type, and the bridge states the one conversion available: the
    target's unit-array String decodes to a native Swift String, whose
    toll-free bridge yields a `CFString` that stays valid for the call.
**/
@:swiftNativeType("CFString")
@:swiftBridge("String", "String(decoding: $0, as: UTF16.self) as CFString")
abstract CFString(String) from String to String {}
