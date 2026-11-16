package trees;

/** The shipping-tree referencer: compiling this root moves Shared back into
    the main unit while the test root stays in the same output trees. */
class Entry {
    public static function describe():String {
        return new Shared("entry").describe();
    }
}
