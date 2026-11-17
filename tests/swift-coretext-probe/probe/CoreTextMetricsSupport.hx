package probe;

import probe.CGAffineTransform;
import probe.CTFont;
import probe.CTFontUIFontType;
import probe.CFString;
import probe.CoreText;
import probe.CoreTextStringBridge;

/**
    The typed seam between Core Text's `CGFloat` and the target's `Double`.

    The Swift target has no width-specific float type: Haxe `Float` is Swift
    `Double` everywhere, while every Core Text metric accessor returns
    `CGFloat`. Swift's SE-0307 interchangeability converts between the two at a
    typed position, so every helper below names its own return or parameter
    type and the conversion happens at that seam.
**/
@:testOnly
class CoreTextMetricsSupport {
    /** A system UI font at the given size, or null when Core Text declines. */
    public static function createSystemFont(size:Float):Null<CTFont> {
        return CoreText.CTFontCreateUIFontForLanguage(CoreText.kCTFontUIFontSystem, size, null);
    }

    /** A font by PostScript name at the given size. */
    public static function createNamedFont(name:String, size:Float):CTFont {
        return CoreText.CTFontCreateWithName(CoreTextStringBridge.coreTextString(name), size, null);
    }

    /** The font's ascent in points. */
    public static function ascentOf(font:CTFont):Float {
        return CoreText.CTFontGetAscent(font);
    }

    /** The font's descent in points. */
    public static function descentOf(font:CTFont):Float {
        return CoreText.CTFontGetDescent(font);
    }
}
