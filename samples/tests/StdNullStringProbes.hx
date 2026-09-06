package tests;

import std.ReadOnlyArray;

class StdNullStringProbes {
    public static function nullScalar(value:Null<Int>):String {
        return Std.string(value);
    }

    public static function nullCollection(value:Null<ReadOnlyArray<String>>):String {
        return Std.string(value);
    }
}
