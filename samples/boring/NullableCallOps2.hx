package boring;

class NullableCallOps2 {
    public static function nullableToStringResult(value:Null<NullableReceiver>):String {
        final v = value;
        return v.toString();
    }

    public static function normalizedToStringResult(value:Null<NullableReceiver>):String {
        final v = value == null ? new NullableReceiver() : value;
        return v.toString();
    }

    public static function guardedToStringResult(value:Null<NullableReceiver>):String {
        if (value == null) {
            return "missing receiver";
        }
        return value.toString();
    }
}
