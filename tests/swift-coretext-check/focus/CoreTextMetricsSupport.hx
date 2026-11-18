package focus;

import focus.CFString;
import focus.CTFont;
import focus.CoreText;

/**
    The typed consumer. `:swiftImport` is declared here because this file
    names Core Text symbols; the module whose file does not name them carries
    no import line (the check asserts that for `Unrelated`).

    Each construction path is a separate line of the check: a native String
    bridged to CFString, a C string that needs a `withCString` bracket, and
    a UTF-16 buffer that needs `withUnsafeBufferPointer`.
**/
@:swiftImport("CoreText")
class CoreTextMetricsSupport {
    /** A font by PostScript name: the String -> CFString value bridge. */
    public static function namedFont(name:String, size:Float):CTFont {
        return CoreText.CTFontCreateWithName(name, size, null);
    }

    /** A font built through `CFStringCreateWithCString`: the bracket bridge. */
    public static function cStringFont(name:String, size:Float):Null<CTFont> {
        final text:Null<CFString> = CoreText.CFStringCreateWithCString(null, name, CoreText.kCFStringEncodingUTF8);
        if (text == null) {
            return null;
        }
        return CoreText.CTFontCreateWithName(text, size, null);
    }

    /** A font built through `CFStringCreateWithCharacters`: the buffer pointer bridge. */
    public static function unitsFont(units:String, size:Float):Null<CTFont> {
        final text:Null<CFString> = CoreText.CFStringCreateWithCharacters(null, units, CoreText.cfIndex(units.length));
        if (text == null) {
            return null;
        }
        return CoreText.CTFontCreateWithName(text, size, null);
    }

    /** The system UI font role: the CF_ENUM member through `:swiftName`. */
    public static function systemFont(size:Float):Null<CTFont> {
        return CoreText.CTFontCreateUIFontForLanguage(CoreText.kCTFontUIFontSystem, size, null);
    }

    public static function ascentOf(font:CTFont):Float {
        return CoreText.CTFontGetAscent(font);
    }

    public static function descentOf(font:CTFont):Float {
        return CoreText.CTFontGetDescent(font);
    }
}
