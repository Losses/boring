package tests;

import boring.StdStringSelfRecOps;
import boring.StdStringSelfRecOps.SelfRecMark;
import std.Test;

class StdStringSelfRecTests {
    @:test("cyclic enum constructor printed forms")
    public static function forms():Void {
        Test.equals("plain", StdStringSelfRecOps.markText(plain));
        Test.equals("wrap(inner=wrap(inner=plain))", StdStringSelfRecOps.markText(wrap(wrap(plain))));
        Test.equals("nest(list=[plain, wrap(inner=plain)])", StdStringSelfRecOps.markText(nest([plain, wrap(plain)])));
    }
}
