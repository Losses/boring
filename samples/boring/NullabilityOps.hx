package boring;

class NullabilityOps {
    public static function nullableToString(value:Null<NullableReceiver>):String {
        return value.toString();
    }
    
    public static function nullableToStringWithParam(value:Null<NullableReceiver>, suffix:String):String {
        return value.toString() + suffix;
    }

    #if kotlin_output
    public static function narrowedFloat(values:Array<Null<Float>>, index:Int):Float {
        final value:Float = values[index] == null ? 0 : values[index];
        return value;
    }
    #end
}
