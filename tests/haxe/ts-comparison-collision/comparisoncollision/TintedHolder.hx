package comparisoncollision;

/**
    Plain class with no comparator. Two stored fields reference the two
    same-named Color enums from different modules, so the generated file
    imports one short name twice and must bind both imports under module
    identity aliases. The accessors construct every value this harness
    reads; the harness reads the generated fields on these accessors only.
**/
class TintedHolder {
    public final left:comparisoncollision.first.Color;
    public final right:comparisoncollision.second.Color;

    public function new(left:comparisoncollision.first.Color, right:comparisoncollision.second.Color) {
        this.left = left;
        this.right = right;
    }

    public static function tintedCrimsonNavy():TintedHolder
        return new TintedHolder(comparisoncollision.first.Color.Crimson(1), comparisoncollision.second.Color.Navy(2));

    public static function tintedNavyCrimson():TintedHolder
        return new TintedHolder(comparisoncollision.first.Color.Navy(4), comparisoncollision.second.Color.Crimson(3));
}
