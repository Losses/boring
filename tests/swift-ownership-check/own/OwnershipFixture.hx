package own;

import own.CF;
import own.CFData;
import own.CFNumber;
import ptr.CFString;
import ptr.CoreText;
import ptr.Types.CFArray;
import ptr.Types.CFAttributedString;
import ptr.Types.CFIndex;
import ptr.Types.CGColorSpace;
import ptr.Types.CGContext;
import ptr.Types.CGGlyph;
import ptr.Types.CGPoint;
import ptr.Types.CTLine;
import ptr.Types.CTFont;
import ptr.Types.CTRun;
import ptr.Types.UInt8;
import ptr.Types.UniChar;
import std.Console;
import swift.Buffer;
import swift.Opaque;
import swift.RawPointer;

@:swiftImport("CoreFoundation", "CoreText", "CoreGraphics")
class OwnershipFixture {
    static function show(value:Float):String {
        return Std.string(value);
    }

    static function oneByte():UInt8 {
        return 1;
    }

    static function zeroGlyph():CGGlyph {
        return 0;
    }

    static function zeroUni():UniChar {
        return 0;
    }

    static function noPointer():Null<RawPointer> {
        return null;
    }

    static function whiteByte():UInt8 {
        return 255;
    }

    public static function main():Void {
        final text:Null<CFString> = CF.CFStringCreateWithCString(null, "Helvetica", CF.kCFStringEncodingUTF8);
        if (text == null) {
            Console.log("b1 text=null");
            return;
        }
        final font = CoreText.CTFontCreateWithName(text, 48.0, null);
        final fonts:std.HashMap<Int, CTFont> = new std.HashMap();
        fonts.set(0, font);
        final attributed:Null<CFAttributedString> = CoreText.CFAttributedStringCreate(null, text, null);
        if (attributed == null) {
            Console.log("b1 attributed=null");
            return;
        }
        final line = CoreText.CTLineCreateWithAttributedString(attributed);
        final lines:std.HashMap<Int, CTLine> = new std.HashMap();
        lines.set(0, line);

        final bytes:Buffer<UInt8> = Buffer.alloc(4, oneByte());
        final data:Null<CFData> = CF.CFDataCreate(null, bytes, CoreText.cfIndex(4));

        final nums:Buffer<Int> = Buffer.alloc(1, 0);
        nums.set(0, 42);
        final number:Null<CFNumber> = CF.CFNumberCreate(null, CF.kCFNumberSInt32Type, nums);

        final values:Buffer<Null<RawPointer>> = Buffer.alloc(1, noPointer());
        values.set(0, Opaque.passUnretained(text));
        final array:Null<CFArray> = CF.CFArrayCreate(null, values, CoreText.cfIndex(1), null);

        final keys:Buffer<Null<RawPointer>> = Buffer.alloc(1, noPointer());
        keys.set(0, Opaque.passUnretained(text));
        final dictValues:Buffer<Null<RawPointer>> = Buffer.alloc(1, noPointer());
        dictValues.set(0, Opaque.passUnretained(text));
        final dict:Null<ptr.Types.CFDictionary> = CF.CFDictionaryCreate(null, keys, dictValues, CoreText.cfIndex(1), null, null);

        final expectedHello = [72, 101, 108, 108, 111];
        final chars:Buffer<UniChar> = Buffer.alloc(5, zeroUni());
        for (i in 0...5) {
            chars.set(i, CoreText.unicode(expectedHello[i]));
        }
        final hglyphs:Buffer<CGGlyph> = Buffer.alloc(5, zeroGlyph());
        final mapped = CoreText.CTFontGetGlyphsForCharacters(font, chars, hglyphs, CoreText.cfIndex(5));

        final numberOut:Buffer<Int> = Buffer.alloc(1, 0);
        final numberOk = number == null ? false : CF.CFNumberGetValue(number, CF.kCFNumberSInt32Type, numberOut);
        final dataLen = data == null ? -1 : CoreText.cfInt(CF.CFDataGetLength(data));
        final arrayCount = array == null ? -1 : CoreText.cfInt(CoreText.CFArrayGetCount(array));
        final arrayRaw:Null<RawPointer> = array == null ? null : CF.CFArrayGetValueAtIndex(array, CoreText.cfIndex(0));
        final arrayText:Null<CFString> = arrayRaw == null ? null : Opaque.takeUnretained(arrayRaw);
        final dictRaw:Null<RawPointer> = dict == null ? null : CF.CFDictionaryGetValue(dict, Opaque.passUnretained(text));
        final dictText:Null<CFString> = dictRaw == null ? null : Opaque.takeUnretained(dictRaw);
        final heldFont = fonts.get(0);
        final heldLine = lines.get(0);
        Console.log("b1 mapped=" + Std.string(mapped)
            + " data=" + Std.string(dataLen)
            + " number=" + Std.string(numberOut.get(0))
            + " numberOk=" + Std.string(numberOk)
            + " array=" + Std.string(arrayCount)
            + " arrayText=" + Std.string(arrayText != null)
            + " dictText=" + Std.string(dictText != null)
            + " font=yes line=yes");

        // B2: the two borrow shapes. The array read hands back a borrowed run.
        final runs:CFArray = CoreText.CTLineGetGlyphRuns(line);
        final runRaw:Null<RawPointer> = CoreText.cfInt(CoreText.CFArrayGetCount(runs)) > 0
            ? CF.CFArrayGetValueAtIndex(runs, CoreText.cfIndex(0))
            : null;
        final runGlyphs = runRaw == null ? 0 : CoreText.cfInt(CoreText.CTRunGetGlyphCount(Opaque.takeUnretained(runRaw)));

        // The UI boundary passes an unretained context address; the engine
        // converts it back for the call and never stores or releases it.
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
                final raw:RawPointer = Opaque.passUnretained(ctx);
                final back:CGContext = Opaque.takeUnretained(raw);
                final positions:Buffer<CGPoint> = Buffer.alloc(5, CoreText.CGPointMake(10.0, 10.0));
                CoreText.CTFontDrawGlyphs(font, hglyphs, positions, CoreText.nativeInt(5), back);
                for (i in 0...pixelCount) {
                    if (CoreText.byteInt(pixels.get(i)) != 255) {
                        changed++;
                    }
                }
                positions.free(5);
            }
        }
        Console.log("b2 runGlyphs=" + Std.string(runGlyphs) + " changed=" + Std.string(changed));

        // B3: the cache holds class references; the map retains on insert and
        // releases on removal, with no explicit retain/release call.
        final cache:std.HashMap<Int, CTLine> = new std.HashMap();
        cache.set(1, line);
        final cached = cache.get(1);
        cache.remove(1);
        final after = cache.get(1);
        Console.log("b3 cached=" + Std.string(cached != null) + " after=" + (after == null ? "null" : "held"));

        chars.free(5);
        hglyphs.free(5);
        pixels.free(pixelCount);
    }
}
