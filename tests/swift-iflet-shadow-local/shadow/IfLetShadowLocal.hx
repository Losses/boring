package shadow;

/**
    Minimal shape of the if-let shadowed-local force-unwrap leak: an optional
    numeric local guarded by 'if (x != null)' lowers to 'if let x = x', making
    the Swift binding non-optional inside the branch. Value uses must render
    bare (or through the Float conversion), never 'x!'.
*/
class IfLetShadowLocal {
    /** return site: shadowed optional local returned, never x! */
    public static function pickReturn(x:Null<Float>):Float {
        if (x != null) {
            return x;
        }
        return -1.0;
    }

    /** operand site: shadowed optional local as an arithmetic operand */
    public static function pickOperand(x:Null<Float>):Float {
        if (x != null) {
            return x + 1.0;
        }
        return -1.0;
    }

    /** multi-site: the shadowed local reused across two operand uses in one return */
    public static function pickMulti(x:Null<Float>):Float {
        if (x != null) {
            return x + x;
        }
        return -1.0;
    }
}
