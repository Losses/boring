package own;

import ptr.Types.CTFont;
import swift.Opaque;

class TakeRetainedNegative {
    public static function main():Void {}

    public static function take(font:CTFont):CTFont {
        return Opaque.takeRetained(Opaque.passUnretained(font));
    }
}
