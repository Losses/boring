package boring;

#if swift_output
import runtime.SortedTable;
import std.SortedMap;

/**
    Sorted table builders carry a value parameter Swift cannot infer from
    the comparator alone, so a local declaration pins the full type.
*/
class TableBuilderInferOps {
    public static function sum():Int {
        final b = SortedTable.mapBuilder(SortedTable.compareStrings);
        b.put("a", 1);
        b.put("b", 2);
        final m = b.build();
        var total = 0;
        var i = 0;
        while (i < m.size()) {
            total += m.valueAt(i);
            i += 1;
        }
        return total;
    }

    public static function emptySize():Int {
        final z:SortedMap<String, Int> = SortedMap.builder().build();
        return z.size();
    }
}
#else
class TableBuilderInferOps {}
#end
