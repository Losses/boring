package place.rejected;

import std.ReadOnlyArray;

/**
	Rejected form: rebinding a `final` local. The binding itself is not
	rebindable, while the object it names keeps its own declared write
	operations.
**/
class RejectFinalLocalAssign {
	static function main():Void {
		final plain:Array<Int> = [1, 2];
		final ro:ReadOnlyArray<Int> = plain;
		ro = [3, 4];
	}
}
