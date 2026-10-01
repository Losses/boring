package pch;

/**
    The minimal reproduction of the per-char `units` hoisting defect
    (t-mukem10i-n8ll): every shape below walks a String one UTF-16 code unit at
    a time. The emitted Rust must materialize `u_string::units(&s)` at most once
    per (function, receiver) -- a re-materialization inside a loop body is O(n)
    per step, i.e. quadratic in the string length.

    The shapes differ in how the emitter reaches them:
      stripWholeFraction -- a nested `while (i < s.length)` over the same
                            receiver; this is the measured Tiqian shape
                            (TestTraceRender.stripWholeFraction) verbatim.
      whileDotCount      -- a single `while` walk of a parameter.
      whileLocalDotCount -- a single `while` walk of a local String, which the
                            function-level String-parameter hoist cannot cover.
      forRangeDotCount   -- `for (i in 0...s.length)` of a parameter.
      forRangeLocal...   -- `for (i in 0...s.length)` of a local String, which
                            the emitter lowers through the interval
                            (`for i in start..bound`) path.
**/
class PerCharUnitsProbe {
    public static function stripWholeFraction(value:String):String {
        final output = new StringBuf();
        var index = 0;
        while (index < value.length) {
            if (value.charCodeAt(index) == 46 && index > 0 && isDigit(value.charCodeAt(index - 1))) {
                var cursor = index + 1;
                while (cursor < value.length && value.charCodeAt(cursor) == 48) {
                    cursor += 1;
                }
                if (cursor > index + 1 && (cursor == value.length || !isDigit(value.charCodeAt(cursor)))) {
                    index = cursor;
                    continue;
                }
            }
            output.add(value.substring(index, index + 1));
            index += 1;
        }
        return output.toString();
    }

    static function isDigit(code:Int):Bool {
        return code >= 48 && code <= 57;
    }

    public static function whileDotCount(s:String):Int {
        var total = 0;
        var i = 0;
        while (i < s.length) {
            if (s.charCodeAt(i) == 46) {
                total += 1;
            }
            i += 1;
        }
        return total;
    }

    public static function whileLocalDotCount(input:String):Int {
        final s = input + "!";
        var total = 0;
        var i = 0;
        while (i < s.length) {
            if (s.charCodeAt(i) == 46) {
                total += 1;
            }
            i += 1;
        }
        return total;
    }

    public static function forRangeDotCount(s:String):Int {
        var total = 0;
        for (i in 0...s.length) {
            if (s.charCodeAt(i) == 46) {
                total += 1;
            }
        }
        return total;
    }

    public static function forRangeLocalDotCount(input:String):Int {
        final s = input + "!";
        var total = 0;
        for (i in 0...s.length) {
            if (s.charCodeAt(i) == 46) {
                total += 1;
            }
        }
        return total;
    }
}
