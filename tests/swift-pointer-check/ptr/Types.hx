package ptr;

@:swiftNativeType("CGFloat")
abstract CGFloat(Float) from Float to Float {}

@:swiftNativeType("Int")
abstract NativeInt(Int) from Int to Int {}

@:swiftNativeType("CGGlyph")
abstract CGGlyph(Int) from Int to Int {}

@:swiftNativeType("CGPoint")
extern class CGPoint {
    var x:Float;
    var y:Float;
}

extern class CTLine {}
extern class CTRun {}
extern class CFAttributedString {}
extern class CFDictionary {}
extern class CFAllocator {}
extern class CFArray {}
extern class CFRange {}
extern class CFIndex {}
