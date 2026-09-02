package tests;

import boring.DeferredLocalsOps;
import std.Test;

class DeferredLocalsTests {
	@:test("deferred locals initialize along control-flow paths")
	public static function testDeferredLocals():Void {
		Test.equals(2, DeferredLocalsOps.tierOf(4), "if branch");
		Test.equals(1, DeferredLocalsOps.tierOf(1), "else branch");
		Test.equals(8, DeferredLocalsOps.nullableValue(8), "nullable branch");
		Test.equals(0, DeferredLocalsOps.nullableValue(null), "null branch");
		Test.equals(2, DeferredLocalsOps.loopValue(3), "loop assignment");
	}
}
