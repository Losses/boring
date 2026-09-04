package tests;

import std.Test;

class HandWrittenLoopPositionTests {
	@:test("hand-written accumulation loop remains valid at direct position")
	public static function directLoop():Void {
		Test.equals([2, 3, 4], accumulate([1, 2, 3]));
	}

	@:test("hand-written accumulation loop remains valid in if")
	public static function loopInIf():Void {
		Test.equals([2, 3, 4], nestedIf([1, 2, 3]));
	}

	@:test("hand-written accumulation loop remains valid in while")
	public static function loopInWhile():Void {
		Test.equals([2, 3, 4], nestedWhile([1, 2, 3]));
	}

	@:test("nested hand-written loop does not synthesize a closure")
	public static function nestedLoop():Void {
		Test.equals([2, 3, 4, 2, 3, 4], outerLoop([1, 2, 3]));
	}

	static function accumulate(values:Array<Int>):Array<Int> {
		final result = new Array<Int>();
		for (index in 0...values.length) result.push(values[index] + 1);
		return result;
	}

	static function nestedIf(values:Array<Int>):Array<Int> {
		final result = new Array<Int>();
		if (values.length > 0) {
			final inner = new Array<Int>();
			for (index in 0...values.length) inner.push(values[index] + 1);
			for (value in inner) result.push(value);
		}
		return result;
	}

	static function nestedWhile(values:Array<Int>):Array<Int> {
		final result = new Array<Int>();
		var pass = 0;
		while (pass < 1) {
			final inner = new Array<Int>();
			for (index in 0...values.length) inner.push(values[index] + 1);
			for (value in inner) result.push(value);
			pass++;
		}
		return result;
	}

	static function outerLoop(values:Array<Int>):Array<Int> {
		final result = new Array<Int>();
		for (pass in 0...2) {
			final inner = new Array<Int>();
			for (index in 0...values.length) inner.push(values[index] + 1);
			for (value in inner) result.push(value);
		}
		return result;
	}
}
