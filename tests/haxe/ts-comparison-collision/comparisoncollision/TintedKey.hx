package comparisoncollision;

/**
    Cross-module enum case. The two enum declarations share the short name
    Color and declare their constructors in opposite order, so a generated
    comparator that keeps only the short name imports two Color symbols into
    one scope or reads the wrong declaration order. The accessors construct
    every value this harness reads; the harness calls the generated
    comparator on these accessors only.
**/
@:dataClass
class TintedKey {
    public final left:comparisoncollision.first.Color;
    public final right:comparisoncollision.second.Color;

    public function new(left:comparisoncollision.first.Color, right:comparisoncollision.second.Color) {
        this.left = left;
        this.right = right;
    }

    public static function keyCrimsonNavy():TintedKey
        return new TintedKey(comparisoncollision.first.Color.Crimson(1), comparisoncollision.second.Color.Navy(2));

    public static function keyCrimsonCrimson():TintedKey
        return new TintedKey(comparisoncollision.first.Color.Crimson(1), comparisoncollision.second.Color.Crimson(3));

    public static function keyNavyCrimson():TintedKey
        return new TintedKey(comparisoncollision.first.Color.Navy(4), comparisoncollision.second.Color.Crimson(3));
}
