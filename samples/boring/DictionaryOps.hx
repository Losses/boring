package boring;

import std.Dictionary;

/**
 * Business operations over std.Dictionary, exercising the complete
 * mutable hash-table API (docs/specs/stdlib/19).
 */
class DictionaryOps {
    /** Build a dictionary and read a present key. */
    public static function buildGet():Int {
        final d:Dictionary<String, Int> = new Dictionary();
        d.set("k", 42);
        return d.get("k");
    }

    /** get-or-fallback through an explicit null test. */
    public static function getOr(d:Dictionary<String, Int>, key:String, fallback:Int):Int {
        final v = d.get(key);
        return v == null ? fallback : v;
    }

    /** A later set with an equal key replaces the earlier value. */
    public static function overwrite():Int {
        final d:Dictionary<String, Int> = new Dictionary();
        d.set("k", 1);
        d.set("k", 2);
        return d.get("k");
    }

    /** remove reports whether the key was present; absent removes are false. */
    public static function removeKey():Bool {
        final d:Dictionary<String, Int> = new Dictionary();
        d.set("k", 1);
        final removed = d.remove("k");
        final removedAgain = d.remove("k");
        return removed && !removedAgain;
    }

    /** clear empties the table; a re-insert after clear reads back. */
    public static function clearAndReinsert():Int {
        final d:Dictionary<String, Int> = new Dictionary();
        d.set("a", 1);
        d.set("b", 2);
        d.clear();
        d.set("c", 3);
        return d.get("c");
    }
}
