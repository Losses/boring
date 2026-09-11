package boring;

#if swift_output
/**
    Identity equality on an interface-typed value: Haxe interfaces lower
    to Swift protocols, and `===`/`!==` require a class-constrained
    operand, so the existential side is cast to `AnyObject`.
*/
interface IdentityShape {
    public function label():String;
}

class IdentityLeaf implements IdentityShape {
    public static final instance:IdentityLeaf = new IdentityLeaf();

    private function new() {}

    public function label():String
        return "leaf";
}

class IdentityNode implements IdentityShape {
    public final n:Int;

    public function new(n:Int)
        this.n = n;

    public function label():String
        return "node";
}

class InterfaceIdentityOps {
    public static function same(a:IdentityShape, b:IdentityShape):Bool
        return a == b;

    public static function different(a:IdentityShape, b:IdentityShape):Bool
        return a != b;

    public static function isSingleton(a:IdentityShape):Bool
        return IdentityLeaf.instance == a;

    public static function leaf():IdentityLeaf
        return IdentityLeaf.instance;

    public static function node(n:Int):IdentityShape
        return new IdentityNode(n);
}
#else
class InterfaceIdentityOps {}
#end
