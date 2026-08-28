package reflaxe.unicode;

/**
	Shared UAX #29 grapheme boundary walk
	(docs/specs/stdlib/11-grapheme-clusters.md). The walk reads the flat
	range table produced from the pinned Unicode data files, so the
	macro-time conformance gate, the stage-one oracle, and (through the
	single-sourcing plan) every transpiled runtime apply one rule set.

	The carried state packs into one integer: the GB11 link stage in
	bits 0-1 (armed only while the text ends in Extended_Pictographic,
	Extend run, then ZWJ), the GB9c link stage in bits 2-3 (armed after
	a Consonant and an Extend or Linker run that contains at least one
	Linker), and the regional-indicator parity in bit 4.

	The table layout is three ints per range (start, endInclusive,
	packed). The packed value carries the Grapheme_Cluster_Break class
	in bits 0-3, Extended_Pictographic in bit 4, and
	Indic_Conjunct_Break in bits 5-6 (Consonant 0x20, Linker 0x40,
	Extend 0x60). Code points absent from the table are class Other
	with no flags.
**/
class GraphemeWalk {
	/** Binary search for the packed properties of one code point. */
	public static function lookup(table: Array<Int>, code: Int): Int {
		final rangeCount = Std.int(table.length / 3);
		var lo = 0;
		var hi = rangeCount - 1;
		while(lo <= hi) {
			final mid = (lo + hi) >> 1;
			final base = mid * 3;
			if(code < table[base]) {
				hi = mid - 1;
			} else if(code > table[base + 1]) {
				lo = mid + 1;
			} else {
				return table[base + 2];
			}
		}
		return 0;
	}

	/** Decides the boundary before `cur`; the state still describes the text before it. */
	public static function breaksBefore(prev: Int, cur: Int, state: Int): Bool {
		final pc = prev & 15;
		final cc = cur & 15;
		if(pc == 1 && cc == 2) return false; // GB3 CR x LF
		if(pc == 1 || pc == 2 || pc == 3) return true; // GB4
		if(cc == 1 || cc == 2 || cc == 3) return true; // GB5
		if(pc == 9 && (cc == 9 || cc == 10 || cc == 12 || cc == 13)) return false; // GB6
		if((pc == 10 || pc == 12) && (cc == 10 || cc == 11)) return false; // GB7
		if((pc == 11 || pc == 13) && cc == 11) return false; // GB8
		if(cc == 4 || cc == 5) return false; // GB9
		if(cc == 8) return false; // GB9a
		if(pc == 7) return false; // GB9b
		if((cur & 32) != 0 && ((state >> 2) & 3) == 2) return false; // GB9c
		if((cur & 16) != 0 && (state & 3) == 2) return false; // GB11
		if(cc == 6 && (state & 16) != 0) return false; // GB12/13
		return true; // GB999
	}

	/**
		Advances the link states and the regional-indicator parity past
		`cur`. GB11 arms only while the text ends in ExtPict Extend* ZWJ,
		so an Extend after the ZWJ clears it; GB9c arms after Consonant
		then Extend/Linker runs that contain at least one Linker.
	**/
	public static function advanceState(cur: Int, state: Int): Int {
		final cc = cur & 15;
		var pict = state & 3;
		var incb = (state >> 2) & 3;
		var riOdd = (state & 16) != 0;
		if((cur & 16) != 0) {
			pict = 1;
		} else if(cc == 5) {
			pict = pict == 1 ? 2 : 0;
		} else if(cc == 4) {
			if(pict != 1) {
				pict = 0;
			}
		} else {
			pict = 0;
		}
		final incbValue = cur & 96;
		if(incbValue == 32) {
			incb = 1;
		} else if(incbValue == 64) {
			incb = incb >= 1 ? 2 : 0;
		} else if(incbValue == 96) {
			// Extend keeps the consonant context alive.
		} else {
			incb = 0;
		}
		riOdd = cc == 6 ? !riOdd : false;
		return (riOdd ? 16 : 0) | (incb << 2) | pict;
	}

	/** UTF-16 storage width of the code point starting at unit `i`. */
	public static function charWidth(s: String, i: Int): Int {
		final unit = s.charCodeAt(i);
		if(unit >= 0xD800 && unit <= 0xDBFF && i + 1 < s.length) {
			final next = s.charCodeAt(i + 1);
			if(next >= 0xDC00 && next <= 0xDFFF) {
				return 2;
			}
		}
		return 1;
	}

	/** The code point starting at UTF-16 unit `i`, decoding surrogate pairs. */
	public static function codePointAt(s: String, i: Int): Int {
		final unit = s.charCodeAt(i);
		if(unit >= 0xD800 && unit <= 0xDBFF && i + 1 < s.length) {
			final next = s.charCodeAt(i + 1);
			if(next >= 0xDC00 && next <= 0xDFFF) {
				return 0x10000 + ((unit - 0xD800) << 10) + (next - 0xDC00);
			}
		}
		return unit;
	}

	/**
		Walks the string and reports, for every code point, whether a
		cluster boundary sits before it. The first code point always
		reports true (GB1). This is the conformance entry: the macro data
		gate compares these flags against the official
		GraphemeBreakTest vectors.
	**/
	public static function boundaryFlags(table: Array<Int>, s: String): Array<Bool> {
		final flags: Array<Bool> = [];
		var prev = -1;
		var state = 0;
		var unit = 0;
		while(unit < s.length) {
			final code = codePointAt(s, unit);
			final packed = lookup(table, code);
			flags.push(prev < 0 || breaksBefore(prev, packed, state));
			state = advanceState(packed, state);
			prev = packed;
			unit += charWidth(s, unit);
		}
		return flags;
	}
}
