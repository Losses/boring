package boring;

class MathNaNOps {
    public static function minOf(a:Float, b:Float):Float
        return Math.min(a, b);

    public static function maxOf(a:Float, b:Float):Float
        return Math.max(a, b);

    public static function minInts(a:Int, b:Int):Float
        return Math.min(a, b);

    public static function maxInts(a:Int, b:Int):Float
        return Math.max(a, b);

    // Literal-only constant edges (constant folding, warning-zero H1): the
    // operands are all literals, so every target can render the result as its
    // own NaN/infinity constant instead of an operation the toolchains warn
    // about (kotlinc "division by zero"; swiftc literal conversion
    // underflow/overflow).
    public static function constantNan():Float
        return 0.0 / 0.0;

    public static function constantPosInf():Float
        return 1.0 / 0.0;

    public static function constantNegInf():Float
        return -1.0 / 0.0;

    /** Above every binary32 magnitude; f32 conversions flush to +infinity. */
    public static function constantOverflow():Float
        return 1e300;

    /** Below every binary32 magnitude; f32 conversions flush to +zero. */
    public static function constantUnderflow():Float
        return 1e-300;
}
