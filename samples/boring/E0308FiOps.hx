package boring;

/** Reproductions for fallible-closure and owned-receiver boundaries. */
class E0308FiOps {
    public function new() {}

    public static function localBool():Bool {
        final check = function():Bool return true;
        return check();
    }

    public function returnOwned():E0308FiOps {
        return this;
    }

    public static function optionalFloat(value:Null<Float>):Float {
        return value == null ? 0.0 : value;
    }
}
