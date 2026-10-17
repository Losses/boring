package tests;

import boring.StdStringSelfRecOps;
import boring.StdStringSelfRecOps.SelfRecMark;
import boring.StdStringSelfRecOps.SelfRecInt;
import std.Test;

class StdStringSelfRecTests {
    @:test("cyclic enum constructor printed forms")
    public static function forms():Void {
        Test.equals("plain", StdStringSelfRecOps.markText(plain));
        Test.equals("wrap(inner=wrap(inner=plain))", StdStringSelfRecOps.markText(wrap(wrap(plain))));
        Test.equals("nest(list=[plain, wrap(inner=plain)])", StdStringSelfRecOps.markText(nest([plain, wrap(plain)])));
    }

    @:test("cyclic enum Int payload signed rendering")
    public static function intPayload():Void {
        Test.equals("leaf(value=-1)", StdStringSelfRecOps.intMarkText(leaf(-1)));
        Test.equals("leaf(value=0)", StdStringSelfRecOps.intMarkText(leaf(0)));
        Test.equals("next(inner=leaf(value=-1))", StdStringSelfRecOps.intMarkText(next(leaf(-1))));
    }
}
