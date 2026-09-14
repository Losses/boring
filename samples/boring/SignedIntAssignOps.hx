package boring;

#if rust_output
/**
    A u32 Int local assigned an i32-domain expression. The local was declared
    from a plain integer literal, so the assignment reinterprets the signed
    rendering back into the business u32 domain. The named
    signedIntAssignment rule covers the assignment boundary.
*/
class SignedIntAssignOps {
    public static function advance(text:String):Int {
        var start = 0;
        final found = text.indexOf("x");
        start = found + 1;
        return start;
    }
}
#else
class SignedIntAssignOps {}
#end
