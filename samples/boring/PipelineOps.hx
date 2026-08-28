package boring;

using std.Functional;

typedef Item = {
	final id:Int;
	final name:String;
	final score:Int;
}

typedef ItemKeyVal = {
	final key:Int;
	final value:String;
}

/**
 * Functional collection pipeline samples (docs/specs/features/21-functional-idiom-expansion.md).
 * Covers map, filter, forEach, associate, and sortedBy on Array<T>.
 */
class PipelineOps {
	public static function doubleScores(items:Array<Item>):Array<Int> {
		return items.map(function(item:Item):Int {
			return item.score * 2;
		});
	}

	public static function shadowingMap(items:Array<Item>):Array<Int> {
		var item = 999;
		final mapped = items.map(function(item:Item):Int {
			return item.score + item.id;
		});
		if (item != 999) {
			return [];
		}
		return mapped;
	}

	public static function filterHighScore(items:Array<Item>, threshold:Int):Array<Item> {
		return items.filter(function(item:Item):Bool {
			return item.score >= threshold;
		});
	}

	public static function mintCaptureFilter(items:Array<Item>):Array<Item> {
		var pipeline_threshold = 20;
		return items.filter(function(item:Item):Bool {
			return item.score >= pipeline_threshold;
		});
	}

	public static function sumScores(items:Array<Item>):Int {
		var total = 0;
		items.forEach(function(item:Item):Void {
			total += item.score;
		});
		return total;
	}

	public static function associateById(items:Array<Item>):std.SortedMap<Int, String> {
		return items.associate(function(item:Item):ItemKeyVal {
			return {
				key: item.id,
				value: item.name
			};
		});
	}

	public static function sortByScore(items:Array<Item>):Array<Item> {
		return items.sortedBy(function(item:Item):Int {
			return item.score;
		});
	}

	public static function highScorerNames(items:Array<Item>, minScore:Int):Array<String> {
		final highScorers = items.filter(function(item:Item):Bool {
			return item.score >= minScore;
		});
		return highScorers.map(function(item:Item):String {
			return item.name;
		});
	}

	public static function chainedFilterMap(numbers:Array<Int>):Array<Int> {
		return numbers.filter(function(n:Int):Bool {
			return n % 2 == 0;
		}).map(function(n:Int):Int {
			return n * 10;
		});
	}

	public static function nestedLoopMap(matrix:Array<Array<Int>>, offset:Int):Array<Array<Int>> {
		final result = new Array<Array<Int>>();
		for (r in 0...matrix.length) {
			final row = matrix[r];
			final mappedRow = row.map(function(val:Int):Int {
				return val + offset;
			});
			result.push(mappedRow);
		}
		return result;
	}
}
