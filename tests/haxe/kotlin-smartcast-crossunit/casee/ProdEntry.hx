package casee;

/**
    Non-test production entry: references the casee data classes so they stay
    in the main compilation unit under the test-support closure (a production
    data class is referenced by production code, not only by tests).
**/
class ProdEntry {
    public static function make(x:Float):Holder {
        return new Holder(new Vec(x));
    }

    public static function magnitude(v:Vec):Float {
        return Support.useVec(v);
    }
}
