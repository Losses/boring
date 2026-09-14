package boring;

#if rust_output
import haxe.io.FPHelper;

typedef FpHelperDecomposed = {
    final mant24:Int;
    final exp2:Int;
};

/**
    An FPHelper bit-edge call whose argument is the business u32 Int while the
    runtime function takes the signed i32 domain. The named fpHelperArgument
    rule routes the call through the ordinary argument coercion, which
    reinterprets the bits. The bit edges read back from floatToI32 stay in the
    i32 domain, and a u32 struct field reinterprets the signed value at the
    literal boundary.
*/
class FPHelperRustOps {
    public static function valueOf(bits:Int):Float {
        return FPHelper.i32ToFloat(bits);
    }

    public static function decompose(value:Float):FpHelperDecomposed {
        final bits = FPHelper.floatToI32(value);
        final rawExponent = (bits >>> 23) & 0xff;
        final rawMantissa = bits & 0x7fffff;
        if (rawExponent == 0)
            return {mant24: rawMantissa, exp2: -149};
        return {mant24: rawMantissa | 0x800000, exp2: rawExponent - 150};
    }
}
#else
class FPHelperRustOps {}
#end
