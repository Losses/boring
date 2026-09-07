package boring;

import std.Test;

class MathNaNTestSupport {
    public static function assertNaN(value:Float, message:String):Void
        Test.equals(true, value != value, message);

    public static function assertNegativeZero(value:Float, message:String):Void {
        Test.equals(0.0, value, message);
        Test.equals(true, 1.0 / value < 0.0, message + " (sign)");
    }

    public static function assertPositiveZero(value:Float, message:String):Void {
        Test.equals(0.0, value, message);
        Test.equals(true, 1.0 / value > 0.0, message + " (sign)");
    }
}
