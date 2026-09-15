package boring;

#if rust_output
import runtime.SortedTable;

/**
    A resident sorted-table builder infers its key and value types at the
    comparator. The direct call must bind them explicitly so the comparator
    closure matches the builder's parameters.
*/
class ResidentBuilderInferOps {
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
}
#else
class ResidentBuilderInferOps {}
#end
