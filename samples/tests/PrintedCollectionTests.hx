package tests;

import boring.PrintedCollection;
import boring.PrintedCollection.PrintedEnumCollection;
import boring.PrintedCollection.PrintedPoint;
import std.RecordStr;
import std.Test;

class PrintedCollectionTests {
	@:test("collection fields use the ruled array form")
	public static function collections():Void {
		final v = new PrintedCollection(["alpha", "beta"], [1, 2], [new PrintedPoint(1, 2)], [[1, 2], [3]], []);
		final expected = "PrintedCollection(names=[alpha, beta], counts=[1, 2], points=[PrintedPoint(x=1, y=2)], matrix=[[1, 2], [3]], none=[])";
		Test.equals(expected, v.toString());
		Test.equals(expected, RecordStr.str(v));
	}

	// The member call alone carries this row: the call-site form of a module
	// outside the record's own module still awaits the cross-module enum
	// cast import on the TypeScript target (see PrintedSortedFields).
	@:test("payload enum elements render through the labeled form")
	public static function enumElements():Void {
		final v = new PrintedEnumCollection([Silent, Steps(2)]);
		Test.equals("PrintedEnumCollection(flags=[Silent, Steps(count=2)])", v.toString());
	}
}
