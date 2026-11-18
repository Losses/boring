package swift;

/**
    Opaque-pointer conversions for C values that travel as `void*`.

    `takeUnretained<T>` renders `Unmanaged<T>.fromOpaque(pointer).takeUnretainedValue()`,
    which is the generic C interop step for a borrowed CF/opaque handle.
**/
class Opaque {
    public static function takeUnretained<T>(pointer:Null<RawPointer>):T {
        return cast null;
    }

    /** Hands a class reference to a C ABI as an untyped address. */
    public static function passUnretained<T>(value:T):RawPointer {
        return cast null;
    }

    /** Refused by default: an ownership transfer needs a proof. */
    public static function takeRetained<T>(pointer:Null<RawPointer>):T {
        return cast null;
    }
}
