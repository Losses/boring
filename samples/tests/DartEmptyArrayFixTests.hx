package tests;

import boring.DartEmptyArrayFixOps;
import std.Test;

class DartEmptyArrayFixTests {
    @:test("empty array arguments retain their element type")
    public static function emptyArrayArgument():Void {
        Test.equals(0, DartEmptyArrayFixOps.emptyArrayArgument());
    }
}
