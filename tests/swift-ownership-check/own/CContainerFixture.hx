package own;

import own.CF;
import own.CFData;
import own.CFNumber;
import own.CTFontDescriptor;
import ptr.CFString;
import ptr.CoreText;
import ptr.Types.CFArray;
import ptr.Types.CFDictionary;
import ptr.Types.CTFont;
import ptr.Types.UInt8;
import std.Console;
import swift.Buffer;
import swift.Opaque;
import swift.RawPointer;

@:swiftImport("CoreFoundation", "CoreText", "CoreGraphics")
class CContainerFixture {
    static function noPointer():Null<RawPointer> {
        return null;
    }

    static function pointers(count:Int):Buffer<Null<RawPointer>> {
        return Buffer.alloc(count, noPointer());
    }

    public static function main():Void {
        final family:Null<CFString> = CF.CFStringCreateWithCString(null, "Helvetica", CF.kCFStringEncodingUTF8);
        if (family == null) {
            Console.log("c1 family=null");
            return;
        }

        // C1: a family-attributes dictionary that retains its values.
        final c1Keys = pointers(1);
        c1Keys.set(0, Opaque.passUnretained(CF.kCTFontFamilyNameAttribute));
        final c1Values = pointers(1);
        c1Values.set(0, Opaque.passUnretained(family));
        final c1Attrs:Null<CFDictionary> = CF.CFDictionaryCreateRetaining(null, c1Keys, c1Values, CoreText.cfIndex(1), 0, 0);
        final c1Desc:Null<CTFontDescriptor> = c1Attrs == null ? null : CF.CTFontDescriptorCreateWithAttributes(c1Attrs);
        final c1Font:Null<CTFont> = c1Desc == null ? null : CF.CTFontCreateWithFontDescriptor(c1Desc, 48.0, null);
        final c1Name:Null<CFString> = c1Font == null ? null : CF.CTFontCopyFamilyName(c1Font);
        final c1Same = c1Name != null && CF.CFEqual(c1Name, family);
        Console.log("c1 family=" + Std.string(c1Same));

        // C2: a CFNumber weight plus a traits dictionary and an attributes dictionary.
        final weightValue:Buffer<Float> = Buffer.alloc(1, 0.0);
        weightValue.set(0, 0.62);
        final weight:Null<CFNumber> = CF.CFNumberCreateDouble(null, CF.kCFNumberDoubleType, weightValue);
        var c2Traits:Null<CFDictionary> = null;
        if (weight != null) {
            final traitKeys = pointers(1);
            traitKeys.set(0, Opaque.passUnretained(CF.kCTFontWeightTrait));
            final traitValues = pointers(1);
            traitValues.set(0, Opaque.passUnretained(weight));
            c2Traits = CF.CFDictionaryCreateRetaining(null, traitKeys, traitValues, CoreText.cfIndex(1), 0, 0);
        }
        var c2Font:Null<CTFont> = null;
        if (c2Traits != null) {
            final keys = pointers(2);
            keys.set(0, Opaque.passUnretained(CF.kCTFontFamilyNameAttribute));
            keys.set(1, Opaque.passUnretained(CF.kCTFontTraitsAttribute));
            final values = pointers(2);
            values.set(0, Opaque.passUnretained(family));
            values.set(1, Opaque.passUnretained(c2Traits));
            final attrs:Null<CFDictionary> = CF.CFDictionaryCreateRetaining(null, keys, values, CoreText.cfIndex(2), 0, 0);
            if (attrs != null) {
                final desc:Null<CTFontDescriptor> = CF.CTFontDescriptorCreateWithAttributes(attrs);
                if (desc != null) {
                    c2Font = CF.CTFontCreateWithFontDescriptor(desc, 48.0, null);
                }
            }
        }
        Console.log("c2 font=" + Std.string(c2Font != null));

        // C3: an OpenType feature dictionary inside a settings array.
        final tag:Null<CFString> = CF.CFStringCreateWithCString(null, "liga", CF.kCFStringEncodingUTF8);
        final featureValue:Buffer<Int> = Buffer.alloc(1, 0);
        featureValue.set(0, 1);
        final featureNumber:Null<CFNumber> = CF.CFNumberCreate(null, CF.kCFNumberSInt32Type, featureValue);
        var c3Feature:Null<CFDictionary> = null;
        if (tag != null && featureNumber != null) {
            final keys = pointers(2);
            keys.set(0, Opaque.passUnretained(CF.kCTFontOpenTypeFeatureTag));
            keys.set(1, Opaque.passUnretained(CF.kCTFontOpenTypeFeatureValue));
            final values = pointers(2);
            values.set(0, Opaque.passUnretained(tag));
            values.set(1, Opaque.passUnretained(featureNumber));
            c3Feature = CF.CFDictionaryCreateRetaining(null, keys, values, CoreText.cfIndex(2), 0, 0);
        }
        var c3Settings:Null<CFArray> = null;
        if (c3Feature != null) {
            final values = pointers(1);
            values.set(0, Opaque.passUnretained(c3Feature));
            c3Settings = CF.CFArrayCreateRetaining(null, values, CoreText.cfIndex(1), 0);
        }
        var c3Font:Null<CTFont> = null;
        if (c3Settings != null) {
            final keys = pointers(2);
            keys.set(0, Opaque.passUnretained(CF.kCTFontFamilyNameAttribute));
            keys.set(1, Opaque.passUnretained(CF.kCTFontFeatureSettingsAttribute));
            final values = pointers(2);
            values.set(0, Opaque.passUnretained(family));
            values.set(1, Opaque.passUnretained(c3Settings));
            final attrs:Null<CFDictionary> = CF.CFDictionaryCreateRetaining(null, keys, values, CoreText.cfIndex(2), 0, 0);
            if (attrs != null) {
                final desc:Null<CTFontDescriptor> = CF.CTFontDescriptorCreateWithAttributes(attrs);
                if (desc != null) {
                    c3Font = CF.CTFontCreateWithFontDescriptor(desc, 48.0, null);
                }
            }
        }
        Console.log("c3 font=" + Std.string(c3Font != null));

        // C4: an array of two CFStrings, order preserved.
        final one:Null<CFString> = CF.CFStringCreateWithCString(null, "One", CF.kCFStringEncodingUTF8);
        final two:Null<CFString> = CF.CFStringCreateWithCString(null, "Two", CF.kCFStringEncodingUTF8);
        var c4Array:Null<CFArray> = null;
        if (one != null && two != null) {
            final values = pointers(2);
            values.set(0, Opaque.passUnretained(one));
            values.set(1, Opaque.passUnretained(two));
            c4Array = CF.CFArrayCreateRetaining(null, values, CoreText.cfIndex(2), 0);
        }
        final c4Count = c4Array == null ? -1 : CoreText.cfInt(CoreText.CFArrayGetCount(c4Array));
        final c4First:Null<RawPointer> = c4Array == null ? null : CF.CFArrayGetValueAtIndex(c4Array, CoreText.cfIndex(0));
        final c4Second:Null<RawPointer> = c4Array == null ? null : CF.CFArrayGetValueAtIndex(c4Array, CoreText.cfIndex(1));
        final c4Order = c4First != null && c4Second != null && one != null && two != null
            && CF.CFEqual(Opaque.takeUnretained(c4First), one)
            && CF.CFEqual(Opaque.takeUnretained(c4Second), two);
        Console.log("c4 count=" + Std.string(c4Count) + " order=" + Std.string(c4Order));
    }
}
