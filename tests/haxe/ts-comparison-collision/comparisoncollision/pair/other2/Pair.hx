package comparisoncollision.pair.other2;

/**
    A second Pair declaration whose short name equals both the shell
    record's own name and the first nested Pair. The static wrap makes the
    generated file resolve a static reference on the imported class, the
    path the emitter renders through its own value site.
**/
class Pair {
    public final value:Int;

    public function new(value:Int) {
        this.value = value;
    }

    public static function wrap(value:Int):Pair
        return new Pair(value);
}
