package tests;

import boring.PipelineOps;
import boring.PipelineOps.Item;
import std.Test;

/**
 * Tests for functional collection pipeline expansion (docs/specs/features/21-functional-idiom-expansion.md).
 * Covers map, filter, forEach, associate, and sortedBy with shadowing, mint capture, and nested loops.
 */
class PipelineTests {
	@:test("map transforms elements and pre-allocates fill")
	public static function testMap():Void {
		var empty = new Array<Item>();
		var emptyDoubled = PipelineOps.doubleScores(empty);
		Test.equals(0, emptyDoubled.length, "empty map length");

		var items:Array<Item> = [
			{id: 1, name: "Alice", score: 10},
			{id: 2, name: "Bob", score: 25},
			{id: 3, name: "Charlie", score: 40}
		];
		var doubled = PipelineOps.doubleScores(items);
		Test.equals(3, doubled.length, "doubled length");
		Test.equals(20, doubled[0], "doubled 0");
		Test.equals(50, doubled[1], "doubled 1");
		Test.equals(80, doubled[2], "doubled 2");
	}

	@:test("lambda parameter shadows outer local variable")
	public static function testShadowing():Void {
		var items:Array<Item> = [
			{id: 1, name: "Alice", score: 10},
			{id: 2, name: "Bob", score: 25}
		];
		var shadowed = PipelineOps.shadowingMap(items);
		Test.equals(2, shadowed.length, "shadowed length");
		Test.equals(11, shadowed[0], "shadowed 0");
		Test.equals(27, shadowed[1], "shadowed 1");
	}

	@:test("filter keeps matching elements in compact push loop")
	public static function testFilter():Void {
		var empty = new Array<Item>();
		var emptyFiltered = PipelineOps.filterHighScore(empty, 20);
		Test.equals(0, emptyFiltered.length, "empty filter length");

		var items:Array<Item> = [
			{id: 1, name: "Alice", score: 10},
			{id: 2, name: "Bob", score: 25},
			{id: 3, name: "Charlie", score: 40}
		];
		var filtered = PipelineOps.filterHighScore(items, 25);
		Test.equals(2, filtered.length, "filtered length");
		Test.equals(2, filtered[0].id, "filtered item 0");
		Test.equals(3, filtered[1].id, "filtered item 1");
	}

	@:test("mint hygiene protects user locals with pipeline_ prefix")
	public static function testMintCapture():Void {
		var items:Array<Item> = [
			{id: 1, name: "Alice", score: 10},
			{id: 2, name: "Bob", score: 25},
			{id: 3, name: "Charlie", score: 40}
		];
		var result = PipelineOps.mintCaptureFilter(items);
		Test.equals(2, result.length, "mint capture filter length");
		Test.equals(2, result[0].id, "mint capture item 0");
		Test.equals(3, result[1].id, "mint capture item 1");
	}

	@:test("forEach traverses elements in statement position")
	public static function testForEach():Void {
		var empty = new Array<Item>();
		Test.equals(0, PipelineOps.sumScores(empty), "empty sum");

		var items:Array<Item> = [
			{id: 1, name: "Alice", score: 10},
			{id: 2, name: "Bob", score: 25},
			{id: 3, name: "Charlie", score: 40}
		];
		Test.equals(75, PipelineOps.sumScores(items), "sum scores");
	}

	@:test("associate builds sorted map with last-wins on duplicate keys")
	public static function testAssociate():Void {
		var empty = new Array<Item>();
		var emptyMap = PipelineOps.associateById(empty);
		Test.equals(0, emptyMap.size(), "empty map size");

		var items:Array<Item> = [
			{id: 3, name: "Charlie", score: 40},
			{id: 1, name: "Alice", score: 10},
			{id: 2, name: "Bob", score: 25}
		];
		var map = PipelineOps.associateById(items);
		Test.equals(3, map.size(), "map size");
		Test.equals("Alice", map.get(1), "get 1");
		Test.equals("Bob", map.get(2), "get 2");
		Test.equals("Charlie", map.get(3), "get 3");

		var itemsWithDup:Array<Item> = [
			{id: 1, name: "First", score: 10},
			{id: 1, name: "Updated", score: 20}
		];
		var mapDup = PipelineOps.associateById(itemsWithDup);
		Test.equals(1, mapDup.size(), "dup map size");
		Test.equals("Updated", mapDup.get(1), "dup overwrite");
	}

