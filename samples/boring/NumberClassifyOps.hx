package boring;

class NumberClassifyOps {
    public static function finite(value:Float):Bool
        return Math.isFinite(value);

    public static function nan(value:Float):Bool
        return Math.isNaN(value);
}
