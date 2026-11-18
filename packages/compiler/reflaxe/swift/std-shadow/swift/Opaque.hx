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
}
