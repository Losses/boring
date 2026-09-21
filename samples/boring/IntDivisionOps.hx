package boring;

/**
    The Float quotient of two Int operands. Haxe types `Int / Int` as
    Float, while Kotlin renders `/` on two Int operands as truncating Int
    division, so the target widens an operand before the division.
*/
class IntDivisionOps {
    /** The quotient of two Int operands, read as the Float Haxe promises. */
    public static function quotient(numerator:Int, denominator:Int):Float {
        return numerator / denominator;
    }

    /** A layout offset: an Int product divided by an Int span. */
    public static function offset(width:Int, index:Int, span:Int):Float {
        return width * index / span;
    }

    /** The quotient taking part in a Float multiply and add. */
    public static function scaled(width:Int, index:Int, span:Int, bias:Float):Float {
        return width * index / span * 2.0 + bias;
    }

    /** The truncating spelling of the same quotient, which stays integral. */
    public static function truncated(numerator:Int, denominator:Int):Int {
        return Std.int(numerator / denominator);
    }

    /** The Int remainder, which keeps its integer rendering. */
    public static function remainder(numerator:Int, denominator:Int):Int {
        return numerator % denominator;
    }

    /** The floored quotient of two Int operands. */
    public static function floored(numerator:Int, denominator:Int):Float {
        return Math.floor(numerator / denominator);
    }
}
