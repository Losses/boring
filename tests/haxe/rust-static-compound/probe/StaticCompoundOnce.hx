package probe;

// The required shape: the table is built locally and published in one
// assignment, so a reader sees one complete table and the length never
// changes between the length check and the index read.
class StaticCompoundOnce {
    static var table:Array<Int> = [];

    static function buildTable(k:Int):Array<Int> {
        final built:Array<Int> = [1];
        while (built.length <= k) {
            built.push(built[built.length - 1] * 3);
        }
        return built;
    }

    public static function reset():Void {
        table = [1];
    }

    public static function valueAt(k:Int):Int {
        if (table.length <= k) {
            table = buildTable(k);
        }
        return table[k];
    }
}
