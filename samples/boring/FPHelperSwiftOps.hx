package boring;

#if swift_output
import haxe.io.FPHelper;

/**
    The binary32 bit edges lower through the runtime module pair on
    every configuration (stdlib/05): the Haxe FPHelper calls become
    unqualified `floatToI32` / `i32ToFloat` and the runtime module must
    define them.
*/
class FPHelperSwiftOps {
    public static function bitsOf(value:Float):Int {
        return FPHelper.floatToI32(value);
    }

    public static function valueOf(bits:Int):Float {
        return FPHelper.i32ToFloat(bits);
    }

    public static function roundTrip(value:Float):Float {
        return FPHelper.i32ToFloat(FPHelper.floatToI32(value));
    }
}
#else
class FPHelperSwiftOps {}
#end
