package ptr;

import ptr.Types.CFArray;
import ptr.Types.CGPoint;
import ptr.Types.CGGlyph;
import ptr.Types.CFAttributedString;
import ptr.Types.CFIndex;
import ptr.Types.CGFloat;
import ptr.Types.CTLine;
import ptr.Types.CTRun;
import std.Console;
import swift.Buffer;
import swift.Opaque;
import swift.Out;
import swift.RawPointer;

@:swiftImport("CoreText", "CoreFoundation")
class OutFixture {
    static function show(value:Float):String {
        return Std.string(value);
    }

    static function zeroGlyph():CGGlyph {
        return 0;
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
    }
}
