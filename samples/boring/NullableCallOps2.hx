package boring;

class NullableCallOps2 {
    public static function nullableToStringResult(value:Null<NullableReceiver>):String {
        final v = value;
        return v.toString();
    }
}
