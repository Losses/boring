package boring;

#if swift_output
/**
    A heterogeneous array literal of concrete interface implementations.
    Haxe types the literal as the interface array, but a bare Swift array
    literal infers `[Any]` and loses the protocol members; the generator
    must carry the interface element type onto the literal.
*/
interface TaggedEntry {
    function tag():String;
}

class TaggedAlpha implements TaggedEntry {
    public static final instance:TaggedAlpha = new TaggedAlpha();

    private function new() {}

    public function tag():String
        return "alpha";
}

class TaggedBeta implements TaggedEntry {
    public static final instance:TaggedBeta = new TaggedBeta();

    private function new() {}

    public function tag():String
        return "beta";
}

class InterfaceArrayLiteralOps {
    public static function tags():Array<String> {
        final entries = [TaggedAlpha.instance, TaggedBeta.instance];
        return [for (entry in entries) entry.tag()];
    }
}
#else
class InterfaceArrayLiteralOps {}
#end
