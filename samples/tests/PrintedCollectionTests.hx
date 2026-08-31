package tests;

import boring.PrintedCollection;
import boring.PrintedCollection.PrintedPoint;
import std.RecordStr;
import std.Test;

class PrintedCollectionTests {
	@:test("collection fields use the ruled array form")
	public static function collections():Void {
		final v = new PrintedCollection(["alpha", "beta"], [1, 2], [new PrintedPoint(1, 2)], [[1, 2], [3]], []);
		final expected = "PrintedCollection(names=[alpha, beta], counts=[1, 2], points=[PrintedPoint(x=1, y=2)], matrix=[[1, 2], [3]], none=[])";
		Test.equals(RecordStr.str(v), v.toString());
	}
}
