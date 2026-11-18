package swift;

/**
    A read-only C buffer of `T`.

    The representation matches `Buffer`, and an extern argument position
    passes the array itself, which Swift converts to `UnsafePointer<T>`.
**/
@:swiftNativeType("[$T]")
class ConstBuffer<T> {
    public static function alloc<T>(count:Int, fill:T):ConstBuffer<T> {
        return cast null;
    }

    public function get(index:Int):T {
        return cast null;
    }
}
