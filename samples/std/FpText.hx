package std;

import haxe.io.FPHelper;
import std.StringBuf;

/**
    Shortest decimal text for a binary32 value (features/44): the
    fewest significant digits that round-trip to the same binary32
    bits, rendered in plain decimal placement with a trailing ".0"
    for whole numbers. Values whose shortest form needs more than
    nine significant digits keep the platform text.
**/
class FpText {
    public static function shortest(value:Float):String {
        var negative = value < 0;
        var v = Math.abs(value);
        if (v == 0) {
            return negative ? "-0.0" : "0.0";
        }
        var e = 0;
        var x = v;
        while (x >= 10) { x /= 10; e += 1; }
        while (x < 1) { x *= 10; e -= 1; }
        final targetBits = FPHelper.floatToI32(v);
        final target = FPHelper.i32ToFloat(targetBits);
        var p = 1;
        while (p <= 9) {
            final exp = e - p + 1;
            final scaled = v / Math.pow(10, exp);
            final base = Math.floor(scaled);
            var best = -1.0;
            var bestDist = Math.POSITIVE_INFINITY;
            var c:Float = base - 1;
            while (c <= base + 2) {
                if (c >= 1) {
                    final candidateText:String = Std.string(c) + "e" + Std.string(exp);
                    final cand:Float = Std.parseFloat(candidateText);
                    if (FPHelper.floatToI32(cand) == targetBits) {
                        final dist:Float = Math.abs(cand - target);
                        if (dist < bestDist || (dist == bestDist && (c % 2 == 0))) {
                            best = c;
                            bestDist = dist;
                        }
                    }
                }
                c += 1;
            }
            if (best >= 0) {
                return render(best, e, p, negative);
            }
            p += 1;
        }
        return (negative ? "-" : "") + Std.string(v);
    }

    static function render(c:Float, e:Int, p:Int, negative:Bool):String {
        var s = Std.string(c);
        if (s.length < p) {
            s = StringTools.lpad(s, "0", p);
        }
        final pointAfter = e + 1;
        final out = new StringBuf();
        if (negative) {
            out.add("-");
        }
        if (pointAfter <= 0) {
            out.add("0.");
            var k = 0;
            while (k < -pointAfter) { out.add("0"); k += 1; }
            out.add(s);
        } else if (pointAfter >= p) {
            out.add(s);
            var k = p;
            while (k < pointAfter) { out.add("0"); k += 1; }
            out.add(".0");
        } else {
            out.add(s.substring(0, pointAfter));
            out.add(".");
            out.add(s.substring(pointAfter));
        }
        return out.toString();
    }
}
