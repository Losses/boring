package rusthandlefixtures;

// handle field write: assign a fresh handle into a handle field.
class Inner {
    public function new() {}
}

class Holder {
    public var inner:Inner;
    public function new() {
        inner = new Inner();
    }
}

class HandleFieldWriteOps {
    public static function replace(holder:Holder):Void {
        holder.inner = new Inner();
    }
}
