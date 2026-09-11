package boring;

@:build(DataTables.rangesField("samples/data/synthetic-script-ranges.txt", "RANGES"))
class DivTableOps {
    public static function lookup(codePoint:Int):Int {
        var low:Int = 0;
        var high:Int = Std.int(RANGES.length / 3) - 1;
        while (low <= high) {
            final mid:Int = (low + high) >> 1;
            final base:Int = mid * 3;
            final start:Int = RANGES[base];
            if (codePoint < start) {
                high = mid - 1;
            } else {
                return RANGES[base];
            }
        }
        return 0;
    }
}
