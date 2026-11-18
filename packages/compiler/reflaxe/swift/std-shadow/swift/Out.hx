package swift;

/**
    A C `T*` out parameter.

    The Swift target passes `&value` where the extern declaration names
    `Out<T>`, so the callee writes into the field and the caller reads the
    result from `value`. The wrapper is an ordinary Swift class, which keeps
    the addressable storage alive across the call.
**/
class Out<T> {
    public var value:T;

    public function new(value:T) {
        this.value = value;
    }
}
