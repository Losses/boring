package ptr;

import ptr.Types.CTLine;
import ptr.Types.CGFloat;
import swift.Out;

@:swiftImport("CoreText")
class OutNegative {
    public static function main():Void {}

    public static function bounds(line:CTLine):Float {
        // A constructor call has no addressable storage: the generator must
        // reject it, so it never emits `&Out(...).value`.
        return CoreText.CTLineGetTypographicBounds(line, new Out<CGFloat>(0.0), null, null);
    }
}
