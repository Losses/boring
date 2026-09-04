package boring;

/**
 * Word character membership table using compile-time expanded range pairs
 * (docs/specs/features/20-compile-time-data-tables.md).
 */
@:build(DataTables.rangesField("samples/data/synthetic-word-ranges.txt", "RANGES"))
class WordCharacterTable {
    public static function contains(codePoint:Int):Bool {
        var low = 0;
        var high = Std.int(RANGES.length / 2);
        while (low < high) {
            final mid = (low + high) >> 1;
            final start = RANGES[mid * 2];
            final end = RANGES[mid * 2 + 1];
            if (codePoint < start) {
                high = mid;
            } else if (codePoint > end) {
                low = mid + 1;
            } else {
                return true;
            }
        }
        return false;
    }
}
