package boring;

class NullableArrayOps {
    public static function literalMixed():Array<Null<Int>>
        return [1, null, 3];

    public static function literalSingleNull():Array<Null<Int>>
        return [null];

    public static function fromNullableVar(value:Null<Int>):Array<Null<Int>>
        return [value, 5, null];

    public static function nullableStrings():Array<Null<String>>
        return ["a", null, "c"];

    public static function elementMatches(value:Array<Null<Int>>, index:Int, expected:Null<Int>):Bool
        return value[index] == expected;

    public static function stringElementMatches(value:Array<Null<String>>, index:Int, expected:Null<String>):Bool
        return value[index] == expected;
}
