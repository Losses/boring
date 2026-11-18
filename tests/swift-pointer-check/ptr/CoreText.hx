package ptr;

import ptr.Types.CFAllocator;
import ptr.Types.CFArray;
import ptr.Types.CFAttributedString;
import ptr.Types.CFDictionary;
import ptr.Types.CFIndex;
import ptr.Types.CFRange;
import ptr.Types.CFStringEncoding;
import ptr.Types.CGBitmapInfo;
import ptr.Types.CGColorSpace;
import ptr.Types.CGContext;
import ptr.Types.CGGlyph;
import ptr.Types.CGPoint;
import ptr.Types.CGRect;
import ptr.Types.CGAffineTransform;
import ptr.Types.CGFloat;
import ptr.Types.CTLine;
import ptr.Types.CTFont;
import ptr.Types.CTFontOrientation;
import ptr.Types.CTRun;
import ptr.Types.CChar;
import ptr.Types.UInt8;
import ptr.Types.UInt32;
import ptr.Types.UniChar;
import swift.Buffer;
import swift.Out;
import swift.RawPointer;

extern class CoreText {
    @:topLevel
    static function CFAttributedStringCreate(alloc:Null<CFAllocator>, str:CFString, attributes:Null<CFDictionary>):Null<CFAttributedString>;

    @:topLevel
    static function CTLineCreateWithAttributedString(attr:CFAttributedString):CTLine;

    @:topLevel
    static function CTLineGetTypographicBounds(line:CTLine, ascent:Null<Out<CGFloat>>, descent:Null<Out<CGFloat>>, leading:Null<Out<CGFloat>>):Float;

    @:topLevel
    static function CTLineGetGlyphRuns(line:CTLine):CFArray;

    @:topLevel
    static function CFArrayGetCount(array:CFArray):CFIndex;

    @:topLevel
    static function CFArrayGetValues(array:CFArray, range:CFRange, values:Out<Null<RawPointer>>):Void;

    @:topLevel
    static function CFRangeMake(location:CFIndex, length:CFIndex):CFRange;

    @:topLevel
    static function CTRunGetGlyphCount(run:CTRun):CFIndex;

    @:topLevel
    static function CTRunGetGlyphs(run:CTRun, range:CFRange, glyphs:Buffer<CGGlyph>):Void;

    @:topLevel
    static function CTRunGetPositions(run:CTRun, range:CFRange, positions:Buffer<CGPoint>):Void;

    @:topLevel
    static function CGPointMake(x:Float, y:Float):CGPoint;

    @:topLevel
    static function CGRectMake(x:Float, y:Float, width:Float, height:Float):CGRect;

    @:topLevel
    static function CFStringGetCString(string:CFString, buffer:Buffer<CChar>, bufferSize:CFIndex, encoding:CFStringEncoding):Bool;

    @:topLevel @:swiftName("CFStringBuiltInEncodings.UTF8.rawValue")
    static final kCFStringEncodingUTF8:CFStringEncoding;

    @:topLevel
    static function CTFontCreateWithName(name:CFString, size:Float, matrix:Null<CGAffineTransform>):CTFont;

    @:topLevel
    static function CTFontGetGlyphsForCharacters(font:CTFont, characters:Buffer<UniChar>, glyphs:Buffer<CGGlyph>, count:CFIndex):Bool;

    @:topLevel @:swiftName("CTFontOrientation.horizontal")
    static final kCTFontOrientationHorizontal:CTFontOrientation;

    @:topLevel
    static function CTFontGetBoundingRectsForGlyphs(font:CTFont, orientation:CTFontOrientation, glyphs:Buffer<CGGlyph>, boundingRects:Buffer<CGRect>, count:CFIndex):CGRect;

    @:topLevel
    static function CTFontDrawGlyphs(font:CTFont, glyphs:Buffer<CGGlyph>, positions:Buffer<CGPoint>, count:Int, context:CGContext):Void;

    @:topLevel
    static function CGColorSpaceCreateDeviceRGB():Null<CGColorSpace>;

    @:topLevel @:swiftName("CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)")
    static final kCGBitmapAlphaPremultipliedLast:CGBitmapInfo;

    @:topLevel @:swiftName("CGContext")
    @:swiftLabels("data|width|height|bitsPerComponent|bytesPerRow|space|bitmapInfo")
    static function CGContextCreate(data:Buffer<UInt8>, width:Int, height:Int, bitsPerComponent:Int, bytesPerRow:Int, space:CGColorSpace, bitmapInfo:CGBitmapInfo):Null<CGContext>;

    @:topLevel
    static function CGContextRelease(context:CGContext):Void;

    @:topLevel
    static function CGColorSpaceRelease(space:CGColorSpace):Void;

    @:topLevel @:swiftName("Int")
    static function cfIndex(value:Int):CFIndex;

    @:topLevel @:swiftName("Int32")
    static function cfInt(value:CFIndex):Int;

    @:topLevel @:swiftName("Int32")
    static function glyphInt(value:CGGlyph):Int;

    @:topLevel @:swiftName("Int32")
    static function charInt(value:CChar):Int;

    @:topLevel @:swiftName("Int32")
    static function byteInt(value:UInt8):Int;

    @:topLevel @:swiftName("UInt16")
    static function unicode(code:Int):UniChar;

    @:topLevel @:swiftName("Int")
    static function nativeInt(value:Int):Int;
}