	@:test("sortedBy sorts ascending with platform stability on equal keys")
	public static function testSortedBy():Void {
		var empty = new Array<Item>();
		var emptySorted = PipelineOps.sortByScore(empty);
		Test.equals(0, emptySorted.length, "empty sorted length");

		var single:Array<Item> = [{id: 1, name: "Solo", score: 100}];
		var singleSorted = PipelineOps.sortByScore(single);
		Test.equals(1, singleSorted.length, "single sorted length");
		Test.equals(100, singleSorted[0].score, "single sorted score");

		var items:Array<Item> = [
			{id: 1, name: "Charlie", score: 40},
			{id: 2, name: "Alice", score: 10},
			{id: 3, name: "Bob", score: 25}
		];
		var sorted = PipelineOps.sortByScore(items);
		Test.equals(3, sorted.length, "sorted length");
		Test.equals(10, sorted[0].score, "sorted 0");
		Test.equals(25, sorted[1].score, "sorted 1");
		Test.equals(40, sorted[2].score, "sorted 2");

		var itemsWithEqualKeys:Array<Item> = [
			{id: 1, name: "First20", score: 20},
			{id: 2, name: "Ten", score: 10},
			{id: 3, name: "Second20", score: 20},
			{id: 4, name: "Third20", score: 20}
		];
		var sortedStable = PipelineOps.sortByScore(itemsWithEqualKeys);
		Test.equals(4, sortedStable.length, "stable length");
		Test.equals(2, sortedStable[0].id, "stable item 0 (Ten)");
		Test.equals(1, sortedStable[1].id, "stable item 1 (First20)");
		Test.equals(3, sortedStable[2].id, "stable item 2 (Second20)");
		Test.equals(4, sortedStable[3].id, "stable item 3 (Third20)");
	}

	@:test("chained pipeline methods expand in source order")
	public static function testChained():Void {
		var nums = [1, 2, 3, 4, 5, 6];
		var result = PipelineOps.chainedFilterMap(nums);
		Test.equals(3, result.length, "chained length");
		Test.equals(20, result[0], "chained 0");
		Test.equals(40, result[1], "chained 1");
		Test.equals(60, result[2], "chained 2");

		var items:Array<Item> = [
			{id: 1, name: "Alice", score: 10},
			{id: 2, name: "Bob", score: 25},
			{id: 3, name: "Charlie", score: 40}
		];
		var names = PipelineOps.highScorerNames(items, 20);
		Test.equals(2, names.length, "high scorer names length");
		Test.equals("Bob", names[0], "name 0");
		Test.equals("Charlie", names[1], "name 1");
	}

	@:test("nested loops rebuild per-iteration pipeline temporaries")
	public static function testNestedLoop():Void {
		var matrix:Array<Array<Int>> = [
			[1, 2, 3],
			[4, 5, 6]
		];
		var transformed = PipelineOps.nestedLoopMap(matrix, 100);
		Test.equals(2, transformed.length, "matrix length");
		Test.equals(3, transformed[0].length, "row 0 length");
		Test.equals(101, transformed[0][0], "row 0 elem 0");
		Test.equals(102, transformed[0][1], "row 0 elem 1");
		Test.equals(103, transformed[0][2], "row 0 elem 2");
		Test.equals(104, transformed[1][0], "row 1 elem 0");
		Test.equals(105, transformed[1][1], "row 1 elem 1");
		Test.equals(106, transformed[1][2], "row 1 elem 2");
	}

	@:test("any checks predicate matches with early exit and returns false for empty")
	public static function testAny():Void {
		var empty = new Array<Item>();
		Test.equals(false, PipelineOps.hasHighScore(empty, 50), "empty any is false");

		var items:Array<Item> = [
			{id: 1, name: "Alice", score: 10},
			{id: 2, name: "Bob", score: 25},
			{id: 3, name: "Charlie", score: 40}
		];
		Test.equals(false, PipelineOps.hasHighScore(items, 50), "no match any is false");
		Test.equals(true, PipelineOps.hasHighScore(items, 25), "match any is true");
	}

	@:test("all checks predicate matches all with early exit and returns true for empty")
	public static function testAll():Void {
		var empty = new Array<Item>();
		Test.equals(true, PipelineOps.allAboveScore(empty, 50), "empty all is true");

		var items:Array<Item> = [
			{id: 1, name: "Alice", score: 10},
			{id: 2, name: "Bob", score: 25},
			{id: 3, name: "Charlie", score: 40}
		];
		Test.equals(false, PipelineOps.allAboveScore(items, 20), "mixed all is false");
		Test.equals(true, PipelineOps.allAboveScore(items, 5), "all match is true");
	}

	@:test("firstOrNull finds first matching element or returns null")
	public static function testFirstOrNull():Void {
		var empty = new Array<Item>();
		var emptyResult = PipelineOps.findFirstHighScore(empty, 20);
		Test.equals(true, emptyResult == null, "empty firstOrNull is null");

		var items:Array<Item> = [
			{id: 1, name: "Alice", score: 10},
			{id: 2, name: "Bob", score: 25},
			{id: 3, name: "Charlie", score: 40}
		];
		var noMatch = PipelineOps.findFirstHighScore(items, 50);
		Test.equals(true, noMatch == null, "no match firstOrNull is null");

		var matchedItem = PipelineOps.findFirstHighScore(items, 20);
		Test.equals(true, matchedItem != null, "match is not null");
		if (matchedItem != null) {
			Test.equals(2, matchedItem.id, "first matched item id");
			Test.equals("Bob", matchedItem.name, "first matched item name");
		}
	}

