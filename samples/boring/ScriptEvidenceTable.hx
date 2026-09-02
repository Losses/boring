package boring;

/**
 * Character classification table using compile-time expanded range triples
 * (docs/specs/features/20-compile-time-data-tables.md).
 */
@:build(DataTables.rangesField("samples/data/synthetic-script-ranges.txt", "RANGES"))
class ScriptEvidenceTable {
	public static function classify(codePoint:Int):Int {
		var low = 0;
		var high = Std.int(RANGES.length / 3);
		while (low < high) {
			final mid = (low + high) >> 1;
			final start = RANGES[mid * 3];
			final end = RANGES[mid * 3 + 1];
			if (codePoint < start) {
				high = mid;
			} else if (codePoint > end) {
				low = mid + 1;
			} else {
				return RANGES[mid * 3 + 2];
			}
		}
		return 0;
	}
}
