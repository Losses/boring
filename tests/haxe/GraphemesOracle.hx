package;

import reflaxe.unicode.GraphemeBreakData;
import reflaxe.unicode.GraphemeWalk;

/**
    Stage-one oracle behind std.Graphemes
    (docs/specs/stdlib/11-grapheme-clusters.md). The cluster tier is a
    cursor protocol over the shared UAX #29 walk in
    reflaxe.unicode.GraphemeWalk, reading the table the compile-time
    data pipeline defines, so the four-target consistency harness
    compares one rule set.
**/
@:expose("GraphemesOracle")
class GraphemesOracle {
    static function packedAt(s:String, i:Int):Int {
        return GraphemeWalk.lookup(GraphemeBreakData.TABLE, GraphemeWalk.codePointAt(s, i));
    }

    public static function count(s:String):Int {
        var total:Int = 0;
        var prev:Int = -1;
        var state:Int = 0;
        var i:Int = 0;
        while (i < s.length) {
            final packed:Int = packedAt(s, i);
            if (prev < 0 || GraphemeWalk.breaksBefore(prev, packed, state)) {
                total += 1;
            }
            state = GraphemeWalk.advanceState(packed, state);
            prev = packed;
            i += GraphemeWalk.charWidth(s, i);
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
            final packed:Int = packedAt(s, i);
            if (prev < 0 || GraphemeWalk.breaksBefore(prev, packed, state)) {
                if (ordinal == index + 1) {
                    return s.substring(clusterStart, i);
                }
                ordinal += 1;
                clusterStart = i;
            }
            state = GraphemeWalk.advanceState(packed, state);
            prev = packed;
            i += GraphemeWalk.charWidth(s, i);
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
            final packed:Int = packedAt(s, i);
            if (prev < 0 || GraphemeWalk.breaksBefore(prev, packed, state)) {
                if (ordinal - 1 >= start && ordinal - 1 < end) {
                    out += s.substring(clusterStart, i);
                }
                ordinal += 1;
                clusterStart = i;
            }
            state = GraphemeWalk.advanceState(packed, state);
            prev = packed;
            i += GraphemeWalk.charWidth(s, i);
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
            final packed:Int = packedAt(s, i);
            if (prev < 0 || GraphemeWalk.breaksBefore(prev, packed, state)) {
                if (prev >= 0) {
                    out.push(s.substring(clusterStart, i));
                }
                clusterStart = i;
            }
            state = GraphemeWalk.advanceState(packed, state);
            prev = packed;
            i += GraphemeWalk.charWidth(s, i);
        }
        if (clusterStart < s.length) {
            out.push(s.substring(clusterStart));
        }
        return out;
    }
}
