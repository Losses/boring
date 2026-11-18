package own;

import ptr.CFString;
import ptr.Types.CFAllocator;
import ptr.Types.CFArray;
import ptr.Types.CFDictionary;
import ptr.Types.CFIndex;
import ptr.Types.CFStringEncoding;
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

    @:topLevel
    static function CFNumberCreate(alloc:Null<CFAllocator>, theType:CFNumberType, valuePtr:Buffer<Int>):Null<CFNumber>;

    @:topLevel
    static function CFNumberGetValue(number:CFNumber, theType:CFNumberType, valuePtr:Buffer<Int>):Bool;

    @:topLevel
    static function CFArrayCreate(alloc:Null<CFAllocator>, values:Buffer<Null<RawPointer>>, count:CFIndex, callBacks:Null<CFArrayCallBacks>):Null<CFArray>;

    @:topLevel
    static function CFDictionaryCreate(alloc:Null<CFAllocator>, keys:Buffer<Null<RawPointer>>, values:Buffer<Null<RawPointer>>, count:CFIndex, keyCallBacks:Null<CFDictionaryKeyCallBacks>, valueCallBacks:Null<CFDictionaryValueCallBacks>):Null<CFDictionary>;

    @:topLevel
    static function CFArrayGetValueAtIndex(array:CFArray, index:CFIndex):Null<RawPointer>;

    @:topLevel
    static function CFDictionaryGetValue(dict:CFDictionary, key:RawPointer):Null<RawPointer>;
}
