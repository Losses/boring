package tests;

import std.Test;

class BlockScopeUnrollTests {

	@:test("literal loop unrolls into scoped blocks")
	public static function literalLoopScopes():Void {
		var total = 0;
		for (step in [1, 3, 7, 31]) {
			final doubled = step * 2;
			total += doubled;
		}
		Test.equals(84, total);
	}

	@:test("sequential literal loops reuse names")
	public static function sequentialLoops():Void {
		var total = 0;
		for (v in [1, 2]) { final tag = v; total += tag; }
		for (v in [3, 4]) { final tag = v; total += tag; }
		Test.equals(10, total);
	}

	@:test("return inside unrolled body")
	public static function returnFromSegment():Void {
		Test.equals(7, BlockScopeUnrollSupport.firstAboveFive());
	}

	@:test("break and continue keep the counted loop path")
	public static function breakContinuePath():Void {
		var total = 0;
		for (step in [1, 3, 7, 31]) {
			if (step == 3) continue;
			if (step == 31) break;
			total += step;
		}
		Test.equals(8, total);
	}
}

private class BlockScopeUnrollSupport {
	public static function firstAboveFive():Int {
		for (step in [1, 3, 7, 31]) { if (step > 5) return step; }
		return 0;
	}
}
