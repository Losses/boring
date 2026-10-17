package boring;

enum SelfRecMark {
    plain;
    wrap(inner:SelfRecMark);
    nest(list:Array<SelfRecMark>);
}

enum SelfRecInt {
    leaf(value:Int);
    next(inner:SelfRecInt);
}

class StdStringSelfRecOps {
    public static function markText(value:SelfRecMark):String
        return Std.string(value);

    public static function intMarkText(value:SelfRecInt):String
        return Std.string(value);
}
