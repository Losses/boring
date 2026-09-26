package tests;

import boring.DartNullPushOps;
import std.Test;

class DartNullPushTests {
	@:test("pushing null into Array<Null<T>> keeps null at the slot")
	public static function pushNullKeepsNull():Void {
		Test.equals(true, DartNullPushOps.pushNullIntoNullableArray() == null);
	}

	@:test("pushing a value into Array<Null<T>> keeps the value")
	public static function pushValueKeepsValue():Void {
		Test.equals(2, DartNullPushOps.pushValueIntoNullableArray());
	}

	@:test("nullable closure returning null keeps null")
	public static function closureNullStaysNull():Void {
		Test.equals(true, DartNullPushOps.nullableClosureReturnsNull() == null);
	}

	@:test("nullable closure returning a value keeps the value")
	public static function closureValueStaysValue():Void {
		Test.equals(7, DartNullPushOps.nullableClosureReturnsValue());
	}
}
