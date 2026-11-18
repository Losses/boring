package swift;

/**
    An untyped C pointer. The Swift spelling is `UnsafeRawPointer`, and the
    type only appears where a C API hands back an opaque address.
**/
@:swiftNativeType("UnsafeRawPointer")
extern class RawPointer {}
