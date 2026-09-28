package place;

import std.Console;

/**
	Separate entry for a failed element read on a null array binding. The
	pinned runner reports a host failure here; the entry exists so that
	failure is recorded with its own status and the other observations
	keep running.
**/
class PlaceReadFault {
	static function main():Void {
		Console.log("[C3d] null binding element compound");
		final a:Array<Int> = null;
		Console.log("  before read");
		a[0] += 1;
		Console.log("  after store");
	}
}
