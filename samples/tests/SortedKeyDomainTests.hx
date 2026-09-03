package tests;

import boring.ClusterTags;
import boring.ScriptNames;
import boring.SortedDataClassKeysOps;
import std.SortedMap;
import std.SortedSet;
import std.Test;

/**
 * Tests for String and structure key domains in std.SortedMap and std.SortedSet
 * (docs/specs/stdlib/07-sorted-keyed-tables.md).
 */
class SortedKeyDomainTests {
	@:test("String keys UTF-16 code unit ordering with astral and high BMP")
	public static function testStringKeyOrder():Void {
		final expected = "ASCII=1; \u{D7FF}=2; \u{10000}=3; \u{10FFFF}=4; \u{E000}=5; \u{FFFF}=6";
		Test.equals(expected, ScriptNames.describeOrder(), "String key traversal matches UTF-16 code unit order");
	}

	@:test("String key lookup hits and misses")
	public static function testStringKeyLookup():Void {
		Test.equals(1, ScriptNames.codeOf("ASCII"), "ASCII hit");
		Test.equals(2, ScriptNames.codeOf("\u{D7FF}"), "D7FF hit");
		Test.equals(3, ScriptNames.codeOf("\u{10000}"), "10000 hit");
		Test.equals(4, ScriptNames.codeOf("\u{10FFFF}"), "10FFFF hit");
		Test.equals(5, ScriptNames.codeOf("\u{E000}"), "E000 hit");
		Test.equals(6, ScriptNames.codeOf("\u{FFFF}"), "FFFF hit");
		Test.equals(null, ScriptNames.codeOf("MISSING"), "unmapped ASCII key miss");
		Test.equals(null, ScriptNames.codeOf("\u{10001}"), "unmapped astral key miss");
	}

	@:test("Structure key lexicographic ordering across field types")
	public static function testStructureKeyOrder():Void {
		final expected = "alpha:10:1:F=500; alpha:10:1:T=400; alpha:10:3:T=300; alpha:20:2:F=200; beta:10:1:T=100";
		Test.equals(expected, ClusterTags.describeOrder(), "Structure key traversal matches field declaration order");
	}

	@:test("DataClass array and nullable key evidence")
	public static function testDataClassKeyEvidence():Void {
		Test.equals("ab;dc;shortlong", SortedDataClassKeysOps.arrayMutations(), "array element and prefix ordering");
		Test.equals("null;value", SortedDataClassKeysOps.nullableMutation(), "null sorts before non-null");
	}

	@:test("DataClass generated entries cover nested enum and arrays")
	public static function testDataClassGeneratedEntries():Void {
		Test.equals("a,b;close,open;nested-first,nested", SortedDataClassKeysOps.read(), "dataClass maps read in key order");
	}

	@:test("Structure key lookup hits and misses")
	public static function testStructureKeyLookup():Void {
		final hitTag:ClusterTag = {name: "alpha", score: 10, sub: {priority: 1}, active: true};
		final missTag:ClusterTag = {name: "alpha", score: 10, sub: {priority: 99}, active: true};
		Test.equals(400, ClusterTags.tagScore(hitTag), "existing structure key hit");
		Test.equals(null, ClusterTags.tagScore(missTag), "unmapped structure key miss");
	}

	@:test("Structure key SortedMap duplicate key last-put-wins")
	public static function testStructureMapLastWins():Void {
		final b:SortedMapBuilder<ClusterTag, String> = SortedMap.builder();
		final tagA:ClusterTag = {name: "tag", score: 1, sub: {priority: 10}, active: true};
		final tagB:ClusterTag = {name: "tag", score: 1, sub: {priority: 10}, active: true};
		b.put(tagA, "first");
		b.put(tagB, "second");

		final map = b.build();
		Test.equals(1, map.size(), "map size after duplicate structure key replacement");
		Test.equals("second", map.get(tagA), "last-put-wins value returned");
	}

	@:test("Structure key SortedSet deduplication and ascending ordering")
	public static function testStructureSetOperations():Void {
		final expected = "alpha:10:1:F; alpha:20:2:F; beta:10:1:T";
		Test.equals(expected, ClusterTags.describeSetOrder(), "SortedSet deduplicated elements match expected order");

		final set = ClusterTags.createSet();
		Test.equals(3, set.size(), "set size after deduplication");
		Test.equals(true, set.has({name: "beta", score: 10, sub: {priority: 1}, active: true}), "has existing element");
		Test.equals(false, set.has({name: "beta", score: 10, sub: {priority: 1}, active: false}), "has non-existing element");
	}
}
