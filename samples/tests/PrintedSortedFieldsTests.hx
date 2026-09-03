package tests;

import boring.PrintedSortedFields;
import boring.PrintedCollection.PrintedPoint;
import boring.PrintedSortedFields.PrintedNullableMark;
import boring.PrintedEnumOps.PrintedMark;
import std.SortedMap;
import std.SortedSet;
import std.Test;

class PrintedSortedFieldsTests {
	@:test("sorted fields use ruled forms")
	public static function fields():Void {
		final sb = SortedSet.builder(); sb.put(2); sb.put(1);
		final pb = SortedSet.builder(); pb.put(new PrintedPoint(1, 2));
		final mb = SortedMap.builder(); mb.put("b", 2); mb.put("a", 1);
		final emptySet = SortedSet.builder();
		final emptyMap = SortedMap.builder();
		final value = new PrintedSortedFields(sb.build(), pb.build(), mb.build(), emptySet.build(), emptyMap.build());
		final expected = "PrintedSortedFields(marks=[1, 2], points=[PrintedPoint(x=1, y=2)], lookup={a=1, b=2}, emptySet=[], emptyMap={})";
		Test.equals(expected, value.toString());
		final nullMark = new PrintedNullableMark(null);
		Test.equals("PrintedNullableMark(mark=null)", nullMark.toString());
		final ringMark = new PrintedNullableMark(Ring(1.5));
		Test.equals("PrintedNullableMark(mark=Ring(diameter=1.5))", ringMark.toString());
	}
}
