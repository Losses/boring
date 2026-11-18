package focus;

/**
    The Core Text entry points the check drives, declared the way the Swift
    target already models a platform call: an extern class whose statics
    carry `:topLevel`, so a reference renders the platform symbol.

    Every spelling that the C header cannot express as a bare Swift name goes
    through `:swiftName`: the CF_ENUM member and the CFIndex initializer
    seam. The 48.0 size is a Double at the extern boundary, which Swift's
    SE-0307 CGFloat interchangeability converts at the typed position.
**/
extern class CoreText {
    @:topLevel
    static function CTFontCreateWithName(name:CFString, size:Float, matrix:Null<CGAffineTransform>):CTFont;

    @:topLevel
    static function CTFontCreateUIFontForLanguage(uiFontType:CTFontUIFontType, size:Float, language:Null<CFString>):Null<CTFont>;

    @:topLevel
    static function CTFontGetAscent(font:CTFont):Float;

    @:topLevel
    static function CTFontGetDescent(font:CTFont):Float;

    @:topLevel
    static function CFStringCreateWithCString(alloc:Null<CFAllocator>, cStr:CString, encoding:CFStringEncoding):Null<CFString>;

    @:topLevel
    static function CFStringCreateWithCharacters(alloc:Null<CFAllocator>, chars:UniCharPointer, count:CFIndex):Null<CFString>;

    /** The CF_ENUM member: the C name is not in Swift scope. */
    @:topLevel @:swiftName("CTFontUIFontType.system")
    static final kCTFontUIFontSystem:CTFontUIFontType;

    /** The CF_ENUM member behind CFStringCreateWithCString's encoding. */
    @:topLevel @:swiftName("CFStringBuiltInEncodings.UTF8.rawValue")
    static final kCFStringEncodingUTF8:CFStringEncoding;

    /** An initializer-shaped seam from the target's Int32 to CFIndex's Int. */
    @:topLevel @:swiftName("Int")
    static function cfIndex(value:Int):CFIndex;
}
