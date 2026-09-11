package boring;

#if swift_output
/**
    A coalescing default that calls a private static helper of the same
    class. Swift rejects a public default argument value that references a
    private member, so the default moves into the body.
*/
class PrivateDefaultOps {
    public final values:Array<Int>;

    public function new(?values:Array<Int>) {
        this.values = values == null ? emptyValues() : values;
    }

    public function size():Int {
        return this.values.length;
    }

    static function emptyValues():Array<Int> {
        return [];
    }
}
#else
class PrivateDefaultOps {}
#end
