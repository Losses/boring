package tests;

import boring.PrintedCollection;
import boring.PrintedCollection.PrintedPoint;
import std.RecordStr;
import std.Test;

// Stage 1 renders the Std.string operand natively and joins array elements
// with "," and no space; the generated targets print the ruled ", " join.
// Rows with collection fields assert through the boring_oracle conditional,
// the array-row pattern of stdlib spec 12.
class PrintedCollectionTests {
	@:test("collection fields use the ruled array form")
	public static function collections():Void {
		final v = new PrintedCollection(["alpha", "beta"], [1, 2], [new PrintedPoint(1, 2)], [[1, 2], [3]], []);
		final expected = "PrintedCollection(names=[alpha, beta], counts=[1, 2], points=[PrintedPoint(x=1, y=2)], matrix=[[1, 2], [3]], none=[])";
		#if boring_oracle
		final native = "PrintedCollection(names=[alpha,beta], counts=[1,2], points=[PrintedPoint(x=1, y=2)], matrix=[[1,2],[3]], none=[])";
		Test.equals(native, v.toString());
		Test.equals(native, RecordStr.str(v));
		#else
		Test.equals(expected, v.toString());
		Test.equals(expected, RecordStr.str(v));
		#end
	}
}
