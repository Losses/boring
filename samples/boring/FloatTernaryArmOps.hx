package boring;

#if swift_output
/**
    A ternary whose true arm is an Int field and whose false arm is a real
    literal. Haxe unifies the result to the module real, while the Int arm
    still renders as an integer.
**/
class FloatTernaryArmOps {
    static var penalty:Int = 4;

    public static function cost(flag:Bool):Float {
        final value = flag ? penalty : 0.0;
        return value;
    }

    public static function doubled(flag:Bool):Float {
        final value = flag ? penalty : 0.0;
        return value * 2.0;
    }
}
#else
class FloatTernaryArmOps {}
#end
