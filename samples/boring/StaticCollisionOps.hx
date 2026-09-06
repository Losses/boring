package boring;

class StaticCollisionFloat {
    public static function ic(value:Float):String {
        return "float:" + Std.string(value);
    }
}

class StaticCollisionInt {
    public static function ic(value:Int):String {
        return "int:" + Std.string(value);
    }
}

class StaticCollisionOps {
    public static function floatValue(value:Float):String {
        return StaticCollisionFloat.ic(value);
    }

    public static function intValue(value:Int):String {
        return StaticCollisionInt.ic(value);
    }
}
