package;

import reflaxe.unicode.GraphemeBreakData;

/**
 * Stage-one oracle behind std.Graphemes
 * (docs/specs/stdlib/11-grapheme-clusters.md). Implements the same UAX
 * #29 walk and reads the same generated table as the three transpiled
 * runtimes, so the four-target consistency harness compares one rule set.
 */
@:expose("GraphemesOracle")
class GraphemesOracle {
    static function lookup(code:Int):Int {
        var lo:Int = 0;
        var hi:Int = Math.floor(GraphemeBreakData.TABLE.length / 3) - 1;
        while (lo <= hi) {
            final mid:Int = (lo + hi) >> 1;
            final base:Int = mid * 3;
            if (code < GraphemeBreakData.TABLE[base]) {
                hi = mid - 1;
            } else if (code > GraphemeBreakData.TABLE[base + 1]) {
                lo = mid + 1;
            } else {
                return GraphemeBreakData.TABLE[base + 2];
            }
        }
        return 0;
    }

    static function breaksBefore(prev:Int, cur:Int, state:Int):Bool {
        final pc:Int = prev & 15;
        final cc:Int = cur & 15;
        if (pc == 1 && cc == 2) return false; // GB3 CR x LF
        if (pc == 1 || pc == 2 || pc == 3) return true; // GB4
        if (cc == 1 || cc == 2 || cc == 3) return true; // GB5
        if (pc == 9 && (cc == 9 || cc == 10 || cc == 12 || cc == 13)) return false; // GB6
        if ((pc == 10 || pc == 12) && (cc == 10 || cc == 11)) return false; // GB7
        if ((pc == 11 || pc == 13) && cc == 11) return false; // GB8
        if (cc == 4 || cc == 5) return false; // GB9
        if (cc == 8) return false; // GB9a
        if (pc == 7) return false; // GB9b
        if ((cur & 32) != 0 && ((state >> 2) & 3) == 2) return false; // GB9c
        if ((cur & 16) != 0 && (state & 3) == 2) return false; // GB11
        if (cc == 6 && (state & 16) != 0) return false; // GB12/13
        return true; // GB999
    }

    static function advanceState(cur:Int, state:Int):Int {
        final cc:Int = cur & 15;
        var pict:Int = state & 3;
        var incb:Int = (state >> 2) & 3;
        var riOdd:Bool = (state & 16) != 0;
        if ((cur & 16) != 0) {
            pict = 1;
        } else if (cc == 5) {
            pict = pict == 1 ? 2 : 0;
        } else if (cc == 4) {
            if (pict != 1) {
                pict = 0;
            }
        } else {
            pict = 0;
        }
        final incbValue:Int = cur & 96;
        if (incbValue == 32) {
            incb = 1;
        } else if (incbValue == 64) {
            incb = incb >= 1 ? 2 : 0;
        } else if (incbValue == 96) {
            // Extend keeps the consonant context alive.
        } else {
            incb = 0;
        }
        riOdd = cc == 6 ? !riOdd : false;
        return (riOdd ? 16 : 0) | (incb << 2) | pict;
    }

    static function charWidth(s:String, i:Int):Int {
        final unit:Int = s.charCodeAt(i);
        if (unit >= 0xD800 && unit <= 0xDBFF && i + 1 < s.length) {
            final next:Int = s.charCodeAt(i + 1);
            if (next >= 0xDC00 && next <= 0xDFFF) {
                return 2;
            }
        }
        return 1;
    }

    static function codePointAt(s:String, i:Int):Int {
        final unit:Int = s.charCodeAt(i);
        if (unit >= 0xD800 && unit <= 0xDBFF && i + 1 < s.length) {
            final next:Int = s.charCodeAt(i + 1);
            if (next >= 0xDC00 && next <= 0xDFFF) {
                return 0x10000 + ((unit - 0xD800) << 10) + (next - 0xDC00);
            }
        }
        return unit;
    }

    public static function count(s:String):Int {
        var total:Int = 0;
        var prev:Int = -1;
        var state:Int = 0;
        var i:Int = 0;
        while (i < s.length) {
            final packed:Int = lookup(codePointAt(s, i));
            if (prev < 0 || breaksBefore(prev, packed, state)) {
                total += 1;
            }
            state = advanceState(packed, state);
            prev = packed;
            i += charWidth(s, i);
        }
        return total;
    }

    public static function at(s:String, index:Int):Null<String> {
        if (index < 0) {
            return null;
        }
        var ordinal:Int = 0;
        var prev:Int = -1;
        var state:Int = 0;
        var clusterStart:Int = 0;
        var i:Int = 0;
        while (i < s.length) {
            final packed:Int = lookup(codePointAt(s, i));
            if (prev < 0 || breaksBefore(prev, packed, state)) {
                if (ordinal == index + 1) {
                    return s.substring(clusterStart, i);
                }
                ordinal += 1;
                clusterStart = i;
            }
            state = advanceState(packed, state);
            prev = packed;
            i += charWidth(s, i);
        }
        if (ordinal == index + 1) {
            return s.substring(clusterStart);
        }
        return null;
    }

    public static function slice(s:String, from:Int, to:Int):String {
        final total:Int = count(s);
        var start:Int = from < 0 ? 0 : from;
        if (start > total) {
            start = total;
        }
        var end:Int = to > total ? total : to;
        if (end < 0) {
            end = 0;
        }
        if (start >= end) {
            return "";
        }
        var out:String = "";
        var ordinal:Int = 0;
        var prev:Int = -1;
        var state:Int = 0;
        var clusterStart:Int = 0;
        var i:Int = 0;
        while (i < s.length) {
            final packed:Int = lookup(codePointAt(s, i));
            if (prev < 0 || breaksBefore(prev, packed, state)) {
                if (ordinal - 1 >= start && ordinal - 1 < end) {
                    out += s.substring(clusterStart, i);
                }
                ordinal += 1;
                clusterStart = i;
            }
            state = advanceState(packed, state);
            prev = packed;
            i += charWidth(s, i);
        }
        if (ordinal - 1 >= start && ordinal - 1 < end) {
            out += s.substring(clusterStart);
        }
        return out;
    }

    public static function parts(s:String):Array<String> {
        final out:Array<String> = [];
        var prev:Int = -1;
        var state:Int = 0;
        var clusterStart:Int = 0;
        var i:Int = 0;
        while (i < s.length) {
            final packed:Int = lookup(codePointAt(s, i));
            if (prev < 0 || breaksBefore(prev, packed, state)) {
                if (prev >= 0) {
                    out.push(s.substring(clusterStart, i));
                }
                clusterStart = i;
            }
            state = advanceState(packed, state);
            prev = packed;
            i += charWidth(s, i);
        }
        if (clusterStart < s.length) {
            out.push(s.substring(clusterStart));
        }
        return out;
    }
}
