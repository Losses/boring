package org.tiqian.protocol;


/**
 * Font session replay keys (Stage2 protocol, research 5.3).
 *
 * Canonical twin of the hand-written Rust replay.rs
 * shape_replay_key / metric_replay_key / normalized_replay_number.
 * A replay key is a byte-stable JSON array: families are joined with the ASCII
 * unit separator (U+001F), optional strings render as the literal "null", and
 * numbers render through PlanJsonNumber.ecmaJsonNumber (ECMAScript shortest
 * round-trip, identical to the Rust js_number_string).
 */

/** Canonical shape-replay key (7 fields). Mirrors Rust struct ShapeReplayKey. */
typedef ShapeReplayKey = {
    final displayText:String;
    final serializedFamilies:String;
    final fontWeight:Float;
    final italic:Bool;
    final locale:String;
    final role:String;
    final sourceText:String;
};

/** Canonical metric-replay key (5 fields). Mirrors Rust struct MetricReplayKey. */
typedef MetricReplayKey = {
    final serializedFamilies:String;
    final fontWeight:Float;
    final italic:Bool;
    final role:String;
    final faceSelectionText:String;
};

class ReplayKey {
    public static function shapeReplayKey(displayText:String, fontFamilies:Array<String>, fontWeight:Float, italic:Bool, locale:String, role:Null<String>, sourceText:String):ShapeReplayKey {
        return {
            displayText: displayText,
            serializedFamilies: serializeFamilies(fontFamilies),
            fontWeight: fontWeight,
            italic: italic,
            locale: locale,
            role: role == null ? "null" : role,
            sourceText: sourceText
        };
    }

    public static function metricReplayKey(fontFamilies:Array<String>, fontWeight:Float, italic:Bool, role:Null<String>, faceSelectionText:Null<String>):MetricReplayKey {
        return {
            serializedFamilies: serializeFamilies(fontFamilies),
            fontWeight: fontWeight,
            italic: italic,
            role: role == null ? "null" : role,
            faceSelectionText: faceSelectionText == null ? "null" : faceSelectionText
        };
    }

    public static function renderShapeReplayKey(key:ShapeReplayKey):String {
        final out:Array<String> = [];
        out.push("[");
        addJsonString(out, key.displayText);
        out.push(",");
        addJsonString(out, key.serializedFamilies);
        out.push(",");
        addJsonNumber(out, key.fontWeight);
        out.push(",");
        addJsonBool(out, key.italic);
        out.push(",");
        addJsonString(out, key.locale);
        out.push(",");
        addJsonString(out, key.role);
        out.push(",");
        addJsonString(out, key.sourceText);
        out.push("]");
        return out.join("");
    }

    public static function renderMetricReplayKey(key:MetricReplayKey):String {
        final out:Array<String> = [];
        out.push("[");
        addJsonString(out, key.serializedFamilies);
        out.push(",");
        addJsonNumber(out, key.fontWeight);
        out.push(",");
        addJsonBool(out, key.italic);
        out.push(",");
        addJsonString(out, key.role);
        out.push(",");
        addJsonString(out, key.faceSelectionText);
        out.push("]");
        return out.join("");
    }

    public static function normalizedReplayNumber(value:Float, fontSize:Float):Null<Float> {
        if (!Math.isFinite(value))
            return null;
        final q = value / fontSize;
        if (!Math.isFinite(q))
            return q; // Rust format + parse round-trips inf/nan back unchanged
        final normalized = roundTwelveDecimals(q);
        return normalized == 0.0 ? 0.0 : normalized;
    }

    // --- private helpers ---

    private static function serializeFamilies(fontFamilies:Array<String>):String {
        return fontFamilies.join("\x1f");
    }

    private static function addJsonNumber(out:Array<String>, v:Float):Void {
        out.push(PlanJsonNumber.ecmaJsonNumber(v));
    }

    private static function addJsonBool(out:Array<String>, b:Bool):Void {
        out.push(b ? "true" : "false");
    }

    private static function addJsonString(out:Array<String>, s:String):Void {
        PlanJsonNumber.appendJsonString(out, s);
    }

