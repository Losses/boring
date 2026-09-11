package boring;

#if swift_output
class IntFloatCtorHolder {
    public final value:Float;

    public function new(value:Float) {
        this.value = value;
    }
}

/**
    Haxe promotes an Int argument into a Float constructor parameter; the
    Swift initializer needs the explicit widening conversion.
*/
class IntFloatCtorOps {
    public static function ctorValue(value:Int):Float {
        return new IntFloatCtorHolder(value).value;
    }

    public static function sum(value:Int):Float {
        return new IntFloatCtorHolder(value).value + 0.25;
    }
}
#else
class IntFloatCtorOps {}
#end
