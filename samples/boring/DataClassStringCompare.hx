package boring;

/**
 * Minimal regression for the Rust target's resident emission: a @:dataClass
 * with a String field generates a comparator that calls the resident
 * runtime.SortedTable (sorted_table_compare_strings), so requiring its type
 * must light the resident's emission gate and emit sorted_table.rs beside the
 * runtime shims.
 */
@:dataClass
class DataClassStringCompare {
    public final label:String;
    public final order:Int;

    public function new(label:String, order:Int) {
        this.label = label;
        this.order = order;
    }
}
