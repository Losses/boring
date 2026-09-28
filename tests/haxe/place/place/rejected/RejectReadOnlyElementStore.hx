package place.rejected;

import std.ReadOnlyArray;

/**
	Rejected form: an element store through the read-only array interface.
	The view declares indexed reads only, so the store is rejected by the
	Haxe type checker while a retained mutable alias keeps write access.
**/
class RejectReadOnlyElementStore {
	static function main():Void {
		final plain:Array<Int> = [1, 2];
		final ro:ReadOnlyArray<Int> = plain;
		ro[0] = 5;
	}
}
