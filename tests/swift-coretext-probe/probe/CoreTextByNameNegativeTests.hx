package probe;

import probe.CFString;
import probe.CTFont;
import probe.CoreText;

/**
    The negative control: the same `CTFontCreateWithName` call written without
    the hand-written `CFString` bridge, i.e. exactly what the emitter produces
    from a plain Haxe `String` argument. The forced cast is the only spelling
    the subset offers, and it traps at run time because `[UInt16]` does not
    bridge to `CFString`. The macOS job runs this on purpose and records the
    trap; it is never part of the positive probe.
**/
@:testOnly
class CoreTextByNameNegativeTests {
    @:test
    public static function createFontWithoutBridge():Void {
        final font:CTFont = CoreText.CTFontCreateWithName(cast("Helvetica", CFString), 48.0, null);
        final ascent:Float = CoreText.CTFontGetAscent(font);
        final descent:Float = CoreText.CTFontGetDescent(font);
        final line = "helvetica ascent=" + Std.string(ascent) + " descent=" + Std.string(descent);
        std.Fs.makeDirs("out/coretext-probe-byname");
        std.Fs.writeText("out/coretext-probe-byname/metrics.txt", line + "\n");
    }
}
