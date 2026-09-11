package boring;

class MathMinMaxOps {
    public static function smaller(a:Float, b:Float):Float
        return Math.min(a, b);

    public static function larger(a:Float, b:Float):Float
        return Math.max(a, b);

    public static function smallerOfInts(a:Int, b:Int):Float
        return Math.min(a, b);

    public static function largerOfInts(a:Int, b:Int):Float
        return Math.max(a, b);

    /** An int-typed expression beside a literal zero: both operands
        widen so the NaN guard has a floating member to test. The shape
        is Swift-side: the other targets lower the int literal through
        their own numeric tower. */
    #if swift_output
    public static function deficitOfInts(a:Int, b:Int):Float
        return Math.max(a - b, 0);
    #end

    public static function absValue(a:Float):Float
        return Math.abs(a);

    public static function absOfInts(a:Int):Float
        return Math.abs(a);

    public static function power(a:Float, b:Float):Float
        return Math.pow(a, b);

    public static function powerOfInts(a:Int, b:Int):Float
        return Math.pow(a, b);

    public static function rounded(a:Float):Int
        return Math.round(a);

    public static function floored(a:Float):Int
        return Math.floor(a);

    public static function ceiled(a:Float):Int
        return Math.ceil(a);
}
