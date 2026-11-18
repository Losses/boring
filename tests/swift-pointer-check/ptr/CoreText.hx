package ptr;

import ptr.Types.CFAllocator;
import ptr.Types.CFArray;
import ptr.Types.CFAttributedString;
import ptr.Types.CFDictionary;
import ptr.Types.CFIndex;
import ptr.Types.CFRange;
import ptr.Types.CGFloat;
import ptr.Types.CGGlyph;
import ptr.Types.CGPoint;
import ptr.Types.CTLine;
import ptr.Types.CTRun;
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

    @:topLevel @:swiftName("Int")
    static function cfIndex(value:Int):CFIndex;

    @:topLevel @:swiftName("Int32")
    static function cfInt(value:CFIndex):Int;

    @:topLevel @:swiftName("Int32")
    static function glyphInt(value:CGGlyph):Int;
}
