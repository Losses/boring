package ptr;

import ptr.Types.CFArray;
import ptr.Types.CGColorSpace;
import ptr.Types.CGContext;
import ptr.Types.CGGlyph;
import ptr.Types.CGPoint;
import ptr.Types.CGRect;
import ptr.Types.CGFloat;
import ptr.Types.CChar;
import ptr.Types.CFAttributedString;
import ptr.Types.CFIndex;
import ptr.Types.CTLine;
import ptr.Types.CTRun;
import ptr.Types.UInt8;
import ptr.Types.UniChar;
import std.Console;
import swift.Buffer;
import swift.Opaque;
import swift.Out;
import swift.RawPointer;

@:swiftImport("CoreText", "CoreFoundation", "CoreGraphics")
class OutFixture {
    static function show(value:Float):String {
        return Std.string(value);
    }

    static function zeroGlyph():CGGlyph {
        return 0;
    }

    static function zeroCChar():CChar {
        return 0;
    }

    static function zeroUni():UniChar {
        return 0;
    }

    static function zeroRect():CGRect {
        return CoreText.CGRectMake(0.0, 0.0, 0.0, 0.0);
    }

    static function whiteByte():UInt8 {
        return 255;
    }

    public static function main():Void {
        final attributed:Null<CFAttributedString> = CoreText.CFAttributedStringCreate(null, "Hello", null);
        if (attributed == null) {
            Console.log("a1 attributed=null");
            return;
        }
        final line = CoreText.CTLineCreateWithAttributedString(attributed);
        final ascent:Out<CGFloat> = new Out<CGFloat>(0.0);
        final descent:Out<CGFloat> = new Out<CGFloat>(0.0);
        final leading:Out<CGFloat> = new Out<CGFloat>(0.0);
        final advance = CoreText.CTLineGetTypographicBounds(line, ascent, descent, leading);
        final ignored = CoreText.CTLineGetTypographicBounds(line, null, null, null);
        final ascentAgain:Out<CGFloat> = new Out<CGFloat>(0.0);
        final descentAgain:Out<CGFloat> = new Out<CGFloat>(0.0);
        final leadingAgain:Out<CGFloat> = new Out<CGFloat>(0.0);
        final advanceAgain = CoreText.CTLineGetTypographicBounds(line, ascentAgain, descentAgain, leadingAgain);
        Console.log("a1 ascent=" + show(ascent.value)
            + " descent=" + show(descent.value)
            + " leading=" + show(leading.value)
            + " advance=" + show(advance)
            + " ignored=" + show(ignored)
            + " stable=" + Std.string(advance == advanceAgain
                && ascent.value == ascentAgain.value
                && descent.value == descentAgain.value
                && leading.value == leadingAgain.value));

        final runs:CFArray = CoreText.CTLineGetGlyphRuns(line);
        final count:Int = CoreText.cfInt(CoreText.CFArrayGetCount(runs));
        final values:Out<Null<RawPointer>> = new Out<Null<RawPointer>>(null);
        if (count <= 0) {
            Console.log("a2 runs=0");
            return;
        }
        CoreText.CFArrayGetValues(runs, CoreText.CFRangeMake(CoreText.cfIndex(0), CoreText.cfIndex(1)), values);
        final run:CTRun = Opaque.takeUnretained(values.value);
        final glyphCount:Int = CoreText.cfInt(CoreText.CTRunGetGlyphCount(run));
        if (glyphCount <= 0) {
            Console.log("a2 glyphs=0");
            return;
        }
        final glyphs:Buffer<CGGlyph> = Buffer.alloc(glyphCount, zeroGlyph());
        final positions:Buffer<CGPoint> = Buffer.alloc(glyphCount, CoreText.CGPointMake(0.0, 0.0));
        CoreText.CTRunGetGlyphs(run, CoreText.CFRangeMake(CoreText.cfIndex(0), CoreText.cfIndex(0)), glyphs);
        CoreText.CTRunGetPositions(run, CoreText.CFRangeMake(CoreText.cfIndex(0), CoreText.cfIndex(0)), positions);
        final firstGlyph:Int = CoreText.glyphInt(glyphs.get(0));
        final firstX:Float = positions.get(0).x;
        final lastX:Float = positions.get(glyphCount - 1).x;
        Console.log("a1 tstar2 count=" + Std.string(count) + " runGlyphs=" + Std.string(glyphCount));
        Console.log("a2 glyphs=" + Std.string(glyphCount)
            + " first=" + Std.string(firstGlyph)
            + " firstX=" + show(firstX)
            + " lastX=" + show(lastX)
            + " ordered=" + Std.string(lastX >= firstX));
        glyphs.free(glyphCount);
        positions.free(glyphCount);

        // A3: an out buffer written by CFStringGetCString round-trips the
        // original UTF-8 bytes.
        final cbuf:Buffer<CChar> = Buffer.alloc(16, zeroCChar());
        final written = CoreText.CFStringGetCString("Helvetica", cbuf, CoreText.cfIndex(16), CoreText.kCFStringEncodingUTF8);
        final expectedText = [72, 101, 108, 118, 101, 116, 105, 99, 97];
        var same = 0;
        for (i in 0...9) {
            if (CoreText.charInt(cbuf.get(i)) == expectedText[i]) {
                same++;
            }
        }
        Console.log("a3 ok=" + Std.string(written) + " same=" + Std.string(same));
        cbuf.free(16);

        // A4: a const glyph buffer in, a CGRect array out, field reads.
        final font = CoreText.CTFontCreateWithName("Helvetica", 48.0, null);
        final n = 5;
        final expectedHello = [72, 101, 108, 108, 111];
        final chars:Buffer<UniChar> = Buffer.alloc(n, zeroUni());
        for (i in 0...n) {
            chars.set(i, CoreText.unicode(expectedHello[i]));
        }
        final hglyphs:Buffer<CGGlyph> = Buffer.alloc(n, zeroGlyph());
        final mapped = CoreText.CTFontGetGlyphsForCharacters(font, chars, hglyphs, CoreText.cfIndex(n));
        final rects:Buffer<CGRect> = Buffer.alloc(n, zeroRect());
        CoreText.CTFontGetBoundingRectsForGlyphs(font, CoreText.kCTFontOrientationHorizontal, hglyphs, rects, CoreText.cfIndex(n));
        var nonEmpty = 0;
        var firstW = 0.0;
        for (i in 0...n) {
            final rect = rects.get(i);
            final w = rect.size.width * 1.0;
            final h = rect.size.height * 1.0;
            if (i == 0) {
                firstW = w;
            }
            if (w > 0.0 && h > 0.0) {
                nonEmpty++;
            }
        }
        Console.log("a4 mapped=" + Std.string(mapped) + " nonEmpty=" + Std.string(nonEmpty) + " firstW=" + show(firstW));
        chars.free(n);
        rects.free(n);

        // A5: draw the mapped glyphs into a bitmap context and read the
        // pixels back through the buffer we own.
        final width = 64;
        final height = 64;
        final pixelCount = width * height * 4;
        final pixels:Buffer<UInt8> = Buffer.alloc(pixelCount, whiteByte());
        final space:Null<CGColorSpace> = CoreText.CGColorSpaceCreateDeviceRGB();
        var changed = 0;
        if (space != null) {
            final ctx:Null<CGContext> = CoreText.CGContextCreate(
                pixels,
                CoreText.nativeInt(width),
                CoreText.nativeInt(height),
                CoreText.nativeInt(8),
                CoreText.nativeInt(width * 4),
                space,
                CoreText.kCGBitmapAlphaPremultipliedLast);
            if (ctx != null) {
                final drawPositions:Buffer<CGPoint> = Buffer.alloc(n, CoreText.CGPointMake(10.0, 10.0));
                CoreText.CTFontDrawGlyphs(font, hglyphs, drawPositions, CoreText.nativeInt(n), ctx);
                for (i in 0...pixelCount) {
                    if (CoreText.byteInt(pixels.get(i)) != 255) {
                        changed++;
                    }
                }
                drawPositions.free(n);
            }
            // CGContext and CGColorSpace are ARC-managed in Swift; the
            // explicit Release calls are unavailable.
        }
        Console.log("a5 changed=" + Std.string(changed));
        pixels.free(pixelCount);
        hglyphs.free(n);
    }
}
