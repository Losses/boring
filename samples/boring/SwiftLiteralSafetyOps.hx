package boring;

class SwiftLiteralSafetyOps {
    public static function trailingPoint():Float {
        return 0.;
    }

    public static function controlText():String {
        return "before" + String.fromCharCode(8) + "after";
    }
}
