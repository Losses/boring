package boring;

enum SelfRecMark {
    plain;
    wrap(inner:SelfRecMark);
    nest(list:Array<SelfRecMark>);
}

class StdStringSelfRecOps {
    public static function markText(value:SelfRecMark):String
        return Std.string(value);
}
