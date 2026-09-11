package boring;

class NullableCallOps {
    public static function nullableToStringResult(value:Null<NullableReceiver>):String {
        return value.toString();
    }
}
