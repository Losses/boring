package runtime;

import std.UStringRT;

/**
	Grapheme cluster segmentation over the shared UAX #29 walk
	(docs/specs/stdlib/11-grapheme-clusters.md). This class is the
	single source of the cluster tier: each target compiles it into its
	runtime package, stage one binds it as std.Graphemes, and the
	break table arrives through the compile-time data pipeline that
	validates it against the official test vectors before this class
	can compile at all.

	The five public operations decode the string to code points once,
	walk them with runtime.GraphemeWalk, and track the storage position
	in UTF-16 units so substring extraction stays on the unit positions
	of the haxe string contract (docs/specs/features/08-strings-and-
	unicode.md, String index access ruling).
**/
@:build(reflaxe.unicode.GraphemeData.tableField("TABLE"))
class Graphemes {
	// The build injects `public static final TABLE: Array<Int>`: the
	// flat break table (three ints per range: start, endInclusive,
	// packed) from the compile-time data pipeline, which validates it
	// against the Unicode GraphemeBreakTest conformance vectors before
	// this class can compile.

	/** The number of grapheme clusters in the string. */
	public static function count(s: String): Int {
		final codes = UStringRT.toCodePoints(s);
		var total = 0;
		var prev = -1;
		var state = 0;
		for(index in 0...codes.length) {
			final packed = GraphemeWalk.lookup(TABLE, codes[index]);
			if(prev < 0 || GraphemeWalk.breaksBefore(prev, packed, state)) {
				total += 1;
			}
			state = GraphemeWalk.advanceState(packed, state);
			prev = packed;
		}
		return total;
	}

	/** The cluster at `index`, or null when the index is out of range. */
	public static function at(s: String, index: Int): Null<String> {
		if(index < 0) {
			return null;
		}
		final codes = UStringRT.toCodePoints(s);
		var ordinal = 0;
		var prev = -1;
		var state = 0;
		var clusterStart = 0;
		var unit = 0;
		for(i in 0...codes.length) {
			final code = codes[i];
			final packed = GraphemeWalk.lookup(TABLE, code);
			final width = code > 0xFFFF ? 2 : 1;
			if(prev < 0 || GraphemeWalk.breaksBefore(prev, packed, state)) {
				if(ordinal == index + 1) {
					return s.substring(clusterStart, unit);
				}
				ordinal += 1;
				clusterStart = unit;
			}
			state = GraphemeWalk.advanceState(packed, state);
			prev = packed;
			unit += width;
		}
		if(ordinal == index + 1) {
			return s.substring(clusterStart, unit);
		}
		return null;
	}

	/**
		The clusters with ordinal positions in `[from, to)`, clamped to
		the cluster count the way std.UString.slice clamps to the code
		point count: negative bounds read as zero and bounds past the
		end read as the end, so an empty range yields the empty string.
	**/
	public static function slice(s: String, from: Int, to: Int): String {
		final total = count(s);
		var start = from < 0 ? 0 : from;
		if(start > total) {
			start = total;
		}
		var end = to > total ? total : to;
		if(end < 0) {
			end = 0;
		}
		if(start >= end) {
			return "";
		}
		final codes = UStringRT.toCodePoints(s);
		var out = "";
		var ordinal = 0;
		var prev = -1;
		var state = 0;
		var clusterStart = 0;
		var unit = 0;
		for(i in 0...codes.length) {
			final code = codes[i];
			final packed = GraphemeWalk.lookup(TABLE, code);
			final width = code > 0xFFFF ? 2 : 1;
			if(prev < 0 || GraphemeWalk.breaksBefore(prev, packed, state)) {
				if(ordinal - 1 >= start && ordinal - 1 < end) {
					out += s.substring(clusterStart, unit);
				}
				ordinal += 1;
				clusterStart = unit;
			}
			state = GraphemeWalk.advanceState(packed, state);
			prev = packed;
			unit += width;
		}
		if(ordinal - 1 >= start && ordinal - 1 < end) {
			out += s.substring(clusterStart, unit);
		}
		return out;
	}

	/**
		The UTF-16 unit offsets of every cluster boundary, in order:
		entry 0 is always 0, the last entry is the length of the string,
		and each interior entry is the unit position where one cluster
		ends and the next begins. A string of n clusters carries n + 1
		entries; the empty string carries the single entry 0. The unit
		positions are the positions of the haxe string contract, the
		same positions `at` and `slice` extract substrings from.
	**/
	public static function boundaries(s: String): Array<Int> {
		final codes = UStringRT.toCodePoints(s);
		final out: Array<Int> = [0];
		var prev = -1;
		var state = 0;
		var unit = 0;
		for(i in 0...codes.length) {
			final code = codes[i];
			final packed = GraphemeWalk.lookup(TABLE, code);
			final width = code > 0xFFFF ? 2 : 1;
			if(prev >= 0 && GraphemeWalk.breaksBefore(prev, packed, state)) {
				out.push(unit);
			}
			state = GraphemeWalk.advanceState(packed, state);
			prev = packed;
			unit += width;
		}
		if(unit > 0) {
			out.push(unit);
		}
		return out;
	}

	/** Every cluster of the string, in order; the empty string has no parts. */
	public static function parts(s: String): Array<String> {
		final codes = UStringRT.toCodePoints(s);
		final out: Array<String> = [];
		var prev = -1;
		var state = 0;
		var clusterStart = 0;
		var unit = 0;
		for(i in 0...codes.length) {
			final code = codes[i];
			final packed = GraphemeWalk.lookup(TABLE, code);
			final width = code > 0xFFFF ? 2 : 1;
			if(prev < 0 || GraphemeWalk.breaksBefore(prev, packed, state)) {
				if(prev >= 0) {
					out.push(s.substring(clusterStart, unit));
				}
				clusterStart = unit;
			}
			state = GraphemeWalk.advanceState(packed, state);
			prev = packed;
			unit += width;
		}
		if(clusterStart < unit) {
			out.push(s.substring(clusterStart, unit));
		}
		return out;
	}
}
