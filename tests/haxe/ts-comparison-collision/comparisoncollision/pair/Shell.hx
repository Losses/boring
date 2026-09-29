package comparisoncollision.pair;

/**
    Stored fields reference both nested Pair declarations, and one method
    calls the static wrap on the second module's Pair. The generated file
    imports two Pair symbols plus two wrap functions; every static
    reference and every wrap call must use the module identity alias of
    its own module.
**/
@:dataClass
class Shell {
    public final left:comparisoncollision.pair.other.Pair;
    public final right:comparisoncollision.pair.other2.Pair;

    public function new(left:comparisoncollision.pair.other.Pair, right:comparisoncollision.pair.other2.Pair) {
        this.left = left;
        this.right = right;
    }

    public static function wrapped(value:Int):Shell
        return new Shell(new comparisoncollision.pair.other.Pair(value), comparisoncollision.pair.other2.Pair.wrap(value));
}
