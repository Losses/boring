package runtime;

/**
    The runtime home of the StringTools statics that have no native Kotlin
    `String` equivalent and no inline lowering at the call site. The Kotlin
    target routes `StringTools` statics that are neither inline-lowered (hex,
    trim, startsWith, endsWith) nor present on the Kotlin `String` type into
    this class, exactly like std.UStringRT fronts runtime.UString.
**/
class StringTools {
    /** True when the character of `s` at `pos` is a whitespace character. */
    public static function isSpace(s:String, pos:Int):Bool {
        if (s.length == 0 || pos < 0 || pos >= s.length) {
            return false;
        }
        final c = s.charCodeAt(pos);
        return (c > 8 && c < 14) || c == 32;
    }

    /** Removes leading whitespace from `s`. */
    public static function ltrim(s:String):String {
        var l = s.length;
        var r = 0;
        while (r < l && isSpace(s, r)) {
            r++;
        }
        return r > 0 ? s.substr(r, l - r) : s;
    }

    /** Removes trailing whitespace from `s`. */
    public static function rtrim(s:String):String {
        var l = s.length;
        var r = 0;
        while (r < l && isSpace(s, l - r - 1)) {
            r++;
        }
        return r > 0 ? s.substr(0, l - r) : s;
    }

    /** Pads `s` on the left with `c` until its length is at least `l`. */
    public static function lpad(s:String, c:String, l:Int):String {
        if (c.length <= 0) {
            return s;
        }
        var buf = new StringBuf();
        var remaining = l - s.length;
        while (buf.length < remaining) {
            buf.add(c);
        }
        buf.add(s);
        return buf.toString();
    }

    /** Pads `s` on the right with `c` until its length is at least `l`. */
    public static function rpad(s:String, c:String, l:Int):String {
        if (c.length <= 0) {
            return s;
        }
        var buf = new StringBuf();
        buf.add(s);
        var remaining = l - s.length;
        while (buf.length < remaining) {
            buf.add(c);
        }
        return buf.toString();
    }

    /** Replaces every occurrence of `sub` in `s` with `by`. */
    public static function replace(s:String, sub:String, by:String):String {
        return s.split(sub).join(by);
    }
}