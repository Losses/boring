package tests;

import boring.CodePointNames;
import std.SortedMap;
import std.SortedSet;
import std.Test;

/**
 * Tests for std.SortedMap and std.SortedSet (docs/specs/stdlib/07-sorted-keyed-tables.md).
 * Covers builder semantics, duplicate key last-wins, empty tables, binary search, and ordering.
 */
class SortedTableTests {
	@:test("CodePointNames lookup hits and misses")
	public static function testCodePointNamesLookup():Void {
		Test.equals("LINE FEED", CodePointNames.nameOf(0x000A), "LF hit");
		Test.equals("SPACE", CodePointNames.nameOf(0x0020), "Space hit");
		Test.equals("DIGIT ZERO", CodePointNames.nameOf(0x0030), "Digit 0 hit");
		Test.equals("LATIN CAPITAL LETTER A", CodePointNames.nameOf(0x0041), "Letter A hit");
		Test.equals("LATIN CAPITAL LETTER B", CodePointNames.nameOf(0x0042), "Letter B hit");
		Test.equals(null, CodePointNames.nameOf(0x0000), "Null character miss");
		Test.equals(null, CodePointNames.nameOf(0x9999), "Unmapped code point miss");
	}

	@:test("CodePointNames ascending traversal order")
	public static function testCodePointNamesOrder():Void {
		final expected = "10=LINE FEED; 32=SPACE; 48=DIGIT ZERO; 65=LATIN CAPITAL LETTER A; 66=LATIN CAPITAL LETTER B";
		Test.equals(expected, CodePointNames.describeOrder(), "ascending traversal matches expected order");
	}

	@:test("SortedMap duplicate key last-put-wins semantics")
	public static function testMapDuplicateKeys():Void {
		final b:SortedMapBuilder<Int, String> = SortedMap.builder();
		b.put(100, "hundred-first");
		b.put(50, "fifty");
		b.put(100, "hundred-final");
		b.put(20, "twenty");
		b.put(50, "fifty-final");

		final map = b.build();
		Test.equals(3, map.size(), "size after duplicate replacements");
		Test.equals("twenty", map.get(20), "key 20 value");
		Test.equals("fifty-final", map.get(50), "key 50 replaced value");
		Test.equals("hundred-final", map.get(100), "key 100 replaced value");
		Test.equals(null, map.get(99), "unmapped key returns null");

		Test.equals(true, map.has(20), "has 20");
		Test.equals(true, map.has(50), "has 50");
		Test.equals(true, map.has(100), "has 100");
		Test.equals(false, map.has(10), "has 10 is false");

		Test.equals(20, map.keyAt(0), "key at 0");
		Test.equals("twenty", map.valueAt(0), "value at 0");
		Test.equals(50, map.keyAt(1), "key at 1");
		Test.equals("fifty-final", map.valueAt(1), "value at 1");
		Test.equals(100, map.keyAt(2), "key at 2");
		Test.equals("hundred-final", map.valueAt(2), "value at 2");
	}

	@:test("SortedMap empty builder produces empty map")
	public static function testEmptyMap():Void {
		final b:SortedMapBuilder<Int, String> = SortedMap.builder();
		final map = b.build();
		Test.equals(0, map.size(), "empty map size is 0");
		Test.equals(false, map.has(1), "empty map has returns false");
		Test.equals(null, map.get(1), "empty map get returns null");
	}

	@:test("SortedSet duplicate key deduplication and ascending ordering")
	public static function testSortedSetOperations():Void {
		final b = SortedSet.builder();
		b.put(300);
		b.put(100);
		b.put(300);
		b.put(200);
		b.put(100);

		final set = b.build();
		Test.equals(3, set.size(), "set size after duplicates");
		Test.equals(true, set.has(100), "has 100");
		Test.equals(true, set.has(200), "has 200");
		Test.equals(true, set.has(300), "has 300");
		Test.equals(false, set.has(150), "has 150 is false");
		Test.equals(false, set.has(400), "has 400 is false");

		Test.equals(100, set.at(0), "element 0");
		Test.equals(200, set.at(1), "element 1");
		Test.equals(300, set.at(2), "element 2");
	}

	@:test("SortedSet empty builder produces empty set")
	public static function testEmptySet():Void {
		final b = SortedSet.builder();
		final set = b.build();
		Test.equals(0, set.size(), "empty set size is 0");
		Test.equals(false, set.has(42), "empty set has returns false");
	}
}
