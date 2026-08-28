package;

@:expose("UStringRtOracle")
class UStringRtOracle {
    public static function count(s:String):Int {
        var total:Int = 0;
        var i:Int = 0;
        final units:Int = s.length;
        while (i < units) {
            final unit:Int = s.charCodeAt(i);
            if (unit >= 0xD800 && unit <= 0xDBFF && i + 1 < units) {
                final next:Int = s.charCodeAt(i + 1);
                if (next >= 0xDC00 && next <= 0xDFFF) {
                    i += 1;
                }
            }
            total += 1;
            i += 1;
        }
        return total;
    }

    public static function at(s:String, index:Int):Null<Int> {
        if (index < 0) {
            return null;
        }
        var remaining:Int = index;
        var i:Int = 0;
        final units:Int = s.length;
        while (i < units) {
            final unit:Int = s.charCodeAt(i);
            var width:Int = 1;
            if (unit >= 0xD800 && unit <= 0xDBFF && i + 1 < units) {
                final next:Int = s.charCodeAt(i + 1);
                if (next >= 0xDC00 && next <= 0xDFFF) {
                    width = 2;
                }
            }
            if (remaining == 0) {
                if (width == 2) {
                    return 0x10000 + ((unit - 0xD800) << 10) + (s.charCodeAt(i + 1) - 0xDC00);
                }
                return unit;
            }
            remaining -= 1;
            i += width;
        }
        return null;
    }

    public static function slice(s:String, from:Int, to:Int):String {
        final total:Int = UStringRtOracle.count(s);
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
        var unitStart:Int = 0;
        var unitEnd:Int = 0;
        var pos:Int = 0;
        var i:Int = 0;
        while (pos < end) {
            if (pos == start) {
                unitStart = i;
            }
            final unit:Int = s.charCodeAt(i);
            if (unit >= 0xD800 && unit <= 0xDBFF && i + 1 < s.length) {
                final next:Int = s.charCodeAt(i + 1);
                if (next >= 0xDC00 && next <= 0xDFFF) {
                    i += 1;
                }
            }
            i += 1;
            pos += 1;
        }
        unitEnd = i;
        return s.substr(unitStart, unitEnd - unitStart);
    }

    public static function toCodePoints(s:String):Array<Int> {
        final out:Array<Int> = [];
        var i:Int = 0;
        final units:Int = s.length;
        while (i < units) {
            final unit:Int = s.charCodeAt(i);
            if (unit >= 0xD800 && unit <= 0xDBFF && i + 1 < units) {
                final next:Int = s.charCodeAt(i + 1);
                if (next >= 0xDC00 && next <= 0xDFFF) {
                    out.push(0x10000 + ((unit - 0xD800) << 10) + (next - 0xDC00));
                    i += 2;
                    continue;
                }
            }
            out.push(unit);
            i += 1;
        }
        return out;
    }

    public static function fromCodePoint(code:Int):String {
        if (code < 0x10000) {
            return String.fromCharCode(code);
        }
        final offset:Int = code - 0x10000;
        return String.fromCharCode(0xD800 + ((offset >> 10) & 0x3FF)) + String.fromCharCode(0xDC00 + (offset & 0x3FF));
    }

    public static function fromCodePoints(codes:Array<Int>):String {
        final parts:Array<String> = [];
        for (i in 0...codes.length) {
            parts.push(UStringRtOracle.fromCodePoint(codes[i]));
        }
        return parts.join("");
    }
}
