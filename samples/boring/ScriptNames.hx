package boring;

import std.SortedMap;

/**
 * Sample demonstrating std.SortedMap with String keys (docs/specs/stdlib/07-sorted-keyed-tables.md).
 * Keys are ordered by UTF-16 code unit sequence across all targets.
 */
class ScriptNames {
    static function createTable():SortedMap<String, Int> {
        final b:SortedMapBuilder<String, Int> = SortedMap.builder();
        b.put("\u{FFFF}", 6);
        b.put("\u{10000}", 3);
        b.put("ASCII", 1);
        b.put("\u{E000}", 5);
        b.put("\u{D7FF}", 2);
        b.put("\u{10FFFF}", 4);
        return b.build();
    }

    public static function codeOf(name:String):Null<Int> {
        final table = createTable();
        return table.get(name);
    }

    public static function describeOrder():String {
        final table = createTable();
        final parts:Array<String> = [];
        final count = table.size();
        for (i in 0...count) {
            parts.push(table.keyAt(i) + "=" + table.valueAt(i));
        }
        return parts.join("; ");
    }
}
