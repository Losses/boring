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

    public static function absValue(a:Float):Float
        return Math.abs(a);

    public static function absOfInts(a:Int):Float
        return Math.abs(a);
}
