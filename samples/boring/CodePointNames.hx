package boring;

import std.SortedMap;

/**
 * Sample demonstrating std.SortedMap construction and ascending traversal
 * (docs/specs/stdlib/07-sorted-keyed-tables.md).
 */
class CodePointNames {
	static function createTable():SortedMap<Int, String> {
		final b:SortedMapBuilder<Int, String> = SortedMap.builder();
		b.put(0x0041, "LATIN CAPITAL LETTER A");
		b.put(0x0020, "SPACE");
		b.put(0x0042, "LATIN CAPITAL LETTER B");
		b.put(0x000A, "LINE FEED");
		b.put(0x0030, "DIGIT ZERO");
		return b.build();
	}

	public static function nameOf(codePoint:Int):Null<String> {
		final table = createTable();
		return table.get(codePoint);
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
