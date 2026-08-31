package boring;

import std.ReadOnlyArray;

/** Collection fields use the Std.string array lowering (feature 33). */
@:dataClass
class PrintedCollection {
	public final names:ReadOnlyArray<String>;
	public final counts:Array<Int>;
	public final points:ReadOnlyArray<PrintedPoint>;
	public final matrix:Array<Array<Int>>;
	public final none:Array<String>;

	public function new(names:ReadOnlyArray<String>, counts:Array<Int>, points:ReadOnlyArray<PrintedPoint>, matrix:Array<Array<Int>>, none:Array<String>) {
		this.names = names; this.counts = counts; this.points = points; this.matrix = matrix; this.none = none;
	}
}

@:dataClass
class PrintedPoint {
	public final x:Int;
	public final y:Int;
	public function new(x:Int, y:Int) { this.x = x; this.y = y; }
}
