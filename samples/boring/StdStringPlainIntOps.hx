package boring;

enum PlainIntMark {
    plain;
    leaf(value:Int);
}

class StdStringPlainIntOps {
    public static function intMarkText(value:PlainIntMark):String
        return Std.string(value);
}
