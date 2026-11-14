package kotlinpack;

import std.SortedMap;

/**
    The nullable numeric argument shape: a has/get ternary is passed to a
    parameter that carries a registered default. The ternary's Kotlin type is
    still nullable, so the argument boundary needs its elvis even though the
    presence model reads the get as present.
**/
class NullableArgFixture {
    /** The boxed top for one cluster, with the spread read from the map. */
    public static function build(spreads:SortedMap<Int, Float>, k:Int):Float {
        return new Box(0.0, 0.0, spreads.has(k) ? spreads.get(k) : 0).top;
    }
}

/** One decision record whose spread parameter carries a default. */
class Box {
    public final top:Float;
    public final spread:Float;

    public function new(top:Float, delta:Float, ?spread:Float = 0.0) {
        this.top = top;
        this.spread = spread;
    }
}
