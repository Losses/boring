package boring;

import std.HashMap;

/**
 * Business operations over std.HashMap, exercising the complete
 * mutable hash-table API (docs/specs/stdlib/19).
 */
class HashMapOps {
    /** Build a hash map and read a present key. */
    public static function buildGet():Int {
        final d:HashMap<String, Int> = new HashMap();
        d.set("k", 42);
        return d.get("k");
    }

    /** get-or-fallback through an explicit null test. */
    public static function getOr(d:HashMap<String, Int>, key:String, fallback:Int):Int {
        final v = d.get(key);
        return v == null ? fallback : v;
    }

    /** A later set with an equal key replaces the earlier value. */
    public static function overwrite():Int {
        final d:HashMap<String, Int> = new HashMap();
        d.set("k", 1);
        d.set("k", 2);
        return d.get("k");
    }

    /** remove reports whether the key was present; absent removes are false. */
    public static function removeKey():Bool {
        final d:HashMap<String, Int> = new HashMap();
        d.set("k", 1);
        final removed = d.remove("k");
        final removedAgain = d.remove("k");
        return removed && !removedAgain;
    }

    /** clear empties the table; a re-insert after clear reads back. */
    public static function clearAndReinsert():Int {
        final d:HashMap<String, Int> = new HashMap();
        d.set("a", 1);
        d.set("b", 2);
        d.clear();
        d.set("c", 3);
        return d.get("c");
    }

    /** A final HashMap field mutates in place (Swift var, not let). */
    public static function fieldMutate():Int {
        final holder = new DictHolder();
        holder.entries.set("k", 7);
        return holder.entries.get("k");
    }

    /** Array.remove(x) lowers to a splice-based removal in TS. */
    public static function arrayRemove():Bool {
        final a = [1, 2, 3];
        final removed = a.remove(2);
        return removed && a.length == 2;
    }

    /** Std.string on a bare HashMap emits the deterministic "{}" placeholder. */
    public static function directString():String {
        final d:HashMap<String, Int> = new HashMap();
        d.set("a", 1);
        return Std.string(d);
    }

    /** A @:dataClass with a HashMap field prints a stable structured form. */
    public static function dictToString():String {
        final d:HashMap<String, Int> = new HashMap();
        d.set("a", 1);
        d.set("b", 2);
        final r = new DictRecord(d);
        return r.toString();
    }

    /** A @:dataClass key compares structurally, not by reference. */
    public static function structuralKey():Int {
        final d:HashMap<DictKey, Int> = new HashMap();
        d.set(new DictKey(1, "x"), 42);
        return d.get(new DictKey(1, "x"));
    }
}

/** A final HashMap field keeps mutating methods in Swift (var, not let). */
class DictHolder {
    public final entries:HashMap<String, Int>;
    public function new() {
        entries = new HashMap();
    }
}

/** @:dataClass holding a HashMap field (toString structured emission). */
@:dataClass
class DictRecord {
    public final table:HashMap<String, Int>;
    public function new(table:HashMap<String, Int>) {
        this.table = table;
    }
}

/** @:dataClass key used through a HashMap (structural, not reference). */
@:dataClass
class DictKey {
    public final a:Int;
    public final b:String;
    public function new(a:Int, b:String) {
        this.a = a;
        this.b = b;
    }
}
