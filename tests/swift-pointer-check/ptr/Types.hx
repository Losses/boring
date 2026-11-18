package ptr;

@:swiftNativeType("CGFloat")
abstract CGFloat(Float) from Float to Float {}

@:swiftNativeType("CGGlyph")
abstract CGGlyph(Int) from Int to Int {}

@:swiftNativeType("CChar")
abstract CChar(Int) from Int to Int {}

@:swiftNativeType("UniChar")
abstract UniChar(Int) from Int to Int {}

@:swiftNativeType("UInt8")
abstract UInt8(Int) from Int to Int {}

@:swiftNativeType("UInt32")
abstract UInt32(Int) from Int to Int {}

@:swiftNativeType("CGPoint")
extern class CGPoint {
    var x:Float;
    var y:Float;
}

@:swiftNativeType("CGSize")
extern class CGSize {
    var width:Float;
    var height:Float;
}

@:swiftNativeType("CGRect")
extern class CGRect {
    var origin:CGPoint;
    var size:CGSize;
}

extern class CTLine {}
extern class CTRun {}
extern class CTFont {}
extern class CTFontOrientation {}
extern class CGContext {}
extern class CGColorSpace {}
extern class CGBitmapInfo {}
extern class CGAffineTransform {}
extern class CFAttributedString {}
extern class CFDictionary {}
extern class CFAllocator {}
extern class CFArray {}
extern class CFRange {}
extern class CFIndex {}
extern class CFStringEncoding {}
