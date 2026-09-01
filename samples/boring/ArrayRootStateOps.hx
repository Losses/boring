package boring;

import std.ReadOnlyArray;

enum ArrayRootKind {
	Plain;
	Weighted(value:Int);
}

class ArrayRootStateOps {
	public function new() {}

	public static final readOnlyInts:ReadOnlyArray<Int> = [10, 20, 30];
	public static final mutableInts:Array<Int> = [40, 50];
	public static final words:Array<String> = ["alpha", "beta"];
	public static final marker:Int = 7;
	public static final mixed:Array<ArrayRootKind> = [ArrayRootKind.Weighted(marker), ArrayRootKind.Plain];
	public static final nested:Array<Array<Int>> = [[1, 2], [3, 4]];

	public static function readOnlyLength():Int return readOnlyInts.length;

	public static function readOnlyElement(index:Int):Int return readOnlyInts[index];

	public static function mutableLength():Int return mutableInts.length;

	public static function mutableElement(index:Int):Int return mutableInts[index];

	public static function wordsLength():Int return words.length;

	public static function word(index:Int):String return words[index];

	public static function mixedLength():Int return mixed.length;

	public static function mixedIsWeighted():Bool {
		final kind = mixed[0];
		return switch (kind) {
			case Plain: false;
			case Weighted(_): true;
		};
	}

	public static function mixedWeight():Int {
		final kind = mixed[0];
		return switch (kind) {
			case Plain: 0;
			case Weighted(value): value;
		};
	}

	public static function nestedLength():Int return nested.length;

	public static function nestedInnerLength(index:Int):Int return nested[index].length;

	public static function nestedElement(outer:Int, inner:Int):Int return nested[outer][inner];
}
