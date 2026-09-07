package boring;

class NumericConversionWidening {
    #if kotlin
    public static function compareEqual(a:Float, b:Int):Bool {
        return a == b;
    }

    public static function compareNotEqual(a:Float, b:Int):Bool {
        return a != b;
    }

    public static function returnIntAsFloat(x:Int):Float {
        return x;
    }

    public static function initFloat():Float {
        final x:Float = 16;
        return x;
    }

    public static function assignIntToFloat():Float {
        var x:Float = 0;
        x = 42;
        return x;
    }

    public static function floatParam(value:Float):Float {
        return value + 1.0;
    }

    public static function callFloatParam():Float {
        return floatParam(8);
    }
    #end
}
