package tests;

import boring.ToStringOps;
import std.Test;

class ToStringTests {
	@:test("an explicit toString method renders and runs on every target")
	public static function explicitToString():Void {
		final label = ToStringOps.makeLabel("body", 12);
		Test.equals("PlainLabel(text=body, width=12)", ToStringOps.describe(label), "describe must return the explicit printed form");
	}
}
