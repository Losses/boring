package boring;

import std.ReadOnlyArray;

class StdStringOps {
    public static function concatString(value:String):String
        return "string=" + Std.string(value);

    public static function concatInt(value:Int):String
        return "int=" + Std.string(value);

    public static function concatFloat(value:Float):String
        return "float=" + Std.string(value);

    public static function concatBool(value:Bool):String
        return "bool=" + Std.string(value);

    public static function concatEnum(value:FloatWidth):String
        return "enum=" + Std.string(value);

    public static function stringValue(value:String):String
        return Std.string(value);

    public static function intValue(value:Int):String
        return Std.string(value);

    public static function floatValue(value:Float):String
        return Std.string(value);

    public static function floatForms():Array<String> {
        return [
            Std.string(2.0),
            Std.string(0.0),
            Std.string(-0.0),
            Std.string(2.5),
            Std.string(-1.25),
            Std.string(1e20),
            Std.string(1e21),
            Std.string(1e-6),
            Std.string(1e-7)
        ];
    }

    public static function boolValue(value:Bool):String
        return Std.string(value);

    public static function enumValue(value:FloatWidth):String
        return Std.string(value);

    public static function enumMatchesConstructor():Bool {
        return Std.string(FloatWidth.F32) == "F32";
    }

    // Native Haxe omits the ruled space after commas; the oracle uses
    // the ruled literal while every generated target exercises Std.string.
    public static function intArray():String {
        final values:Array<Int> = [1, 2, 3];
        #if boring_oracle return "[1, 2, 3]"; #else return Std.string(values); #end
    }

    public static function stringArray():String {
        final values:Array<String> = ["alpha", "beta"];
        #if boring_oracle return "[alpha, beta]"; #else return Std.string(values); #end
    }

    public static function floatArray():String {
        final values:Array<Float> = [1.5, 2.25];
        #if boring_oracle return "[1.5, 2.25]"; #else return Std.string(values); #end
    }

    public static function boolArray():String {
        final values:Array<Bool> = [true, false];
        #if boring_oracle return "[true, false]"; #else return Std.string(values); #end
    }

    public static function enumArray():String {
        final values:Array<FloatWidth> = [FloatWidth.F64, FloatWidth.F16];
        #if boring_oracle return "[F64, F16]"; #else return Std.string(values); #end
    }

    public static function emptyArray():String {
        return emptyArrayValue([]);
    }

    static function emptyArrayValue(values:Array<Int>):String {
        #if boring_oracle return "[]"; #else return Std.string(values); #end
    }

    public static function nestedArray():String {
        final values:Array<Array<Int>> = [[1, 2], [3]];
        #if boring_oracle return "[[1, 2], [3]]"; #else return Std.string(values); #end
    }

    public static function readOnlyArray():String {
        final values:ReadOnlyArray<String> = ["alpha", "beta"];
        #if boring_oracle return "[alpha, beta]"; #else return Std.string(values); #end
    }
}
