package boring;

class MathIntWideningOps {
    public static function floorOf(x:Int):Int {
        return Math.floor(x);
    }

    public static function ceilOf(x:Int):Int {
        return Math.ceil(x);
    }

    public static function sqrtOf(x:Int):Float {
        return Math.sqrt(x);
    }

    public static function nanOf(x:Int):Bool {
        return Math.isNaN(x);
    }

    public static function finiteOf(x:Int):Bool {
        return Math.isFinite(x);
    }
}
