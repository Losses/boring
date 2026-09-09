package boring;

/** Reproductions for fallible-closure and owned-receiver boundaries. */
class E0308FiOps {
    public function new() {}

    public static function localBool():Bool {
        final check = function():Bool return true;
        return check();
    }
}
