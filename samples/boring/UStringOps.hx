package boring;

import std.UString;

/**
 * The three content classes of docs/specs/stdlib/10-unicode-string-access.md:
 * pure ASCII, BMP CJK, and supplementary CJK. Every operation routes through
 * std.UString, so each side answers over the character sequence and never
 * over platform storage.
 */
class UStringOps {
    public static function asciiCount():Int {
        return UString.count("tiqian");
    }

    public static function bmpCount():Int {
        return UString.count("提椠排版");
    }

    public static function supplementaryCount():Int {
        return UString.count("𠀀一𠀁");
    }

    public static function codeAt(text:String, index:Int):Null<Int> {
        return UString.at(text, index);
    }

    public static function middleSlice(text:String):String {
        return UString.slice(text, 1, 3);
    }

    public static function clampedSlice(text:String):String {
        return UString.slice(text, -2, 99);
    }

    public static function reversedText(text:String):String {
        var codes = UString.toCodePoints(text);
        final reversed = new Array<Int>();
        for (index in 0...codes.length) {
            reversed.push(codes[codes.length - 1 - index]);
        }
        return UString.fromCodePoints(reversed);
    }

    public static function roundTrip(text:String):String {
        return UString.fromCodePoints(UString.toCodePoints(text));
    }

    /**
     * The substring tier of docs/specs/features/08-strings-and-unicode.md:
     * String.substring keeps haxe positions (UTF-16 code units) on every
     * target. The bounds below sit on code-point boundaries, the domain
     * where all four targets agree.
     */
    public static function substringRange(text:String, from:Int, to:Int):String {
        return text.substring(from, to);
    }

    public static function substringFrom(text:String, from:Int):String {
        return text.substring(from);
    }

    public static function substringLiteral():String {
        return "tiqian".substring(1, 3);
    }

    public static function substringNegativeStart():String {
        return "abcdef".substring(-2, 3);
    }

    public static function substringLongEnd():String {
        return "abcdef".substring(2, 20);
    }

    public static function substringSwappedBounds():String {
        return "abcdef".substring(5, 2);
    }

    public static function substringOmittedEnd():String {
        return "abcdef".substring(-3);
    }
}
