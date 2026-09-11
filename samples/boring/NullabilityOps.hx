package boring;

class NullabilityOps {
    public static function nullableToString(value:Null<NullableReceiver>):String {
        return value.toString();
    }
    
    public static function nullableToStringWithParam(value:Null<NullableReceiver>, suffix:String):String {
        return value.toString() + suffix;
    }
}
