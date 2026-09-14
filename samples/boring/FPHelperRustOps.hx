package boring;

#if rust_output
import haxe.io.FPHelper;

/**
    An FPHelper bit-edge call whose argument is the business u32 Int while the
    runtime function takes the signed i32 domain. The named fpHelperArgument
    rule routes the call through the ordinary argument coercion, which
    reinterprets the bits.
*/
class FPHelperRustOps {
    public static function valueOf(bits:Int):Float {
        return FPHelper.i32ToFloat(bits);
    }
}
#else
class FPHelperRustOps {}
#end
