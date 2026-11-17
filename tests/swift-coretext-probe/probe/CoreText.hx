package probe;

/**
    The Core Text entry points the probe calls, declared the way the Swift
    target already models a platform call: an extern class whose static
    functions carry `:topLevel`, so a reference site renders the bare symbol
    (StaticFunctionMarkers, features/10).

    The declared argument and return names are the Swift spellings of the C
    typedefs; an extern declaration renders nothing and its signature is
    emitted verbatim at the call site.
**/
extern class CoreText {
    /** A font from a PostScript name. Returns a non-optional font. */
    @:topLevel
    static function CTFontCreateWithName(name:CFString, size:Float, matrix:Null<CGAffineTransform>):CTFont;

    /** A UI font of the given role and size; null when Core Text declines. */
    @:topLevel
    static function CTFontCreateUIFontForLanguage(uiFontType:CTFontUIFontType, size:Float, language:Null<CFString>):Null<CTFont>;

    /** The font's ascent in points (a `CGFloat`). */
    @:topLevel
    static function CTFontGetAscent(font:CTFont):Float;

    /** The font's descent in points (a `CGFloat`). */
    @:topLevel
    static function CTFontGetDescent(font:CTFont):Float;

    /** The system UI font role constant. */
    @:topLevel
    static final kCTFontUIFontSystem:CTFontUIFontType;
}