    /**
     * Rounds a finite Float to 12 fractional decimal digits, returning a Float:
     * the Haxe twin of Rust format!("{:.12}", x) then parse::<f64>() (equivalently
     * JS Number((x).toFixed(12))). Built over the shortest exact decimal
     * (PlanJsonNumber.ecmaJsonNumber) so it neither overflows the 32-bit Int
     * returned by Math.round nor depends on target Float-to-String notation.
     * Exact for all finite |x| < 1e15 (covers every font metric).
     */
    private static function roundTwelveDecimals(x:Float):Float {
        if (x == 0.0)
            return 0.0;
        final negative = x < 0;
        final a = negative ? -x : x;
        final text = fixed12(a);
        final parsed = Std.parseFloat(text);
        final result = negative ? -parsed : parsed;
        return result == 0.0 ? 0.0 : result;
    }

    private static function fixed12(a:Float):String {
        final s = PlanJsonNumber.ecmaJsonNumber(a);
        var intPart:String;
        var fracPart:String;
        final ePos = s.indexOf("e");
        if (ePos >= 0) {
            final mant = s.substr(0, ePos);
            // Exponent is signed ("e-13" / "e+21"); parse magnitude as a
            // non-negative Int (u32) and branch on sign so the decimal shift
            // never goes negative (Std.parseInt maps to a nullable i32 that
            // breaks the generated unsigned arithmetic).
            final expStr = s.substr(ePos + 1);
            final expFirst = expStr.charCodeAt(0);
            final negativeExp = expFirst == 45;
            final expBody = (expFirst == 45 || expFirst == 43) ? expStr.substr(1) : expStr;
            final expMag = parseUnsignedDecimal(expBody);
            final mdot = mant.indexOf(".");
            var digits:String;
            var lead:Int;
            if (mdot >= 0) {
                digits = mant.substr(0, mdot) + mant.substr(mdot + 1);
                lead = mdot;
            } else {
                lead = mant.length;
                digits = mant;
            }
            if (negativeExp) {
                // |a| < 1: the first significant digit sits lead - expMag < 0
                // places left of the unit, so expMag > lead and the zero-run
                // is non-negative.
                intPart = "0";
                fracPart = zeros(expMag - lead) + digits;
            } else {
                final pointPos = lead + expMag;
                final digitsLen = digits.length;
                if (pointPos >= digitsLen) {
                    intPart = digits + zeros(pointPos - digitsLen);
                    fracPart = "";
                } else {
                    intPart = digits.substr(0, pointPos);
                    fracPart = digits.substr(pointPos);
                }
            }
        } else {
            final dot = s.indexOf(".");
            if (dot >= 0) {
                intPart = s.substr(0, dot);
                fracPart = s.substr(dot + 1);
            } else {
                intPart = s;
                fracPart = "";
            }
        }
        // Round fracPart to 12 digits (round half up; no exact ties occur for
        // binary doubles, per the Rust replay.rs note).
        var roundedFrac:String;
        var carry = false;
        if (fracPart.length <= 12) {
            roundedFrac = fracPart + zeros(12 - fracPart.length);
        } else {
            final next = fracPart.charCodeAt(12) - 48;
            if (next >= 5) {
                final inc = incrementDecimal(fracPart.substr(0, 12));
                if (inc.length > 12) {
                    roundedFrac = zeros(12);
                    carry = true;
                } else {
                    roundedFrac = inc;
                }
            } else {
                roundedFrac = fracPart.substr(0, 12);
            }
        }
        final finalInt = carry ? incrementDecimal(intPart) : intPart;
        return finalInt + "." + roundedFrac;
    }

    private static function parseUnsignedDecimal(s:String):Int {
        var n = 0;
        final len = s.length;
        var i = 0;
        while (i < len) {
            n = n * 10 + (s.charCodeAt(i) - 48);
            i++;
        }
        return n;
    }

    private static function incrementDecimal(s:String):String {
        var i = s.length - 1;
        while (i >= 0 && s.charCodeAt(i) == 57)
            i--;
        if (i < 0)
            return "1" + zeros(s.length);
        return s.substr(0, i) + String.fromCharCode(s.charCodeAt(i) + 1) + zeros(s.length - i - 1);
    }

    private static function zeros(n:Int):String {
        var s = "";
        var i = 0;
        while (i < n) {
            s += "0";
            i++;
        }
        return s;
    }
}
