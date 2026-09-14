package boring;

#if rust_output
/**
    An Int argument that lowers in the signed i32 domain while the parameter
    slot is the business u32 domain. A wrapping binop result and a negated
    i32-domain local reinterpret their bits at the call boundary. The named
    signedIntArgument rule covers each call position.
*/
class SignedIntArgumentOps {
    public static function offsetTotal(base:Int, delta:Int):Int {
        return base + delta;
    }

    public static function fromIndex(text:String, offset:Int):Int {
        final index = text.indexOf("x");
        return offsetTotal(-index, offset);
    }

    public static function shifted(text:String, offset:Int):Int {
        final index = text.indexOf("x");
        return offsetTotal(index + offset, offset);
    }
}
#else
class SignedIntArgumentOps {}
#end
