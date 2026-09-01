package runtime;

import std.UStringPlatform;

/**
	Code-point-addressed string access, the single source of the unchecked
	primitives behind std.UStringRT
	(docs/specs/stdlib/10-unicode-string-access.md). Each target compiles this
	class into its runtime package and routes the extern through it; stage
	one binds it as std.UStringRT. The construction-domain checks live in
	the inline wrappers of std.UString and never reach these functions.

	Every walk is a cursor loop over std.UStringPlatform: the cursor counts
	UTF-16 units on the script targets and bytes on Rust, and each step
	costs O(1), so count, at, slice, and toCodePoints stay one linear pass
	over the storage with no intermediate allocation beyond the result.
**/
class UString {
	/** The number of code points in the string. */
	public static function count(s:String):Int {
		var total = 0;
		var cursor = 0;
		final stop = UStringPlatform.end(s);
		while(cursor < stop) {
			total += 1;
			cursor = UStringPlatform.advance(s, cursor);
		}
		return total;
	}

	/** The code point at `index`, or null when the index is out of range. */
	public static function at(s:String, index:Int):Null<Int> {
		if(index < 0) {
			return null;
		}
		var remaining = index;
		var cursor = 0;
		final stop = UStringPlatform.end(s);
		while(cursor < stop) {
			if(remaining == 0) {
				return UStringPlatform.codeAt(s, cursor);
			}
			remaining -= 1;
			cursor = UStringPlatform.advance(s, cursor);
		}
		return null;
	}

	/**
		The code points with ordinal positions in `[from, to)`, clamped to
		the code point count: negative bounds read as zero and bounds past
		the end read as the end, so an empty range yields the empty string.
	**/
	public static function slice(s:String, from:Int, to:Int):String {
		final total = count(s);
		var start = from < 0 ? 0 : from;
		if(start > total) {
			start = total;
		}
		var stop = to > total ? total : to;
		if(stop < 0) {
			stop = 0;
		}
		if(start >= stop) {
			return "";
		}
		var ordinal = 0;
		var startCursor = 0;
		var cursor = 0;
		while(ordinal < stop) {
			if(ordinal == start) {
				startCursor = cursor;
			}
			cursor = UStringPlatform.advance(s, cursor);
			ordinal += 1;
		}
		return UStringPlatform.substringBetween(s, startCursor, cursor);
	}

	/** Every code point of the string, in order; the empty string has none. */
	public static function toCodePoints(s:String):Array<Int> {
		final out:Array<Int> = [];
		var cursor = 0;
		final stop = UStringPlatform.end(s);
		while(cursor < stop) {
			out.push(UStringPlatform.codeAt(s, cursor));
			cursor = UStringPlatform.advance(s, cursor);
		}
		return out;
	}

	/** The string holding `code`, a code point of the valid domain. */
	public static function fromCodePoint(code:Int):String {
		return UStringPlatform.fromCodePoint(code);
	}

	/** The concatenation of every code point of the valid domain. */
	public static function fromCodePoints(codes:Array<Int>):String {
		var out = "";
		for(index in 0...codes.length) {
			out += UStringPlatform.fromCodePoint(codes[index]);
		}
		return out;
	}
}
