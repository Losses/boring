package tests;

import std.Test;

class HandWrittenLoopPositionTests {
	@:test("hand-written accumulation loop remains valid at direct position")
	public static function directLoop():Void {
		Test.equals([2, 3, 4], HandWrittenLoopPositionSupport.accumulate([1, 2, 3]));
	}

	@:test("hand-written accumulation loop remains valid in if")
	public static function loopInIf():Void {
		Test.equals([2, 3, 4], HandWrittenLoopPositionSupport.nestedIf([1, 2, 3]));
	}

	@:test("hand-written accumulation loop remains valid in while")
	public static function loopInWhile():Void {
		Test.equals([2, 3, 4], HandWrittenLoopPositionSupport.nestedWhile([1, 2, 3]));
	}

	@:test("nested hand-written loop does not synthesize a closure")
	public static function nestedLoop():Void {
		Test.equals([2, 3, 4, 2, 3, 4], HandWrittenLoopPositionSupport.outerLoop([1, 2, 3]));
	}
}