	@:test("sumOfInt sums integer selector values and returns 0 for empty")
	public static function testSumOfInt():Void {
		var empty = new Array<Item>();
		Test.equals(0, PipelineOps.totalScore(empty), "empty sumOfInt is 0");

		var items:Array<Item> = [
			{id: 1, name: "Alice", score: 10},
			{id: 2, name: "Bob", score: 25},
			{id: 3, name: "Charlie", score: 40}
		];
		Test.equals(75, PipelineOps.totalScore(items), "sumOfInt total");
	}

	@:test("sumOfFloat sums float selector values and returns 0.0 for empty")
	public static function testSumOfFloat():Void {
		var empty = new Array<Item>();
		Test.equals(0.0, PipelineOps.totalWeightedScore(empty, 1.5), "empty sumOfFloat is 0.0");

		var items:Array<Item> = [
			{id: 1, name: "Alice", score: 10},
			{id: 2, name: "Bob", score: 20}
		];
		Test.equals(45.0, PipelineOps.totalWeightedScore(items, 1.5), "sumOfFloat total");
	}

	@:test("mapNotNull filters out null selector results")
	public static function testMapNotNull():Void {
		var empty = new Array<Item>();
		var emptyMapped = PipelineOps.extractValidNames(empty, 20);
		Test.equals(0, emptyMapped.length, "empty mapNotNull length");

		var items:Array<Item> = [
			{id: 1, name: "Alice", score: 10},
			{id: 2, name: "Bob", score: 25},
			{id: 3, name: "Charlie", score: 15},
			{id: 4, name: "Diana", score: 30}
		];
		var mapped = PipelineOps.extractValidNames(items, 20);
		Test.equals(2, mapped.length, "mapNotNull length");
		Test.equals("Bob", mapped[0], "mapNotNull item 0");
		Test.equals("Diana", mapped[1], "mapNotNull item 1");
	}

	@:test("flatMap flattens selector array results")
	public static function testFlatMap():Void {
		var empty = new Array<Item>();
		var emptyResult = PipelineOps.duplicateScores(empty);
		Test.equals(0, emptyResult.length, "empty flatMap length");

		var items:Array<Item> = [
			{id: 1, name: "Zero", score: 0},
			{id: 2, name: "Alice", score: 10},
			{id: 3, name: "Bob", score: 20}
		];
		var result = PipelineOps.duplicateScores(items);
		Test.equals(4, result.length, "flatMap length");
		Test.equals(10, result[0], "flatMap 0");
		Test.equals(20, result[1], "flatMap 1");
		Test.equals(20, result[2], "flatMap 2");
		Test.equals(40, result[3], "flatMap 3");
	}

	@:test("groupBy groups elements into SortedMap with ascending keys and receiver order in buckets")
	public static function testGroupBy():Void {
		var empty = new Array<Item>();
		var emptyGrouped = PipelineOps.groupNamesByScore(empty);
		Test.equals(0, emptyGrouped.size(), "empty groupBy size");

		var items:Array<Item> = [
			{id: 1, name: "Charlie", score: 40},
			{id: 2, name: "Ten", score: 10},
			{id: 3, name: "Bob", score: 25},
			{id: 4, name: "Second25", score: 25}
		];
		var grouped = PipelineOps.groupNamesByScore(items);
		Test.equals(3, grouped.size(), "groupBy size");

		Test.equals(10, grouped.keyAt(0), "key 0 ascending");
		Test.equals(25, grouped.keyAt(1), "key 1 ascending");
		Test.equals(40, grouped.keyAt(2), "key 2 ascending");

		var bucket10 = grouped.valueAt(0);
		Test.equals(1, bucket10.length, "bucket 10 size");
		Test.equals("Ten", bucket10[0], "bucket 10 item 0");

		var bucket25 = grouped.valueAt(1);
		Test.equals(2, bucket25.length, "bucket 25 size");
		Test.equals("Bob", bucket25[0], "bucket 25 item 0 (receiver order)");
		Test.equals("Second25", bucket25[1], "bucket 25 item 1 (receiver order)");

		var bucket40 = grouped.valueAt(2);
		Test.equals(1, bucket40.length, "bucket 40 size");
		Test.equals("Charlie", bucket40[0], "bucket 40 item 0");

		Test.equals(true, grouped.has(25), "has 25");
		Test.equals(false, grouped.has(999), "has 999 is false");
		Test.equals(true, grouped.get(25) != null, "lookup 25 not null");
		Test.equals(true, grouped.get(999) == null, "lookup 999 is null");
	}
}
