package boring;

#if swift_output
/**
    Haxe `%` accepts a Float operand; Swift has no floating `%` operator, so
    the remainder lowers onto `truncatingRemainder(dividingBy:)`.
*/
class FloatModOps {
    public static function even(value:Float):Bool {
        return value % 2.0 == 0.0;
    }

    public static function rem(value:Float, divisor:Float):Float {
        return value % divisor;
    }
}
#else
class FloatModOps {}
#end
