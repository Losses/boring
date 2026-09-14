package boring;

#if rust_output
/**
    An interface method whose declared Haxe return is a plain value while one
    implementation throws. The Rust trait method carries the Result, so a
    call through the interface receiver propagates the error. The named
    interfaceFallibleCall rule covers the call boundary.
*/
interface InterfaceFallibleEdge {
    public function resolve(key:Int):String;
}

class InterfaceFallibleEdgeImpl implements InterfaceFallibleEdge {
    public function new() {}

    public function resolve(key:Int):String {
        if (key < 0)
            throw new InterfaceFallibleFault("negative");
        return "value" + key;
    }
}

class InterfaceFallibleFault extends haxe.Exception {
    public function new(message:String) {
        super(message);
    }
}

class InterfaceFallibleOps {
    public static function resolve(edge:InterfaceFallibleEdge, key:Int):String {
        if (key == 0)
            throw new InterfaceFallibleFault("zero");
        return edge.resolve(key);
    }

    public static function value(key:Int):String {
        return resolve(new InterfaceFallibleEdgeImpl(), key);
    }
}
#else
class InterfaceFallibleOps {}
#end
