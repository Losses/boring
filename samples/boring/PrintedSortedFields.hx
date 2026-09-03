package boring;

import boring.PrintedCollection.PrintedPoint;
import boring.PrintedEnumOps.PrintedMark;
import std.SortedMap;
import std.SortedSet;

@:dataClass
class PrintedSortedFields {
	public final marks:SortedSet<Int>;
	public final points:SortedSet<PrintedPoint>;
	public final lookup:SortedMap<String, Int>;
	public final emptySet:SortedSet<Int>;
	public final emptyMap:SortedMap<String, Int>;
	public function new(marks:SortedSet<Int>, points:SortedSet<PrintedPoint>, lookup:SortedMap<String, Int>, emptySet:SortedSet<Int>, emptyMap:SortedMap<String, Int>) {
		this.marks = marks; this.points = points; this.lookup = lookup; this.emptySet = emptySet; this.emptyMap = emptyMap;
	}
}

@:dataClass
class PrintedNullableMark {
	public final mark:Null<PrintedMark>;
	public function new(mark:Null<PrintedMark>) { this.mark = mark; }
}
