package own;

import own.CFArrayCallBacksPtr;
import own.CFDictionaryKeyCallBacksPtr;
import own.CFDictionaryValueCallBacksPtr;
import own.CTFontDescriptor;
import ptr.CFString;
import ptr.Types.CFAllocator;
import ptr.Types.CFArray;
import ptr.Types.CFDictionary;
import ptr.Types.CFIndex;
import ptr.Types.CFStringEncoding;
import ptr.Types.CGAffineTransform;
import ptr.Types.CTFont;
import ptr.Types.UInt8;
import swift.Buffer;
import swift.RawPointer;

extern class CF {
    @:topLevel
    static function CFStringCreateWithCString(alloc:Null<CFAllocator>, cStr:CString, encoding:CFStringEncoding):Null<CFString>;

    @:topLevel @:swiftName("CFStringBuiltInEncodings.UTF8.rawValue")
    static final kCFStringEncodingUTF8:CFStringEncoding;

    @:topLevel
    static function CFDataCreate(alloc:Null<CFAllocator>, bytes:Buffer<UInt8>, length:CFIndex):Null<CFData>;

    @:topLevel
    static function CFDataGetLength(data:CFData):CFIndex;

    @:topLevel @:swiftName("CFNumberType(rawValue: 3)!")
    static final kCFNumberSInt32Type:CFNumberType;

    @:topLevel @:swiftName("CFNumberType(rawValue: 6)!")
    static final kCFNumberDoubleType:CFNumberType;

    @:topLevel
    static function CFNumberCreate(alloc:Null<CFAllocator>, theType:CFNumberType, valuePtr:Buffer<Int>):Null<CFNumber>;

    @:topLevel @:swiftName("CFNumberCreate")
    static function CFNumberCreateDouble(alloc:Null<CFAllocator>, theType:CFNumberType, valuePtr:Buffer<Float>):Null<CFNumber>;

    @:topLevel
    static function CFNumberGetValue(number:CFNumber, theType:CFNumberType, valuePtr:Buffer<Int>):Bool;

    @:topLevel
    static function CFArrayCreate(alloc:Null<CFAllocator>, values:Buffer<Null<RawPointer>>, count:CFIndex, callBacks:Null<CFArrayCallBacks>):Null<CFArray>;

    @:topLevel
    static function CFDictionaryCreate(alloc:Null<CFAllocator>, keys:Buffer<Null<RawPointer>>, values:Buffer<Null<RawPointer>>, count:CFIndex, keyCallBacks:Null<CFDictionaryKeyCallBacks>, valueCallBacks:Null<CFDictionaryValueCallBacks>):Null<CFDictionary>;

    @:topLevel @:swiftName("CFArrayCreate")
    static function CFArrayCreateRetaining(alloc:Null<CFAllocator>, values:Buffer<Null<RawPointer>>, count:CFIndex, callBacks:CFArrayCallBacksPtr):Null<CFArray>;

    @:topLevel @:swiftName("CFDictionaryCreate")
    static function CFDictionaryCreateRetaining(alloc:Null<CFAllocator>, keys:Buffer<Null<RawPointer>>, values:Buffer<Null<RawPointer>>, count:CFIndex, keyCallBacks:CFDictionaryKeyCallBacksPtr, valueCallBacks:CFDictionaryValueCallBacksPtr):Null<CFDictionary>;

    @:topLevel
    static function CFArrayGetValueAtIndex(array:CFArray, index:CFIndex):Null<RawPointer>;

    @:topLevel
    static function CFDictionaryGetValue(dict:CFDictionary, key:RawPointer):Null<RawPointer>;

    @:topLevel
    static function CFEqual(a:CFString, b:CFString):Bool;

    @:topLevel @:swiftName("kCFTypeDictionaryKeyCallBacks")
    static final kCFTypeDictionaryKeyCallBacks:CFDictionaryKeyCallBacks;

    @:topLevel @:swiftName("kCFTypeDictionaryValueCallBacks")
    static final kCFTypeDictionaryValueCallBacks:CFDictionaryValueCallBacks;

    @:topLevel @:swiftName("kCFTypeArrayCallBacks")
    static final kCFTypeArrayCallBacks:CFArrayCallBacks;

    @:topLevel @:swiftName("kCTFontFamilyNameAttribute")
    static final kCTFontFamilyNameAttribute:CFString;

    @:topLevel @:swiftName("kCTFontTraitsAttribute")
    static final kCTFontTraitsAttribute:CFString;

    @:topLevel @:swiftName("kCTFontWeightTrait")
    static final kCTFontWeightTrait:CFString;

    @:topLevel @:swiftName("kCTFontFeatureSettingsAttribute")
    static final kCTFontFeatureSettingsAttribute:CFString;

    @:topLevel @:swiftName("kCTFontOpenTypeFeatureTag")
    static final kCTFontOpenTypeFeatureTag:CFString;

    @:topLevel @:swiftName("kCTFontOpenTypeFeatureValue")
    static final kCTFontOpenTypeFeatureValue:CFString;

    @:topLevel
    static function CTFontDescriptorCreateWithAttributes(attributes:CFDictionary):Null<CTFontDescriptor>;

    @:topLevel
    static function CTFontCreateWithFontDescriptor(descriptor:CTFontDescriptor, size:Float, matrix:Null<CGAffineTransform>):CTFont;

    @:topLevel
    static function CTFontCopyFamilyName(font:CTFont):CFString;
}
