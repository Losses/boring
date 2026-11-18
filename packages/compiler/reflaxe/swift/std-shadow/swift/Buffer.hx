package swift;

/**
    A C buffer of `T`.

    The Swift representation is `UnsafeMutablePointer<T>`: `alloc` allocates
    and initializes, `get/set` subscript the pointee, an extern argument
    position passes the pointer itself, and `free` deinitializes and
    deallocates. The declaration emits nothing.
**/
@:swiftNativeType("UnsafeMutablePointer<$T>")
class Buffer<T> {
    public static function alloc<T>(count:Int, fill:T):Buffer<T> {
        return cast null;
    }

    public function get(index:Int):T {
        return cast null;
    }

    public function set(index:Int, value:T):Void {}

    public function free(count:Int):Void {}
}
